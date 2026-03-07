import Foundation

enum TranscriptionCoordinatorError: LocalizedError {
    case sessionAlreadyRecording
    case sessionNotRecording
    case missingSessionRequest
    case missingRecordingArtifact
    case unsupportedLocalModel(LocalTranscriptionModel)

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyRecording:
            return "A transcription session is already recording."
        case .sessionNotRecording:
            return "No active recording session to stop."
        case .missingSessionRequest:
            return "Missing transcription request context for this session."
        case .missingRecordingArtifact:
            return "Recording finished without a usable audio artifact."
        case .unsupportedLocalModel(let model):
            return "\(model.title) is not implemented yet for local transcription."
        }
    }
}

@MainActor
final class TranscriptionCoordinator {
    private let recorder: AudioRecorderServiceProtocol
    private let remoteEngine: TranscriptionServiceProtocol
    private let localEngine: LocalTranscriptionServiceProtocol
    private let modelCatalogService: ModelCatalogServiceProtocol

    private var activeSession: TranscriptionSession?
    private var pendingRequest: TranscriptionSessionRequest?
    private var merger: TranscriptMerger?

    init(
        recorder: AudioRecorderServiceProtocol? = nil,
        remoteEngine: TranscriptionServiceProtocol = OpenAITranscriptionService(),
        localEngine: LocalTranscriptionServiceProtocol = AppleLocalTranscriptionService(),
        modelCatalogService: ModelCatalogServiceProtocol? = nil
    ) {
        self.recorder = recorder ?? AudioRecorderService()
        self.remoteEngine = remoteEngine
        self.localEngine = localEngine
        self.modelCatalogService = modelCatalogService ?? OpenAIModelCatalogService()
    }

    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String> {
        try await modelCatalogService.fetchRemoteModelIDs(apiKey: apiKey)
    }

    func engineCapabilities(for request: TranscriptionSessionRequest) throws -> EngineCapabilities {
        try selectedEngine(for: request).capabilities
    }

    @discardableResult
    func startSession(request: TranscriptionSessionRequest) async throws -> TranscriptionSession {
        if let activeSession, activeSession.stage == .recording {
            throw TranscriptionCoordinatorError.sessionAlreadyRecording
        }

        let selectedEngine = try selectedEngine(for: request)
        _ = try await recorder.startRecording()

        let session = TranscriptionSession(
            engineID: selectedEngine.engineID,
            stage: .recording
        )
        activeSession = session
        pendingRequest = request
        merger = TranscriptMerger(
            fallbackModelID: request.options.modelID,
            fallbackResponseFormat: request.options.responseFormat
        )

        return session
    }

    func stopSessionAndTranscribe() -> AsyncThrowingStream<TranscriptionSessionUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.runStopAndTranscribe(continuation: continuation)
                    continuation.finish()
                } catch {
                    self.failActiveSession(with: error, continuation: continuation)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func runStopAndTranscribe(
        continuation: AsyncThrowingStream<TranscriptionSessionUpdate, Error>.Continuation
    ) async throws {
        guard var session = activeSession, session.stage == .recording else {
            throw TranscriptionCoordinatorError.sessionNotRecording
        }
        guard let request = pendingRequest else {
            throw TranscriptionCoordinatorError.missingSessionRequest
        }
        guard let merger else {
            throw TranscriptionCoordinatorError.missingSessionRequest
        }

        session.stage = .transcribing
        activeSession = session
        continuation.yield(.session(session))

        guard let artifact = try await recorder.stopRecording() else {
            throw TranscriptionCoordinatorError.missingRecordingArtifact
        }
        defer {
            recorder.discardRecordingArtifact(artifact)
        }

        let engine = try selectedEngine(for: request)
        let options = constrainedOptions(request.options, for: engine)
        let source = TranscriptionSource.recordingArtifact(
            audioURL: artifact.audioFileURL,
            frames: artifact.frameStream
        )

        for try await event in engine.transcribeEvents(source: source, options: options) {
            let snapshot = await merger.apply(event)
            continuation.yield(.transcript(event: event, snapshot: snapshot))
        }

        session.stage = .completed
        session.endedAt = Date()
        activeSession = session
        pendingRequest = nil
        continuation.yield(.session(session))
    }

    private func failActiveSession(
        with error: Error,
        continuation: AsyncThrowingStream<TranscriptionSessionUpdate, Error>.Continuation
    ) {
        if var session = activeSession {
            session.stage = .failed
            session.endedAt = Date()
            session.errorMessage = error.localizedDescription
            activeSession = session
            pendingRequest = nil
            continuation.yield(.session(session))
        }
    }

    private func selectedEngine(for request: TranscriptionSessionRequest) throws -> any TranscriptionEngine {
        switch request.mode {
        case .remote:
            return remoteEngine
        case .local:
            guard request.localModel == .appleOnDevice else {
                throw TranscriptionCoordinatorError.unsupportedLocalModel(request.localModel)
            }
            return localEngine
        }
    }

    private func constrainedOptions(_ options: TranscriptionOptions, for engine: any TranscriptionEngine) -> TranscriptionOptions {
        var constrained = options
        let capabilities = engine.capabilities

        if !capabilities.supportsLogprobs {
            constrained.includeLogprobs = false
        }
        if !capabilities.supportsPrompt {
            constrained.prompt = nil
        }
        if !capabilities.supportsStreamingEvents {
            constrained.stream = false
        }
        if !capabilities.supportsTimestamps {
            constrained.timestampGranularities = []
        }
        if !capabilities.supportsDiarization {
            constrained.diarizationEnabled = false
            constrained.knownSpeakerNames = []
            constrained.knownSpeakerReferences = []
            constrained.chunkingStrategy = nil
        }

        if let model = ModelRegistry.entry(for: constrained.modelID) {
            let context = ModelCapabilityConstraintContext(
                from: constrained,
                model: model,
                shouldUseChunkingForLongAudio: false
            )
            constrained.responseFormat = context.responseFormat
            constrained.includeLogprobs = context.includeLogprobs
            constrained.prompt = context.prompt
            constrained.stream = context.stream
            constrained.timestampGranularities = context.timestampGranularities
            constrained.diarizationEnabled = context.diarizationEnabled
            constrained.chunkingStrategy = context.chunkingStrategy
        }

        return constrained
    }
}
