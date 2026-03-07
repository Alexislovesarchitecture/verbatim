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
                )
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
            }
        }

        let discardedURL = recorder.discardedURL
        XCTAssertEqual(sessionStages, [.transcribing, .completed])
        XCTAssertEqual(transcriptEventCount, 3)
        XCTAssertEqual(discardedURL, artifactURL)
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

private final class FakeRemoteEngine: TranscriptionServiceProtocol {
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
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class FakeLocalEngine: LocalTranscriptionServiceProtocol {
    let engineID = "fake-local"
    let capabilities = EngineCapabilities.none
    private let transcript: Transcript

    init(transcript: Transcript) {
        self.transcript = transcript
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        transcript
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }
}

private struct FakeModelCatalog: ModelCatalogServiceProtocol {
    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String> {
        ["gpt-4o-mini-transcribe"]
    }
}
