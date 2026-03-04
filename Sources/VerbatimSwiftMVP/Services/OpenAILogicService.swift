import Foundation

@available(macOS 26.0, *)
@available(iOS 26.0, *)
protocol LogicServiceProtocol {
    func format(transcript: Transcript, apiKey: String?, modelID: String, settings: LogicSettings) async throws -> FormattedOutput
}

enum OpenAILogicError: LocalizedError {
    case missingApiKey
    case missingTranscript
    case requestFailed(Error)
    case invalidResponse
    case emptyResponse
    case parseFailed(String)
    case serverError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Set OPENAI_API_KEY in your environment or in Settings."
        case .missingTranscript:
            return "No transcript to format."
        case .requestFailed(let error):
            return "Logic request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Logic service returned an invalid response."
        case .emptyResponse:
            return "Logic service returned an empty response."
        case .parseFailed(let message):
            return "Logic JSON parse failed: \(message)"
        case .serverError(let status, let message):
            return "OpenAI API error (\(status)): \(message)"
        }
    }
}

private struct LogicRequestErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }
    let error: APIError
}

private struct ResponsesOutput: Decodable {
    struct OutputContent: Decodable {
        let type: String?
        let text: String?
    }

    struct OutputItem: Decodable {
        let content: [OutputContent]?
    }

    let output: [OutputItem]?
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class OpenAILogicService: LogicServiceProtocol {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func format(transcript: Transcript, apiKey: String?, modelID: String, settings: LogicSettings) async throws -> FormattedOutput {
        guard !transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILogicError.missingTranscript
        }

        guard let model = ModelRegistry.entry(for: modelID), model.isEnabled else {
            throw OpenAILogicError.parseFailed("Model '\(modelID)' is not enabled")
        }

        guard model.supportsStructuredOutputs else {
            throw OpenAILogicError.parseFailed("Model '\(modelID)' does not support structured outputs")
        }

        guard let finalApiKey = resolveApiKey(from: apiKey), !finalApiKey.isEmpty else {
            throw OpenAILogicError.missingApiKey
        }

        let initialEffort = reasoningEffort(for: model, settings: settings)
        do {
            return try await sendFormatRequest(
                transcript: transcript,
                modelID: modelID,
                settings: settings,
                reasoningEffort: initialEffort,
                apiKey: finalApiKey
            )
        } catch let OpenAILogicError.serverError(status, message) {
            if status == 400 && isReasoningEffortError(message) {
                let fallbackEffort = model.id.hasPrefix("gpt-5") ? "minimal" : nil
                if fallbackEffort != initialEffort {
                    return try await sendFormatRequest(
                        transcript: transcript,
                        modelID: modelID,
                        settings: settings,
                        reasoningEffort: fallbackEffort,
                        apiKey: finalApiKey
                    )
                }
            }
            throw OpenAILogicError.serverError(status: status, message: message)
        }
    }

    private func resolveApiKey(from apiKey: String?) -> String? {
        let providedApiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return providedApiKey?.isEmpty == false ? providedApiKey : envApiKey
    }

    private func buildRequest(
        transcript: Transcript,
        modelID: String,
        settings: LogicSettings,
        reasoningEffort: String?,
        apiKey: String
    ) throws -> URLRequest {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "clean_text": ["type": "string"],
                "format": ["type": "string", "enum": ["paragraph", "bullets", "mixed"]],
                "bullets": ["type": "array", "items": ["type": "string"]],
                "self_corrections": ["type": "array", "items": ["type": "string"]],
                "low_confidence_spans": ["type": "array", "items": ["type": "string"]],
                "notes": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["clean_text", "format", "bullets", "self_corrections", "low_confidence_spans", "notes"],
            "additionalProperties": false
        ]

        var requestBody: [String: Any] = [
            "model": modelID,
            "input": [
                [
                    "role": "user",
                    "content": logicPrompt(from: transcript, settings: settings)
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "formatted_transcript",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]
        if let reasoningEffort {
            requestBody["reasoning"] = ["effort": reasoningEffort]
        }

        let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData
        return request
    }

    private func sendFormatRequest(
        transcript: Transcript,
        modelID: String,
        settings: LogicSettings,
        reasoningEffort: String?,
        apiKey: String
    ) async throws -> FormattedOutput {
        let request = try buildRequest(
            transcript: transcript,
            modelID: modelID,
            settings: settings,
            reasoningEffort: reasoningEffort,
            apiKey: apiKey
        )

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAILogicError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let message = parseServerErrorMessage(from: responseData)
            throw OpenAILogicError.serverError(status: http.statusCode, message: message)
        }

        guard let rawJson = extractTextPayload(from: responseData),
              !rawJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILogicError.emptyResponse
        }

