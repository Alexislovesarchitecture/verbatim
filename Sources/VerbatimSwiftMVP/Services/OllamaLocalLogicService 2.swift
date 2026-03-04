import Foundation

enum LocalLogicError: LocalizedError {
    case invalidEndpoint
    case missingTranscript
    case requestFailed(Error)
    case runtimeUnavailable(String)
    case modelMissing(String)
    case invalidResponse
    case emptyResponse
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Local logic endpoint is invalid. Use a URL like http://localhost:11434."
        case .missingTranscript:
            return "No transcript to format."
        case .requestFailed(let error):
            return "Local logic request failed: \(error.localizedDescription)"
        case .runtimeUnavailable(let detail):
            return "Could not reach local runtime: \(detail)"
        case .modelMissing(let model):
            return "Local model '\(model)' is not available in Ollama. Pull it first."
        case .invalidResponse:
            return "Local runtime returned an invalid response."
        case .emptyResponse:
            return "Local runtime returned an empty response."
        case .parseFailed(let message):
            return "Local logic JSON parse failed: \(message)"
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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkRuntime(baseURLString: String, expectedModelID: String) async -> LocalLogicRuntimeStatus {
        guard let baseURL = normalizedURL(from: baseURLString) else {
            return LocalLogicRuntimeStatus(
                isReachable: false,
                hasExpectedModel: false,
                availableModels: [],
                message: LocalLogicError.invalidEndpoint.localizedDescription
            )
        }

        let tagsURL = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LocalLogicRuntimeStatus(
                    isReachable: false,
                    hasExpectedModel: false,
                    availableModels: [],
                    message: LocalLogicError.invalidResponse.localizedDescription
                )
            }
            guard (200..<300).contains(http.statusCode) else {
                let serverMessage = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return LocalLogicRuntimeStatus(
                    isReachable: false,
                    hasExpectedModel: false,
                    availableModels: [],
                    message: "Ollama responded with status \(http.statusCode). \(serverMessage)"
                )
            }

            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let modelNames = (decoded.models ?? []).map(\.name)
            let expected = ollamaModelName(for: expectedModelID)
            let hasExpected = modelNames.contains(where: { $0 == expected || $0.hasPrefix(expected + ":") })

            let message: String
            if hasExpected {
                message = "Local runtime ready."
            } else if modelNames.isEmpty {
                message = "Local runtime reachable. No models installed."
            } else {
                message = "Runtime reachable. Missing model '\(expected)'."
            }

            return LocalLogicRuntimeStatus(
                isReachable: true,
                hasExpectedModel: hasExpected,
                availableModels: modelNames,
                message: message
            )
        } catch {
            return LocalLogicRuntimeStatus(
                isReachable: false,
                hasExpectedModel: false,
                availableModels: [],
                message: "Could not reach local runtime at \(baseURL.absoluteString)."
            )
        }
    }

    func format(
        transcript: Transcript,
        modelID: String,
        settings: LogicSettings,
        baseURLString: String
    ) async throws -> FormattedOutput {
        guard !transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLogicError.missingTranscript
        }
        guard let baseURL = normalizedURL(from: baseURLString) else {
            throw LocalLogicError.invalidEndpoint
        }

        let runtimeModel = ollamaModelName(for: modelID)
        let preflight = await checkRuntime(baseURLString: baseURL.absoluteString, expectedModelID: modelID)
        guard preflight.isReachable else {
            throw LocalLogicError.runtimeUnavailable(preflight.message)
        }
        guard preflight.hasExpectedModel else {
            throw LocalLogicError.modelMissing(runtimeModel)
        }

        let primaryPrompt = formattingPrompt(transcript: transcript, settings: settings)
        let firstResponse = try await generate(baseURL: baseURL, model: runtimeModel, prompt: primaryPrompt)

        if let parsed = decodeFormattedOutput(from: firstResponse) {
            return parsed
        }

        let repairPrompt = repairPrompt(for: firstResponse)
        let repairedResponse = try await generate(baseURL: baseURL, model: runtimeModel, prompt: repairPrompt)
        if let repaired = decodeFormattedOutput(from: repairedResponse) {
            return repaired
        }

        return FormattedOutput(
            clean_text: transcript.rawText,
            format: "paragraph",
            bullets: [],
            self_corrections: [],
            low_confidence_spans: [],
            notes: ["Local model response was not valid JSON schema. Returned raw transcript."]
        )
    }

    private func generate(baseURL: URL, model: String, prompt: String) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LocalLogicError.requestFailed(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocalLogicError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalLogicError.runtimeUnavailable("Status \(http.statusCode): \(serverMessage)")
        }

        guard let decoded = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data) else {
            throw LocalLogicError.invalidResponse
        }

        if let error = decoded.error, !error.isEmpty {
            throw LocalLogicError.runtimeUnavailable(error)
        }

        let responseText = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !responseText.isEmpty else {
            throw LocalLogicError.emptyResponse
        }

        return responseText
    }

    private func decodeFormattedOutput(from text: String) -> FormattedOutput? {
        if let data = text.data(using: .utf8),
           let output = try? JSONDecoder().decode(FormattedOutput.self, from: data) {
            return output
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            let jsonSlice = String(text[start...end])
            if let data = jsonSlice.data(using: .utf8),
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

    private func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty else {
            return nil
        }
        return url
    }

    private func ollamaModelName(for modelID: String) -> String {
        switch modelID {
        case "gpt-oss-20b":
            return "gpt-oss:20b"
        default:
            return modelID
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct ModelItem: Decodable {
        let name: String
    }

    let models: [ModelItem]?
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
    let error: String?
}
