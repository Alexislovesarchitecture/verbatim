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

protocol LocalLLMRefineServiceProtocol: Sendable {
    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        modelID: String
    ) async throws -> LLMResult
}

final class OllamaLocalLogicService: LocalLLMRefineServiceProtocol, @unchecked Sendable {
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

        let profile = PromptProfile(
            id: "cleanup",
            version: 1,
            name: "Cleanup",
            styleCategory: nil,
            enabled: true,
            outputMode: .text,
            instructionPrefix: "You are a text cleanup assistant. Rules: Do not paraphrase or rewrite. Do not add new information or commitments. Apply the provided glossary mappings exactly (case-insensitive). Add only necessary punctuation and capitalization. Return only the corrected text. No commentary.",
            schema: nil,
            options: nil
        )

        let result = try await refine(
            deterministicText: transcript.rawText,
            contextPack: ContextPack(
                activeAppName: "Unknown App",
                bundleID: "unknown.bundle",
                styleCategory: .other,
                windowTitle: nil,
                focusedElementRole: nil,
                punctuationMode: settings.outputFormat == .paragraph ? "sentence" : "auto",
                fillerRemovalEnabled: settings.removeFillerWords,
                autoDetectLists: settings.autoDetectLists,
                glossary: [],
                sessionMemory: []
            ),
            profile: profile,
            modelID: modelID
        )

        let cleanText = result.text ?? transcript.rawText
        return FormattedOutput(
            clean_text: cleanText,
            format: "paragraph",
            bullets: [],
            self_corrections: [],
            low_confidence_spans: [],
            notes: result.status == .fallback ? ["Returned deterministic fallback output."] : []
        )
    }

    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        modelID: String
    ) async throws -> LLMResult {
        guard !deterministicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLogicError.missingTranscript
        }

        let startedAt = Date()
        let expectedModel = ollamaModelName(for: modelID)
        let runtime = await checkRuntime(expectedModelID: modelID)
        guard runtime.isReachable else {
            throw LocalLogicError.runtimeUnavailable(runtime.message)
        }
        guard runtime.hasExpectedModel else {
            throw LocalLogicError.modelMissing(expectedModel)
        }

        let promptPayload = payload(profile: profile, contextPack: contextPack, text: deterministicText)
        switch profile.outputMode {
        case .text:
            let firstPrompt = "\(profile.instructionPrefix)\n\n\(promptPayload)"
            let output = try await runGenerate(model: expectedModel, prompt: firstPrompt)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            if trimmed.isEmpty {
                return LLMResult(
                    text: deterministicText,
                    json: nil,
                    status: .fallback,
                    validationStatus: .notApplicable,
                    tokens: 0,
                    cachedTokens: 0,
                    latencyMs: latencyMs,
                    profileID: profile.id,
                    profileVersion: profile.version,
                    modelID: modelID,
                    fromCache: false
                )
            }

            return LLMResult(
                text: trimmed,
                json: nil,
                status: .success,
                validationStatus: .notApplicable,
                tokens: 0,
                cachedTokens: 0,
                latencyMs: latencyMs,
                profileID: profile.id,
                profileVersion: profile.version,
                modelID: modelID,
                fromCache: false
            )

        case .jsonSchema, .jsonObjectFallback:
            let jsonPrompt = "\(profile.instructionPrefix)\n\n\(promptPayload)\nOutput JSON only."
            let firstOutput = try await runGenerate(model: expectedModel, prompt: jsonPrompt)
            let firstJSON = extractJSONObject(from: firstOutput)

            if validateJSON(firstJSON, profile: profile) {
                return LLMResult(
                    text: nil,
                    json: firstJSON,
                    status: .success,
                    validationStatus: .valid,
                    tokens: 0,
                    cachedTokens: 0,
                    latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                    profileID: profile.id,
                    profileVersion: profile.version,
                    modelID: modelID,
                    fromCache: false
                )
            }

            let repairPrompt = """
            Return valid JSON only.
            Use the same schema requirements as before.
            Invalid JSON:
            \(firstOutput)
            """
            let repairedOutput = try await runGenerate(model: expectedModel, prompt: repairPrompt)
            let repairedJSON = extractJSONObject(from: repairedOutput)

            if validateJSON(repairedJSON, profile: profile) {
                return LLMResult(
                    text: nil,
                    json: repairedJSON,
                    status: .repaired,
                    validationStatus: .valid,
                    tokens: 0,
                    cachedTokens: 0,
                    latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                    profileID: profile.id,
                    profileVersion: profile.version,
                    modelID: modelID,
                    fromCache: false
                )
            }

            return LLMResult(
                text: deterministicText,
                json: nil,
                status: .fallback,
                validationStatus: .invalid,
                tokens: 0,
                cachedTokens: 0,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                profileID: profile.id,
                profileVersion: profile.version,
                modelID: modelID,
                fromCache: false
            )
        }
    }

    private func payload(profile: PromptProfile, contextPack: ContextPack, text: String) -> String {
        var value: [String: Any] = [
            "context": [
                "active_app": contextPack.activeAppName,
                "bundle_id": contextPack.bundleID,
                "style_category": contextPack.styleCategory.rawValue,
                "window_title": contextPack.windowTitle ?? "",
                "focused_element_role": contextPack.focusedElementRole ?? "",
            ],
            "text": text,
        ]

        if !contextPack.glossary.isEmpty {
            value["glossary"] = contextPack.glossary.map { ["from": $0.from, "to": $0.to] }
        }

        if let options = profile.options?.mapValues({ $0.toAnyValue() }), !options.isEmpty {
            value["options"] = options
        }

        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func validateJSON(_ jsonText: String, profile: PromptProfile) -> Bool {
        guard let data = jsonText.data(using: .utf8) else {
            return false
        }

        if profile.id == "action_items" {
            return (try? JSONDecoder().decode(ActionItemsPayload.self, from: data)) != nil
        }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
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
