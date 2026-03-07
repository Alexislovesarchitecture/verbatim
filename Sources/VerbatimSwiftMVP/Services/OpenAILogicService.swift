import Foundation

protocol LogicServiceProtocol {
    func format(transcript: Transcript, apiKey: String?, modelID: String, settings: LogicSettings) async throws -> FormattedOutput
}

protocol OpenAIRemoteRefineServiceProtocol: Sendable {
    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        apiKey: String?,
        modelID: String
    ) async throws -> LLMResult
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

private struct ResponsesUsage: Decodable {
    struct InputTokenDetails: Decodable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let inputTokenDetails: InputTokenDetails?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokenDetails = "input_tokens_details"
    }
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
    let usage: ResponsesUsage?
}

final class OpenAILogicService: LogicServiceProtocol, OpenAIRemoteRefineServiceProtocol {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func format(transcript: Transcript, apiKey: String?, modelID: String, settings: LogicSettings) async throws -> FormattedOutput {
        guard !transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILogicError.missingTranscript
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

        let context = ContextPack(
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
        )

        let result = try await refine(
            deterministicText: transcript.rawText,
            contextPack: context,
            profile: profile,
            apiKey: apiKey,
            modelID: modelID
        )

        let cleanText = result.text ?? transcript.rawText
        let bullets = inferBullets(from: cleanText)
        return FormattedOutput(
            clean_text: cleanText,
            format: bullets.isEmpty ? "paragraph" : "bullets",
            bullets: bullets,
            self_corrections: [],
            low_confidence_spans: [],
            notes: result.status == .fallback ? ["Returned deterministic fallback output."] : []
        )
    }

    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        apiKey: String?,
        modelID: String
    ) async throws -> LLMResult {
        guard !deterministicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILogicError.missingTranscript
        }

        guard let model = ModelRegistry.entry(for: modelID), model.isEnabled else {
            throw OpenAILogicError.parseFailed("Model '\(modelID)' is not enabled")
        }

        guard let finalApiKey = resolveApiKey(from: apiKey), !finalApiKey.isEmpty else {
            throw OpenAILogicError.missingApiKey
        }

        let startedAt = Date()
        switch profile.outputMode {
        case .text:
            let payload = textPayload(profile: profile, contextPack: contextPack, text: deterministicText)
            let prompt = makePrompt(profile: profile, payload: payload)
            let response = try await sendRequest(
                apiKey: finalApiKey,
                modelID: model.id,
                prompt: prompt,
                textFormat: nil
            )

            let text = response.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)

            guard !text.isEmpty else {
                return fallbackResult(
                    deterministicText: deterministicText,
                    profile: profile,
                    modelID: model.id,
                    latencyMs: latencyMs
                )
            }

            return LLMResult(
                text: text,
                json: nil,
                status: .success,
                validationStatus: .notApplicable,
                tokens: response.usage.totalTokens,
                cachedTokens: response.usage.cachedTokens,
                latencyMs: latencyMs,
                profileID: profile.id,
                profileVersion: profile.version,
                modelID: model.id,
                fromCache: false
            )

        case .jsonSchema:
            if model.supportsStructuredOutputs, let schema = profile.schemaObject {
                do {
                    let strictResponse = try await sendRequest(
                        apiKey: finalApiKey,
                        modelID: model.id,
                        prompt: makePrompt(profile: profile, payload: actionItemsPayload(contextPack: contextPack, text: deterministicText)),
                        textFormat: [
                            "type": "json_schema",
                            "name": "\(profile.id)_schema",
                            "strict": true,
                            "schema": schema,
                        ]
                    )

                    let strictJSON = strictResponse.outputText
                    if validateJSON(strictJSON, profile: profile) {
                        return makeJSONResult(
                            json: strictJSON,
                            status: .success,
                            validationStatus: .valid,
                            usage: strictResponse.usage,
                            latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                            profile: profile,
                            modelID: model.id
                        )
                    }
                } catch let OpenAILogicError.serverError(_, message) {
                    if !isStrictSchemaSupportError(message) {
                        throw OpenAILogicError.serverError(status: 400, message: message)
                    }
                }
            }

            return try await refineViaJSONMode(
                deterministicText: deterministicText,
                contextPack: contextPack,
                profile: profile,
                apiKey: finalApiKey,
                modelID: model.id,
                startedAt: startedAt
            )

        case .jsonObjectFallback:
            return try await refineViaJSONMode(
                deterministicText: deterministicText,
                contextPack: contextPack,
                profile: profile,
                apiKey: finalApiKey,
                modelID: model.id,
                startedAt: startedAt
            )
        }
    }

    private func refineViaJSONMode(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        apiKey: String,
        modelID: String,
        startedAt: Date
    ) async throws -> LLMResult {
        let basePrompt = makePrompt(profile: profile, payload: actionItemsPayload(contextPack: contextPack, text: deterministicText))
        let firstResponse = try await sendRequest(
            apiKey: apiKey,
            modelID: modelID,
            prompt: basePrompt + "\nOutput JSON only.",
            textFormat: ["type": "json_object"]
        )

        let firstJSON = firstResponse.outputText
        if validateJSON(firstJSON, profile: profile) {
            return makeJSONResult(
                json: firstJSON,
                status: .success,
                validationStatus: .valid,
                usage: firstResponse.usage,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                profile: profile,
                modelID: modelID
            )
        }

        let repairPrompt = """
        Return valid JSON only.
        Use the same schema requirements as before.
        Invalid JSON:
        \(firstJSON)
        """

        let repairResponse = try await sendRequest(
            apiKey: apiKey,
            modelID: modelID,
            prompt: repairPrompt,
            textFormat: ["type": "json_object"]
        )

        let repairedJSON = repairResponse.outputText
        if validateJSON(repairedJSON, profile: profile) {
            return makeJSONResult(
                json: repairedJSON,
                status: .repaired,
                validationStatus: .valid,
                usage: repairResponse.usage,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                profile: profile,
                modelID: modelID
            )
        }

        return LLMResult(
            text: deterministicText,
            json: nil,
            status: .fallback,
            validationStatus: .invalid,
            tokens: repairResponse.usage.totalTokens,
            cachedTokens: repairResponse.usage.cachedTokens,
            latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            fromCache: false
        )
    }

    private func textPayload(profile: PromptProfile, contextPack: ContextPack, text: String) -> [String: Any] {
        var payload: [String: Any] = [
            "context": [
                "active_app": contextPack.activeAppName,
                "bundle_id": contextPack.bundleID,
                "style_category": contextPack.styleCategory.rawValue,
                "window_title": contextPack.windowTitle ?? "",
                "focused_element_role": contextPack.focusedElementRole ?? "",
            ],
            "glossary": contextPack.glossary.map { ["from": $0.from, "to": $0.to] },
            "text": text,
        ]

        if let options = profile.options?.mapValues({ $0.toAnyValue() }), !options.isEmpty {
            payload["options"] = options
        }

        if !contextPack.sessionMemory.isEmpty {
            payload["session_memory"] = contextPack.sessionMemory
        }

        return payload
    }

    private func actionItemsPayload(contextPack: ContextPack, text: String) -> [String: Any] {
        [
            "context": [
                "active_app": contextPack.activeAppName,
                "bundle_id": contextPack.bundleID,
                "style_category": contextPack.styleCategory.rawValue,
                "window_title": contextPack.windowTitle ?? "",
                "focused_element_role": contextPack.focusedElementRole ?? "",
            ],
            "text": text,
        ]
    }

    private func makePrompt(profile: PromptProfile, payload: [String: Any]) -> String {
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        return "\(profile.instructionPrefix)\n\n\(payloadJSON)"
    }

    private func sendRequest(
        apiKey: String,
        modelID: String,
        prompt: String,
        textFormat: [String: Any]?
    ) async throws -> (outputText: String, usage: (totalTokens: Int, cachedTokens: Int)) {
        var body: [String: Any] = [
            "model": modelID,
            "input": [
                [
                    "role": "user",
                    "content": prompt,
                ]
            ],
        ]

        if let textFormat {
            body["text"] = ["format": textFormat]
        }

        let requestData = try JSONSerialization.data(withJSONObject: body, options: [])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw OpenAILogicError.requestFailed(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAILogicError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let message = parseServerErrorMessage(from: responseData)
            throw OpenAILogicError.serverError(status: http.statusCode, message: message)
        }

        guard let decoded = try? JSONDecoder().decode(ResponsesOutput.self, from: responseData) else {
            throw OpenAILogicError.invalidResponse
        }

        guard let outputText = extractText(from: decoded), !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAILogicError.emptyResponse
        }

        let total = decoded.usage?.totalTokens ?? ((decoded.usage?.inputTokens ?? 0) + (decoded.usage?.outputTokens ?? 0))
        let cached = decoded.usage?.inputTokenDetails?.cachedTokens ?? 0
        return (outputText, (total, cached))
    }

    private func extractText(from wrapper: ResponsesOutput) -> String? {
        guard let output = wrapper.output else { return nil }
        for item in output {
            guard let contents = item.content else { continue }
            for content in contents {
                if (content.type ?? "output_text") == "output_text", let text = content.text {
                    return text
                }
            }
        }
        return nil
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

    private func validateJSON(_ jsonText: String, profile: PromptProfile) -> Bool {
        guard let data = jsonText.data(using: .utf8) else {
            return false
        }

        if profile.id == "action_items" {
            return (try? JSONDecoder().decode(ActionItemsPayload.self, from: data)) != nil
        }

        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func makeJSONResult(
        json: String,
        status: LLMResultStatus,
        validationStatus: LLMValidationStatus,
        usage: (totalTokens: Int, cachedTokens: Int),
        latencyMs: Int,
        profile: PromptProfile,
        modelID: String
    ) -> LLMResult {
        LLMResult(
            text: nil,
            json: json,
            status: status,
            validationStatus: validationStatus,
            tokens: usage.totalTokens,
            cachedTokens: usage.cachedTokens,
            latencyMs: latencyMs,
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            fromCache: false
        )
    }

    private func fallbackResult(
        deterministicText: String,
        profile: PromptProfile,
        modelID: String,
        latencyMs: Int
    ) -> LLMResult {
        LLMResult(
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

    private func resolveApiKey(from apiKey: String?) -> String? {
        let providedApiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return providedApiKey?.isEmpty == false ? providedApiKey : envApiKey
    }

    private func isStrictSchemaSupportError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("json_schema") || normalized.contains("unsupported") || normalized.contains("strict")
    }

    private func inferBullets(from text: String) -> [String] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.allSatisfy({ $0.hasPrefix("-") || $0.hasPrefix("*") || $0.hasPrefix("•") }) {
            return lines.map { line in
                line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return []
    }
}
