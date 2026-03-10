import Foundation
import XCTest
@testable import VerbatimSwiftMVP

final class TranscriptionCoordinatorTests: XCTestCase {
    @MainActor
    func testStopSessionStreamsTranscriptEventsAndFinalSession() async throws {
        let artifactURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-coordinator-\(UUID().uuidString).wav")
        try Data().write(to: artifactURL)
        defer { try? FileManager.default.removeItem(at: artifactURL) }

        let artifact = AudioRecordingArtifact(
            audioFileURL: artifactURL,
            frameStream: AsyncStream { continuation in
                continuation.finish()
            }
        )

        let finalTranscript = Transcript(
            rawText: "hello world",
            segments: [TranscriptSegment(id: "seg-1", start: 0.0, end: 1.0, speaker: nil, text: "hello world")],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )

        let recorder = FakeAudioRecorder(artifact: artifact)
        let remoteEngine = FakeRemoteEngine(
            transcript: finalTranscript,
            events: [
                .delta(TranscriptDelta(id: "d1", text: "hello")),
                .segment(TranscriptSegment(id: "seg-1", start: 0.0, end: 1.0, speaker: nil, text: "hello world")),
                .done(finalTranscript),
            ]
        )
        let localEngine = FakeLocalEngine(transcript: finalTranscript)
        let sut = TranscriptionCoordinator(
            recorder: recorder,
            remoteEngine: remoteEngine,
            localEngine: localEngine,
            modelCatalogService: FakeModelCatalog()
        )

        _ = try await sut.startSession(
            request: TranscriptionSessionRequest(
                mode: .remote,
                localModel: .appleOnDevice,
                options: TranscriptionOptions(
                    modelID: "gpt-4o-mini-transcribe",
                    apiKey: "test-key",
                    responseFormat: "json",
                    stream: true
                ),
                interactionSettings: InteractionSettings(),
                recordingSessionContext: nil
            )
        )

        var sessionStages: [TranscriptionSession.Stage] = []
        var transcriptEventCount = 0

        for try await update in sut.stopSessionAndTranscribe() {
            switch update {
            case .session(let session):
                sessionStages.append(session.stage)
            case .transcript:
                transcriptEventCount += 1
            case .completion:
                break
            }
        }

        let discardedURL = recorder.discardedURL
        XCTAssertEqual(sessionStages, [.transcribing, .completed])
        XCTAssertEqual(transcriptEventCount, 3)
        XCTAssertEqual(discardedURL, artifactURL)
    }

    @MainActor
    func testSilentHotkeySessionSkipsModelInvocation() async throws {
        let artifactURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-coordinator-silent-\(UUID().uuidString).wav")
        try Data().write(to: artifactURL)
        defer { try? FileManager.default.removeItem(at: artifactURL) }

        let artifact = AudioRecordingArtifact(
            audioFileURL: artifactURL,
            frameStream: makeFrameStream(frames: Array(repeating: makeFrame(amplitude: 0, sampleCount: 1600), count: 4))
        )
        let finalTranscript = Transcript(
            rawText: "should not happen",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )
        let recorder = FakeAudioRecorder(artifact: artifact)
        let remoteEngine = FakeRemoteEngine(
            transcript: finalTranscript,
            events: [.done(finalTranscript)]
        )
        let sut = TranscriptionCoordinator(
            recorder: recorder,
            remoteEngine: remoteEngine,
            localEngine: FakeLocalEngine(transcript: finalTranscript),
            modelCatalogService: FakeModelCatalog()
        )

        _ = try await sut.startSession(
            request: TranscriptionSessionRequest(
                mode: .remote,
                localModel: .appleOnDevice,
                options: TranscriptionOptions(
                    modelID: "gpt-4o-mini-transcribe",
                    apiKey: "test-key",
                    responseFormat: "json",
                    stream: true
                ),
                interactionSettings: InteractionSettings(),
                recordingSessionContext: makeHotkeySessionContext()
            )
        )

        var completion: RecordingCompletionResult?
        var transcriptEvents = 0

        for try await update in sut.stopSessionAndTranscribe() {
            switch update {
            case .completion(let result):
                completion = result
            case .transcript:
                transcriptEvents += 1
            case .session:
                break
            }
        }

        XCTAssertEqual(remoteEngine.transcribeEventsCallCount, 0)
        XCTAssertEqual(transcriptEvents, 0)
        if case .some(.skippedSilence(let context)) = completion {
            XCTAssertEqual(context.audioActivitySummary?.speechDetected, false)
        } else {
            XCTFail("Expected skippedSilence completion result.")
        }
    }

    @MainActor
    func testHotkeySessionWithSpeechStillTranscribes() async throws {
        let artifactURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-coordinator-speech-\(UUID().uuidString).wav")
        try Data().write(to: artifactURL)
        defer { try? FileManager.default.removeItem(at: artifactURL) }

        let frames = Array(repeating: makeFrame(amplitude: 9_000, sampleCount: 1600), count: 3)
        let artifact = AudioRecordingArtifact(
            audioFileURL: artifactURL,
            frameStream: makeFrameStream(frames: frames)
        )
        let finalTranscript = Transcript(
            rawText: "hello world",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )
        let recorder = FakeAudioRecorder(artifact: artifact)
        let remoteEngine = FakeRemoteEngine(
            transcript: finalTranscript,
            events: [.done(finalTranscript)]
        )
        let sut = TranscriptionCoordinator(
            recorder: recorder,
            remoteEngine: remoteEngine,
            localEngine: FakeLocalEngine(transcript: finalTranscript),
            modelCatalogService: FakeModelCatalog()
        )

        _ = try await sut.startSession(
            request: TranscriptionSessionRequest(
                mode: .remote,
                localModel: .appleOnDevice,
                options: TranscriptionOptions(
                    modelID: "gpt-4o-mini-transcribe",
                    apiKey: "test-key",
                    responseFormat: "json",
                    stream: true
                ),
                interactionSettings: InteractionSettings(),
                recordingSessionContext: makeHotkeySessionContext()
            )
        )

        var completion: RecordingCompletionResult?

        for try await update in sut.stopSessionAndTranscribe() {
            if case .completion(let result) = update {
                completion = result
            }
        }

        XCTAssertEqual(remoteEngine.transcribeEventsCallCount, 1)
        if case .some(.transcribed(let context)) = completion {
            XCTAssertEqual(context?.audioActivitySummary?.speechDetected, true)
            XCTAssertGreaterThan(context?.audioActivitySummary?.voicedDuration ?? 0, 0)
        } else {
            XCTFail("Expected transcribed completion result.")
        }
    }

