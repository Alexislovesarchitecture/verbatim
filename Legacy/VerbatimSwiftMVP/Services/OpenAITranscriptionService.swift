import Foundation
import AVFoundation

protocol TranscriptionServiceProtocol: TranscriptionEngine {
    func transcribe(audioFileURL: URL, apiKey: String?, options: TranscriptionOptions) async throws -> Transcript
}

enum OpenAITranscriptionError: LocalizedError {
    case missingApiKey
    case missingAudioFile
    case unsupportedAudioType(String)
    case uploadTooLarge
    case requestFailed(Error)
    case invalidResponse
    case emptyTranscription
    case unsupportedModel(String)
    case serverError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Set OPENAI_API_KEY in your environment or in Settings."
        case .missingAudioFile:
            return "Recorded audio file is missing."
        case .unsupportedAudioType(let type):
            return "Unsupported audio type: \(type). Use mp3/mp4/mpeg/mpga/m4a/wav/webm/flac/ogg."
        case .uploadTooLarge:
            return "Uploaded audio file is larger than 25 MB."
        case .requestFailed(let error):
            return "Transcription request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Transcription API returned an invalid response."
        case .emptyTranscription:
            return "No text was returned from transcription."
        case .unsupportedModel(let model):
            return "Model '\(model)' is not available for this app version."
        case .serverError(let status, let message):
            return "OpenAI API error (\(status)): \(message)"
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError
}

struct OpenAIStreamingEventDecoder {
    func decodeTranscriptEvents(
        payload: String,
        eventID: String?,
        fallbackEventIndex: Int,
        modelID: String,
        responseFormat: String
    ) throws -> [TranscriptEvent] {
        guard let data = payload.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown streaming error."
            throw OpenAITranscriptionError.serverError(status: 500, message: message)
        }

        let type = (object["type"] as? String)?.lowercased() ?? ""
        let baseEventID = eventID ?? "stream_\(fallbackEventIndex)"
        var events: [TranscriptEvent] = []

        if let deltaText = extractDeltaText(from: object, eventType: type),
           !deltaText.isEmpty {
            events.append(.delta(TranscriptDelta(id: "\(baseEventID):delta", text: deltaText)))
        }

        let segments = parseSegments(from: object, fallbackEventID: baseEventID)
        events.append(contentsOf: segments.map(TranscriptEvent.segment))

        let completionSignal = type.contains("completed")
            || type.contains("done")
            || type.contains("final")
        let hasFinalText = object["text"] is String || object["transcript"] is String
        if completionSignal || (hasFinalText && !type.contains("delta")) {
            let text = resolveFinalText(from: object, fallbackSegments: segments)
            if !text.isEmpty || !segments.isEmpty {
                events.append(
                    .done(
                        Transcript(
                            rawText: text,
                            segments: segments,
                            tokenLogprobs: nil,
                            lowConfidenceSpans: [],
                            modelID: modelID,
                            responseFormat: responseFormat
                        )
                    )
                )
            }
        }

