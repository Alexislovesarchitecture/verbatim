import Foundation

enum LocalLogicError: LocalizedError {
    case missingTranscript
    case runtimeUnavailable(String)
    case modelMissing(String)
    case emptyResponse
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTranscript:
            return "No transcript to format."
        case .runtimeUnavailable(let detail):
            return "Could not run local model: \(detail)"
        case .modelMissing(let model):
            return "Local model '\(model)' is not installed. Pull it with `ollama pull \(model)`."
        case .emptyResponse:
            return "Local model returned an empty response."
        case .parseFailed(let message):
            return "Local model JSON parse failed: \(message)"
        }
    }
}

struct LocalLogicRuntimeStatus {
    let isReachable: Bool
    let hasExpectedModel: Bool
    let availableModels: [String]
    let message: String
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class OllamaLocalLogicService {
    private let ollamaBinaryName: String

    init(ollamaBinaryName: String = "ollama") {
        self.ollamaBinaryName = ollamaBinaryName
    }

    func checkRuntime(expectedModelID: String) async -> LocalLogicRuntimeStatus {
        do {
            let result = try await runOllama(arguments: ["list"])
            guard result.statusCode == 0 else {
                let detail = firstNonEmpty(result.stderr, result.stdout, defaultValue: "Failed to run `ollama list`.")
                return LocalLogicRuntimeStatus(
                    isReachable: false,
                    hasExpectedModel: false,
                    availableModels: [],
                    message: detail
                )
            }

            let models = parseModelNames(fromOllamaList: result.stdout)
            let expectedModel = ollamaModelName(for: expectedModelID)
            let hasExpected = models.contains(where: { $0 == expectedModel || $0.hasPrefix(expectedModel + ":") })
            let message = hasExpected
                ? "Local runtime ready."
                : "Ollama is running, but model '\(expectedModel)' is missing."

            return LocalLogicRuntimeStatus(
                isReachable: true,
                hasExpectedModel: hasExpected,
                availableModels: models,
                message: message
            )
        } catch {
            return LocalLogicRuntimeStatus(
                isReachable: false,
                hasExpectedModel: false,
                availableModels: [],
                message: "Ollama CLI is not available. Install/start Ollama first."
            )
        }
    }

    func format(
        transcript: Transcript,
        modelID: String,
        settings: LogicSettings
    ) async throws -> FormattedOutput {
        guard !transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLogicError.missingTranscript
        }

        let expectedModel = ollamaModelName(for: modelID)
        let runtime = await checkRuntime(expectedModelID: modelID)
        guard runtime.isReachable else {
            throw LocalLogicError.runtimeUnavailable(runtime.message)
        }
        guard runtime.hasExpectedModel else {
            throw LocalLogicError.modelMissing(expectedModel)
        }

        let firstPrompt = formattingPrompt(transcript: transcript, settings: settings)
        let firstOutput = try await runGenerate(model: expectedModel, prompt: firstPrompt)

        if let parsed = decodeFormattedOutput(from: firstOutput) {
            return parsed
        }

        let repair = repairPrompt(for: firstOutput)
        let repairedOutput = try await runGenerate(model: expectedModel, prompt: repair)
        if let repaired = decodeFormattedOutput(from: repairedOutput) {
            return repaired
        }

        return FormattedOutput(
            clean_text: transcript.rawText,
            format: "paragraph",
            bullets: [],
            self_corrections: [],
            low_confidence_spans: [],
            notes: ["Local model response was not valid schema JSON. Returned raw transcript."]
        )
    }

    private func runGenerate(model: String, prompt: String) async throws -> String {
        let result = try await runOllama(arguments: ["run", model], standardInput: prompt)
        guard result.statusCode == 0 else {
            let detail = firstNonEmpty(result.stderr, result.stdout, defaultValue: "Unknown local model runtime error.")
            throw LocalLogicError.runtimeUnavailable(detail)
        }

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            throw LocalLogicError.emptyResponse
        }
        return output
    }

    private func runOllama(arguments: [String], standardInput: String? = nil) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [self.ollamaBinaryName] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let inputPipe = Pipe()
            process.standardInput = inputPipe

            do {
                try process.run()
            } catch {
                throw LocalLogicError.runtimeUnavailable("Could not launch `\(self.ollamaBinaryName)`.")
            }

            if let standardInput {
                if let data = standardInput.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
            }
            inputPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return ProcessResult(
                statusCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }.value
    }

    private func parseModelNames(fromOllamaList text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let columns = line.split(whereSeparator: \.isWhitespace)
                return columns.first.map(String.init)
            }
    }

    private func decodeFormattedOutput(from text: String) -> FormattedOutput? {
        if let data = text.data(using: .utf8),
           let output = try? JSONDecoder().decode(FormattedOutput.self, from: data) {
            return output
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let json = String(text[start...end])
            if let data = json.data(using: .utf8),
               let output = try? JSONDecoder().decode(FormattedOutput.self, from: data) {
                return output
            }
        }

        return nil
    }

    private func formattingPrompt(transcript: Transcript, settings: LogicSettings) -> String {
        let transcriptBody = transcript.segments.isEmpty
            ? transcript.rawText
            : transcript.segments.map { segment in
                let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return speaker.isEmpty ? text : "[\(speaker)] \(text)"
            }.joined(separator: "\n")

        let fillerRule = settings.removeFillerWords ? "remove filler words when not meaning-bearing" : "preserve filler words"
        let listRule = settings.autoDetectLists ? "auto-detect list structure" : "do not force list structure"
        let correctionRule: String
        switch settings.selfCorrectionMode {
        case .keepAll:
            correctionRule = "preserve all self-corrections"
        case .keepFinal:
            correctionRule = "keep final corrected phrasing"
        case .annotate:
            correctionRule = "annotate self-corrections in self_corrections"
        }

        return """
        Return JSON only, no markdown.
        Schema:
        {
          "clean_text": "string",
          "format": "paragraph|bullets|mixed",
          "bullets": ["string"],
          "self_corrections": ["string"],
          "low_confidence_spans": ["string"],
          "notes": ["string"]
        }
        Rules:
        - Preserve meaning; do not invent facts.
        - \(fillerRule).
        - \(listRule).
        - \(correctionRule).
        - If unsure, keep source wording.

        Transcript:
        \(transcriptBody)
        """
    }

    private func repairPrompt(for rawText: String) -> String {
        """
        Convert the following text into valid JSON only.
        Required schema:
        {
          "clean_text": "string",
          "format": "paragraph|bullets|mixed",
          "bullets": ["string"],
          "self_corrections": ["string"],
          "low_confidence_spans": ["string"],
          "notes": ["string"]
        }
        Text:
        \(rawText)
        """
    }

    private func ollamaModelName(for modelID: String) -> String {
        switch modelID {
        case "gpt-oss-20b":
            return "gpt-oss:20b"
        default:
            return modelID
        }
    }

    private func firstNonEmpty(_ first: String, _ second: String, defaultValue: String) -> String {
        let firstTrimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if !firstTrimmed.isEmpty { return firstTrimmed }
        let secondTrimmed = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondTrimmed.isEmpty { return secondTrimmed }
        return defaultValue
    }
}

private struct ProcessResult {
    let statusCode: Int32
    let stdout: String
    let stderr: String
}