    @MainActor
    func testLocalWhisperSelectionUsesLocalEngineWithoutUnsupportedModelError() async throws {
        let artifactURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-coordinator-whisper-\(UUID().uuidString).wav")
        try Data().write(to: artifactURL)
        defer { try? FileManager.default.removeItem(at: artifactURL) }

        let artifact = AudioRecordingArtifact(
            audioFileURL: artifactURL,
            frameStream: AsyncStream { continuation in
                continuation.finish()
            }
        )
        let finalTranscript = Transcript(
            rawText: "hello whisper",
            segments: [TranscriptSegment(id: "seg-whisper", start: 0, end: 1, speaker: nil, text: "hello whisper")],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: LocalTranscriptionModel.whisperBase.rawValue,
            responseFormat: "text"
        )
        let localEngine = FakeLocalEngine(transcript: finalTranscript)
        let sut = TranscriptionCoordinator(
            recorder: FakeAudioRecorder(artifact: artifact),
            remoteEngine: FakeRemoteEngine(transcript: finalTranscript, events: [.done(finalTranscript)]),
            localEngine: localEngine,
            modelCatalogService: FakeModelCatalog()
        )

        _ = try await sut.startSession(
            request: TranscriptionSessionRequest(
                mode: .local,
                localModel: .whisperBase,
                options: TranscriptionOptions(modelID: LocalTranscriptionModel.whisperBase.rawValue, responseFormat: "text"),
                interactionSettings: InteractionSettings(),
                recordingSessionContext: nil
            )
        )

        var completion: RecordingCompletionResult?
        for try await update in sut.stopSessionAndTranscribe() {
            if case .completion(let result) = update {
                completion = result
            }
        }

        XCTAssertEqual(localEngine.transcribeBatchCallCount, 1)
        if case .some(.transcribed) = completion {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected transcribed completion result.")
        }
    }

    private func makeFrameStream(frames: [AudioPCM16Frame]) -> AsyncStream<AudioPCM16Frame> {
        AsyncStream { continuation in
            for frame in frames {
                continuation.yield(frame)
            }
            continuation.finish()
        }
    }

    private func makeFrame(amplitude: Int16, sampleCount: Int) -> AudioPCM16Frame {
        let samples = Array(repeating: amplitude, count: sampleCount)
        let data = samples.withUnsafeBytes { Data($0) }
        return AudioPCM16Frame(
            sequenceNumber: 1,
            sampleRate: 16_000,
            channelCount: 1,
            samples: data
        )
    }

    private func makeHotkeySessionContext() -> RecordingSessionContext {
        let context = ActiveAppContext(
            appName: "Messages",
            bundleID: "com.apple.MobileSMS",
            processIdentifier: 123,
            styleCategory: .personal,
            windowTitle: "Chat",
            focusedElementRole: "AXTextArea"
        )
        return RecordingSessionContext(
            activeAppContext: context,
            insertionTarget: context.insertionTarget,
            triggerSource: .hotkey,
            triggerMode: .holdToTalk
        )
    }
}

private final class FakeAudioRecorder: AudioRecorderServiceProtocol {
    let artifact: AudioRecordingArtifact
    private(set) var discardedURL: URL?

    init(artifact: AudioRecordingArtifact) {
        self.artifact = artifact
    }

    func startRecording() async throws -> AsyncStream<AudioPCM16Frame> {
        artifact.frameStream
    }

    func stopRecording() async throws -> AudioRecordingArtifact? {
        artifact
    }

    func discardRecordingArtifact(_ artifact: AudioRecordingArtifact?) {
        discardedURL = artifact?.audioFileURL
    }
}

private final class FakeRemoteEngine: TranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = "fake-remote"
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: true,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: false,
        supportsPrompt: true
    )

    private let transcript: Transcript
    private let events: [TranscriptEvent]
    private(set) var transcribeEventsCallCount = 0

    init(transcript: Transcript, events: [TranscriptEvent]) {
        self.transcript = transcript
        self.events = events
    }

    func transcribe(audioFileURL: URL, apiKey: String?, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }

    func transcribeEvents(source: TranscriptionSource, options: TranscriptionOptions) -> AsyncThrowingStream<TranscriptEvent, Error> {
        transcribeEventsCallCount += 1
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class FakeLocalEngine: LocalTranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = "fake-local"
    let capabilities = EngineCapabilities.none
    private let transcript: Transcript
    private(set) var transcribeBatchCallCount = 0

    init(transcript: Transcript) {
        self.transcript = transcript
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        transcript
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        transcribeBatchCallCount += 1
        return transcript
    }
}

private struct FakeModelCatalog: ModelCatalogServiceProtocol {
    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String> {
        ["gpt-4o-mini-transcribe"]
    }
}