        return events
    }

    func syntheticSegmentID(from object: [String: Any], fallbackEventID: String, ordinal: Int) -> String {
        if let id = object["id"] as? String, !id.isEmpty {
            return id
        }
        if let id = object["segment_id"] as? String, !id.isEmpty {
            return id
        }
        if let index = object["index"] as? Int {
            return "segment_\(index)"
        }

        let text = (object["text"] as? String) ?? (object["transcript"] as? String) ?? ""
        let speaker = object["speaker"] as? String ?? ""
        let start = decodeDouble(object["start"]) ?? decodeDouble(object["start_time"])
        let end = decodeDouble(object["end"]) ?? decodeDouble(object["end_time"])
        let startText = start.map { String($0) } ?? "nil"
        let endText = end.map { String($0) } ?? "nil"
        let digest = stableDigest("\(fallbackEventID)|\(ordinal)|\(startText)|\(endText)|\(speaker)|\(text)")
        return "segment_\(digest)"
    }

    private func parseSegments(from object: [String: Any], fallbackEventID: String) -> [TranscriptSegment] {
        var orderedIDs: [String] = []
        var segmentsByID: [String: TranscriptSegment] = [:]
        let hasNestedSegments = object["segment"] != nil || object["segments"] != nil || object["output"] != nil

        func collect(_ value: Any?, ordinal: Int) {
            guard let segment = parseSegment(from: value, fallbackEventID: fallbackEventID, ordinal: ordinal) else {
                return
            }
            if segmentsByID[segment.id] == nil {
                orderedIDs.append(segment.id)
            }
            segmentsByID[segment.id] = segment
        }

        collect(object["segment"], ordinal: 0)

        if let segmentArray = object["segments"] as? [Any] {
            for (index, value) in segmentArray.enumerated() {
                collect(value, ordinal: index + 1)
            }
        }

        if let outputArray = object["output"] as? [Any] {
            for (index, value) in outputArray.enumerated() {
                collect(value, ordinal: 100 + index)
            }
        }

        if !hasNestedSegments {
            collect(object, ordinal: 999)
        }
        return orderedIDs.compactMap { segmentsByID[$0] }
    }

    private func extractDeltaText(from object: [String: Any], eventType: String) -> String? {
        if let delta = object["delta"] as? String {
            return delta
        }
        if let deltaObject = object["delta"] as? [String: Any] {
            if let text = deltaObject["text"] as? String {
                return text
            }
            if let text = deltaObject["value"] as? String {
                return text
            }
        }
        if let textDelta = object["text_delta"] as? String {
            return textDelta
        }
        if eventType.contains("delta"), let text = object["text"] as? String {
            return text
        }
        return nil
    }

    private func parseSegment(from value: Any?, fallbackEventID: String, ordinal: Int) -> TranscriptSegment? {
        guard let object = value as? [String: Any] else {
            return nil
        }

        let text = (object["text"] as? String)
            ?? (object["transcript"] as? String)
            ?? ""
        let speaker = object["speaker"] as? String
        let start = decodeDouble(object["start"]) ?? decodeDouble(object["start_time"])
        let end = decodeDouble(object["end"]) ?? decodeDouble(object["end_time"])

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && start == nil && end == nil {
            return nil
        }

        return TranscriptSegment(
            id: syntheticSegmentID(from: object, fallbackEventID: fallbackEventID, ordinal: ordinal),
            start: start,
            end: end,
            speaker: speaker,
            text: text
        )
    }

    private func decodeDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }

    private func resolveFinalText(from object: [String: Any], fallbackSegments: [TranscriptSegment]) -> String {
        if let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let text = object["transcript"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        if let finalObject = object["final"] as? [String: Any],
           let text = finalObject["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return fallbackSegments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

final class OpenAITranscriptionService: TranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = "openai-batch-sse"
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: true,
        supportsLiveAudioFrames: false,
        supportsDiarization: true,
        supportsLogprobs: true,
        supportsTimestamps: true,
        supportsPrompt: true
    )

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let session: URLSession
    private let sseParser: ServerSentEventParser
    private let streamingEventDecoder: OpenAIStreamingEventDecoder

    init(
        session: URLSession = .shared,
        sseParser: ServerSentEventParser = ServerSentEventParser(),
        streamingEventDecoder: OpenAIStreamingEventDecoder = OpenAIStreamingEventDecoder()
    ) {
        self.session = session
        self.sseParser = sseParser
        self.streamingEventDecoder = streamingEventDecoder
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        try await transcribe(audioFileURL: audioURL, apiKey: options.apiKey, options: options)
    }

    func transcribeEvents(source: TranscriptionSource, options: TranscriptionOptions) -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let audioURL = source.audioURL else {
                        throw TranscriptionEngineError.missingAudioSource
                    }

                    if options.stream {
                        try await emitStreamingEvents(
                            audioFileURL: audioURL,
                            options: options,
                            continuation: continuation
                        )
                    } else {
                        let transcript = try await transcribeBatch(audioURL: audioURL, options: options)
                        continuation.yield(.done(transcript))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func transcribe(audioFileURL: URL, apiKey: String?, options: TranscriptionOptions) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw OpenAITranscriptionError.missingAudioFile
        }

        guard let model = ModelRegistry.entry(for: options.modelID), model.isEnabled else {
            throw OpenAITranscriptionError.unsupportedModel(options.modelID)
        }

        guard isSupportedAudioFile(audioFileURL) else {
            throw OpenAITranscriptionError.unsupportedAudioType(audioFileURL.pathExtension.lowercased())
        }

        let finalApiKey = resolveApiKey(from: apiKey)
        guard let finalApiKey, !finalApiKey.isEmpty else {
            throw OpenAITranscriptionError.missingApiKey
        }

        let audioData = try Data(contentsOf: audioFileURL)
        guard audioData.count <= ModelRegistry.minimumRemoteUploadBytes else {
            throw OpenAITranscriptionError.uploadTooLarge
        }

        let duration = (try? audioDuration(audioFileURL: audioFileURL)) ?? 0
        let shouldChunk = model.requiresChunkingStrategyForLongAudio && duration > 30

        let capabilityContext = ModelCapabilityConstraintContext(
            from: options,
            model: model,
            shouldUseChunkingForLongAudio: shouldChunk
        )

        let candidateFormats: [String]
        if capabilityContext.responseFormat == "text" && model.id.hasPrefix("gpt-4o") {
            candidateFormats = ["text", "json"]
        } else {
            candidateFormats = [capabilityContext.responseFormat]
        }

        var lastError: Error?
        for format in candidateFormats {
            do {
                let request = try buildRequest(
                    audioFileURL: audioFileURL,
                    audioData: audioData,
                    modelID: model.id,
                    apiKey: finalApiKey,
                    model: model,
                    responseFormat: format,
                    languageHint: options.languageHint,
                    includeLogprobs: capabilityContext.includeLogprobs,
                    prompt: capabilityContext.prompt,
                    stream: capabilityContext.stream,
                    timestampGranularities: capabilityContext.timestampGranularities,
                    chunkingStrategy: capabilityContext.chunkingStrategy,
                    diarizationEnabled: capabilityContext.diarizationEnabled,
                    knownSpeakerNames: options.knownSpeakerNames,
                    knownSpeakerReferences: options.knownSpeakerReferences
                )

                let (responseData, response) = try await performRequestWithRetry(request)
                return try parseResponse(responseData: responseData, response: response, modelID: model.id, responseFormat: format)
            } catch {
                lastError = error
                if format == "text", shouldTryJSONFallback(error) {
                    continue
                }
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw OpenAITranscriptionError.invalidResponse
    }

    private func emitStreamingEvents(
        audioFileURL: URL,
        options: TranscriptionOptions,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    ) async throws {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw OpenAITranscriptionError.missingAudioFile
        }

        guard let model = ModelRegistry.entry(for: options.modelID), model.isEnabled else {
            throw OpenAITranscriptionError.unsupportedModel(options.modelID)
        }

        let finalAPIKey = resolveApiKey(from: options.apiKey)
        guard let finalAPIKey, !finalAPIKey.isEmpty else {
            throw OpenAITranscriptionError.missingApiKey
        }

        guard isSupportedAudioFile(audioFileURL) else {
            throw OpenAITranscriptionError.unsupportedAudioType(audioFileURL.pathExtension.lowercased())
        }

        let audioData = try Data(contentsOf: audioFileURL)
        guard audioData.count <= ModelRegistry.minimumRemoteUploadBytes else {
            throw OpenAITranscriptionError.uploadTooLarge
        }

        let duration = (try? audioDuration(audioFileURL: audioFileURL)) ?? 0
        let shouldChunk = model.requiresChunkingStrategyForLongAudio && duration > 30
        let context = ModelCapabilityConstraintContext(
            from: options,
            model: model,
            shouldUseChunkingForLongAudio: shouldChunk
        )

        let request = try buildRequest(
            audioFileURL: audioFileURL,
            audioData: audioData,
            modelID: model.id,
            apiKey: finalAPIKey,
            model: model,
            responseFormat: context.responseFormat,
            languageHint: options.languageHint,
            includeLogprobs: context.includeLogprobs,
            prompt: context.prompt,
            stream: true,
            timestampGranularities: context.timestampGranularities,
            chunkingStrategy: context.chunkingStrategy,
            diarizationEnabled: context.diarizationEnabled,
            knownSpeakerNames: options.knownSpeakerNames,
            knownSpeakerReferences: options.knownSpeakerReferences
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
            }
            let message = parseServerErrorMessage(from: body)
            throw OpenAITranscriptionError.serverError(status: http.statusCode, message: message)
        }

        var mergedDraft = ""
        var mergedSegmentOrder: [String] = []
        var mergedSegments: [String: TranscriptSegment] = [:]
        var emittedDone = false
        var eventIndex = 0

        for try await event in sseParser.parse(bytes: bytes) {
            let payload = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { continue }
            if payload == "[DONE]" { continue }
            eventIndex += 1

            let transcriptEvents = try streamingEventDecoder.decodeTranscriptEvents(
                payload: payload,
                eventID: event.id,
                fallbackEventIndex: eventIndex,
                modelID: model.id,
                responseFormat: context.responseFormat
            )

            for transcriptEvent in transcriptEvents {
                switch transcriptEvent {
                case .delta(let delta):
                    mergedDraft.append(delta.text)
                case .segment(let segment):
                    if mergedSegments[segment.id] == nil {
                        mergedSegmentOrder.append(segment.id)
                    }
                    mergedSegments[segment.id] = segment
                case .done:
                    emittedDone = true
                }
                continuation.yield(transcriptEvent)
            }
        }

        if !emittedDone {
            let orderedSegments = mergedSegmentOrder.compactMap { mergedSegments[$0] }
            let finalText = orderedSegments.isEmpty
                ? mergedDraft
                : orderedSegments
                    .map(\.text)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

            continuation.yield(
                .done(
                    Transcript(
                        rawText: finalText,
                        segments: orderedSegments,
                        tokenLogprobs: nil,
                        lowConfidenceSpans: [],
                        modelID: model.id,
                        responseFormat: context.responseFormat
                    )
                )
            )
        }
    }

    private func resolveApiKey(from apiKey: String?) -> String? {
        let providedApiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envApiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return providedApiKey?.isEmpty == false ? providedApiKey : envApiKey
    }

    private func isSupportedAudioFile(_ audioFileURL: URL) -> Bool {
        let extensionValue = audioFileURL.pathExtension.lowercased()
        return ModelRegistry.supportedAudioExtensions.contains(extensionValue)
    }

    private func parseResponse(responseData: Data, response: URLResponse, modelID: String, responseFormat: String) throws -> Transcript {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAITranscriptionError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = parseServerErrorMessage(from: responseData)
            throw OpenAITranscriptionError.serverError(status: http.statusCode, message: message)
        }

        if responseFormat == "text" {
            let fallback = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !fallback.isEmpty else {
                throw OpenAITranscriptionError.emptyTranscription
            }

            return Transcript(
                rawText: fallback,
                segments: [TranscriptSegment(start: nil, end: nil, speaker: nil, text: fallback)],
                tokenLogprobs: nil,
                lowConfidenceSpans: [],
                modelID: modelID,
                responseFormat: responseFormat
            )
        }

        let decoded = try JSONDecoder().decode(RemoteTranscriptResponse.self, from: responseData)
        let responseText = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = decoded.segments
        let tokenLogprobs = decoded.logprobs
        let lowConfidenceSpans = deriveLowConfidenceSpans(from: tokenLogprobs)
        let text = resolveTranscriptText(responseText: responseText, segments: segments)

        if text.isEmpty && segments.isEmpty {
            throw OpenAITranscriptionError.emptyTranscription
        }

        return Transcript(
            rawText: text,
            segments: segments,
            tokenLogprobs: tokenLogprobs,
            lowConfidenceSpans: lowConfidenceSpans,
            modelID: modelID,
            responseFormat: responseFormat
        )
    }

    private func deriveLowConfidenceSpans(from tokenLogprobs: [TokenLogprob]?) -> [LowConfidenceSpan] {
        guard let tokenLogprobs else { return [] }

        let threshold = ModelRegistry.diarizationLogprobThreshold
        let lowConfident = tokenLogprobs.filter { $0.logprob < threshold }
        guard !lowConfident.isEmpty else { return [] }

        var spans: [LowConfidenceSpan] = []
        var activeStart: TimeInterval?
        var activeEnd: TimeInterval?
        var activeText: [String] = []
        var activeSum: Double = 0
        var activeCount = 0

        for token in lowConfident {
            let currentStart = token.start
            let currentEnd = token.end

            if let end = activeEnd,
               let start = currentStart,
               start - end <= 0.25,
               !activeText.isEmpty {
                activeEnd = currentEnd
                activeText.append(token.token)
                activeSum += token.logprob
                activeCount += 1
            } else if !activeText.isEmpty {
                spans.append(
                    LowConfidenceSpan(
                        start: activeStart,
                        end: activeEnd,
                        text: activeText.joined(separator: " "),
                        averageLogprob: activeCount > 0 ? activeSum / Double(activeCount) : 0
                    )
                )
                activeStart = currentStart
                activeEnd = currentEnd
                activeText = [token.token]
                activeSum = token.logprob
                activeCount = 1
            } else {
                activeStart = currentStart
                activeEnd = currentEnd
                activeText = [token.token]
                activeSum = token.logprob
                activeCount = 1
            }
        }

        if !activeText.isEmpty {
            spans.append(
                LowConfidenceSpan(
                    start: activeStart,
                    end: activeEnd,
                    text: activeText.joined(separator: " "),
                    averageLogprob: activeCount > 0 ? activeSum / Double(activeCount) : 0
                )
            )
        }

        return spans
    }

    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 1...2 {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                guard attempt < 2, shouldRetry(for: error) else {
                    break
                }
            }
        }

        throw OpenAITranscriptionError.requestFailed(lastError ?? URLError(.unknown))
    }

    private func shouldRetry(for error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func shouldTryJSONFallback(_ error: Error) -> Bool {
        guard let transcriptionError = error as? OpenAITranscriptionError,
              case .serverError(let status, let message) = transcriptionError else {
            return false
        }
        let isResponseFormatError = message.lowercased().contains("response_format") || message.lowercased().contains("unsupported")
        return (400...499).contains(status) && isResponseFormatError
    }

    private func parseServerErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
           let message = decoded.error.message,
           !message.isEmpty {
            return message
        }

        let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bodyText.isEmpty ? "No response body" : bodyText
    }

    private func buildRequest(
        audioFileURL: URL,
        audioData: Data,
        modelID: String,
        apiKey: String,
        model: ModelRegistryEntry,
        responseFormat: String,
        languageHint: String?,
        includeLogprobs: Bool,
        prompt: String?,
        stream: Bool,
        timestampGranularities: [String],
        chunkingStrategy: String?,
        diarizationEnabled: Bool,
        knownSpeakerNames: [String],
        knownSpeakerReferences: [String]
    ) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        appendFormDataHeader(name: "file", filename: audioFileURL.lastPathComponent, mimeType: mimeType(for: audioFileURL), boundary: boundary, into: &body)
        body.append(audioData)
        append(&body, "\r\n")

        appendFormField(name: "model", value: modelID, boundary: boundary, into: &body)
        appendFormField(name: "response_format", value: responseFormat, boundary: boundary, into: &body)

        if let languageHint, !languageHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendFormField(name: "language", value: languageHint, boundary: boundary, into: &body)
        }

        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendFormField(name: "prompt", value: prompt, boundary: boundary, into: &body)
        }

        if includeLogprobs && model.supportsLogprobs {
            appendFormField(name: "include[]", value: "logprobs", boundary: boundary, into: &body)
        }

        if stream && model.supportsStreaming {
            appendFormField(name: "stream", value: "true", boundary: boundary, into: &body)
        }

        if model.supportsTimestamps && responseFormat == "verbose_json" {
            for granularity in timestampGranularities {
                appendFormField(name: "timestamp_granularities[]", value: granularity, boundary: boundary, into: &body)
            }
        }

        if model.supportsDiarization,
           model.requiresChunkingStrategyForLongAudio,
           let strategy = chunkingStrategy {
            appendFormField(name: "chunking_strategy", value: strategy, boundary: boundary, into: &body)
        }

        if diarizationEnabled && model.supportsDiarization {
            for name in knownSpeakerNames where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendFormField(name: "known_speaker_names[]", value: name, boundary: boundary, into: &body)
            }
            for reference in knownSpeakerReferences where !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendFormField(name: "known_speaker_references[]", value: reference, boundary: boundary, into: &body)
            }
        }

        append(&body, "--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }

    private func audioDuration(audioFileURL: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: audioFileURL)
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private func appendFormDataHeader(name: String, filename: String, mimeType: String, boundary: String, into body: inout Data) {
        append(&body, "--\(boundary)\r\n")
        append(&body, "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append(&body, "Content-Type: \(mimeType)\r\n\r\n")
    }

    private func appendFormField(name: String, value: String, boundary: String, into body: inout Data) {
        append(&body, "--\(boundary)\r\n")
        append(&body, "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(&body, "\(value)\r\n")
    }

    private func resolveTranscriptText(responseText: String, segments: [TranscriptSegment]) -> String {
        let hasSpeakerData = segments.contains { segment in
            !(segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        if hasSpeakerData {
            let speakerAware = segments.map { segment in
                let speaker = segment.speaker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil as String? }
                if speaker.isEmpty {
                    return text
                }
                return "[\(speaker)] \(text)"
            }.compactMap { $0 }

            if !speakerAware.isEmpty {
                return speakerAware.joined(separator: "\n")
            }
        }

        if !responseText.isEmpty {
            return responseText
        }

        return segments.map(\.text).joined(separator: "\n")
    }

    private func append(_ body: inout Data, _ string: String) {
        body.append(Data(string.utf8))
    }

    private func mimeType(for audioFileURL: URL) -> String {
        switch audioFileURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "mp4":
            return "audio/mp4"
        case "mpeg":
            return "audio/mpeg"
        case "mpga":
            return "audio/mpga"
        case "m4a":
            return "audio/m4a"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "application/octet-stream"
        }
    }
}

private struct RemoteTranscriptResponse: Decodable {
    let text: String
    let segments: [TranscriptSegment]
    let logprobs: [TokenLogprob]

    private enum CodingKeys: String, CodingKey {
        case text
        case segments
        case output
        case diarizedSegments = "diarized_segments"
        case logprobs
        case words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""

        let rawSegments = (try? container.decodeIfPresent([SegmentDTO].self, forKey: .segments))
            ?? (try? container.decodeIfPresent([SegmentDTO].self, forKey: .output))
            ?? (try? container.decodeIfPresent([SegmentDTO].self, forKey: .diarizedSegments))
            ?? []

        segments = rawSegments.map { $0.transcriptSegment }

        logprobs = (try? container.decodeIfPresent([TokenLogprobDTO].self, forKey: .logprobs))
            .map { $0.map(\.model) } ??
            (try? container.decodeIfPresent([TokenLogprobDTO].self, forKey: .words))
            .map { $0.map(\.model) } ?? []
    }
}

private struct SegmentDTO: Decodable {
    let id: String?
    let start: TimeInterval?
    let end: TimeInterval?
    let text: String?
    let speaker: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case segmentID = "segment_id"
        case index
        case start
        case end
        case startTime = "start_time"
        case endTime = "end_time"
        case text
        case transcript
        case speaker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let explicitID = try container.decodeIfPresent(String.self, forKey: .id) {
            id = explicitID
        } else if let segmentID = try container.decodeIfPresent(String.self, forKey: .segmentID) {
            id = segmentID
        } else if let index = try container.decodeIfPresent(Int.self, forKey: .index) {
            id = "segment_\(index)"
        } else {
            id = nil
        }

        start = (try? container.decodeIfPresent(TimeInterval.self, forKey: .start))
            ?? (try? container.decodeIfPresent(TimeInterval.self, forKey: .startTime))
        end = (try? container.decodeIfPresent(TimeInterval.self, forKey: .end))
            ?? (try? container.decodeIfPresent(TimeInterval.self, forKey: .endTime))
        text = (try? container.decodeIfPresent(String.self, forKey: .text))
            ?? (try? container.decodeIfPresent(String.self, forKey: .transcript))
        speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
    }

    var transcriptSegment: TranscriptSegment {
        TranscriptSegment(id: id ?? UUID().uuidString, start: start, end: end, speaker: speaker, text: text ?? "")
    }
}

private struct TokenLogprobDTO: Decodable {
    let token: String
    let logprob: Double
    let start: TimeInterval?
    let end: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case token
        case text
        case logprob
        case start
        case end
        case startTime = "start_time"
        case endTime = "end_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? container.decode(String.self, forKey: .token))
            ?? (try? container.decode(String.self, forKey: .text))
            ?? ""
        logprob = (try? container.decode(Double.self, forKey: .logprob)) ?? -100
        start = (try? container.decode(Double.self, forKey: .start))
            ?? (try? container.decode(Double.self, forKey: .startTime))
        end = (try? container.decode(Double.self, forKey: .end))
            ?? (try? container.decode(Double.self, forKey: .endTime))
    }

    var model: TokenLogprob {
        TokenLogprob(token: token, logprob: logprob, start: start, end: end)
    }
}