        guard let outputData = rawJson.data(using: .utf8) else {
            throw OpenAILogicError.parseFailed("Unable to decode structured response bytes")
        }

        do {
            return try JSONDecoder().decode(FormattedOutput.self, from: outputData)
        } catch {
            throw OpenAILogicError.parseFailed(error.localizedDescription)
        }
    }

    private func reasoningEffort(for model: ModelRegistryEntry, settings: LogicSettings) -> String? {
        guard model.id.hasPrefix("gpt-5") else {
            return nil
        }

        switch settings.reasoningEffort {
        case .off:
            return nil
        case .minimal:
            return "minimal"
        case .low:
            return "low"
        case .medium:
            return "medium"
        case .high:
            return "high"
        case .modelDefault:
            let raw = model.reasoningEffortDefault?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch raw {
            case .some("minimal"), .some("low"), .some("medium"), .some("high"):
                return raw
            default:
                return "minimal"
            }
        }
    }

    private func isReasoningEffortError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("reasoning") && normalized.contains("supported values")
    }

    private func logicPrompt(from transcript: Transcript, settings: LogicSettings) -> String {
        let fillerInstruction = settings.removeFillerWords
            ? "remove obvious filler words such as 'um', 'uh', 'like' when not meaning-bearing"
            : "preserve filler words"

        let correctionInstruction: String
        switch settings.selfCorrectionMode {
        case .keepAll:
            correctionInstruction = "preserve all self-corrections and keep both versions"
        case .keepFinal:
            correctionInstruction = "keep only final transcript text; if a phrase was corrected, prefer the final result"
        case .annotate:
            correctionInstruction = "when self-corrections occur, add both forms to self_corrections"
        }

        let listModeInstruction = settings.autoDetectLists
            ? "if content is clearly enumerative or list-like, set format to bullets"
            : "prefer paragraph output unless explicitly list-like"

        let overrideInstruction: String
        switch settings.outputFormat {
        case .auto:
            overrideInstruction = "output format follows content"
        case .paragraph:
            overrideInstruction = "prefer paragraph format"
        case .bullets:
            overrideInstruction = "prefer bullet format"
        }

        let confidenceInstruction = settings.flagLowConfidenceWords
            ? "include low-confidence notes and keep uncertain text unchanged unless clearly wrong"
            : "do not call out low-confidence tokens"

        let confidencePayload = transcript.lowConfidenceSpans.map { span in
            "\(String(format: "%.2f", span.averageLogprob))@\(span.start ?? 0)-\(span.end ?? 0): \(span.text)"
        }

        let transcriptBody = renderTranscriptLines(transcript: transcript)
        let speakerAwareNote = transcript.hasSpeakerData
            ? "Speaker labels are present in the transcript and must be preserved when clear."
            : "No speaker labels were detected in the transcript."

        return """
        You are a transcript formatter. Preserve meaning and do not invent content.
        Instructions:
        - Clean up the transcript using: \(fillerInstruction).
        - Self-corrections: \(correctionInstruction).
        - List behavior: \(listModeInstruction).
        - Format override: \(overrideInstruction).
        - Confidence handling: \(confidenceInstruction).
        - \(speakerAwareNote)
        - Always return valid JSON and include all schema fields even when empty.
        - keep raw words, punctuation, and spelling unless the user requested otherwise above.

        Raw transcript:
        \(transcriptBody)

        Low confidence spans (model-provided):
        \(confidencePayload.joined(separator: "\n"))

        Return strictly as JSON matching the schema.
        """
    }

    private func parseServerErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(LogicRequestErrorResponse.self, from: data),
           let message = decoded.error.message,
           !message.isEmpty {
            return message
        }

        let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bodyText.isEmpty ? "No response body" : bodyText
    }

    private func extractTextPayload(from data: Data) -> String? {
        guard let wrapper = try? JSONDecoder().decode(ResponsesOutput.self, from: data) else {
            return nil
        }

        guard let output = wrapper.output else {
            if let plain = String(data: data, encoding: .utf8) {
                return plain
            }
            return nil
        }

        for item in output {
            guard let contents = item.content else { continue }
            for content in contents where (content.type ?? "output_text") == "output_text" {
                if let text = content.text {
                    return text
                }
            }
        }

        return nil
    }

    private func renderTranscriptLines(transcript: Transcript) -> String {
        if transcript.segments.isEmpty {
            return transcript.rawText
        }

        return transcript.segments.map { segment in
            let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if speaker.isEmpty {
                return segmentText
            }
            return "[\(speaker)] \(segmentText)"
        }.joined(separator: "\n")
    }

}

private extension Transcript {
    var hasSpeakerData: Bool {
        segments.contains { segment in
            !(segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}
