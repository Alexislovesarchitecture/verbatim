import XCTest
@testable import VerbatimSwiftMVP

final class ManagedLocalTranscriptionServiceTests: XCTestCase {
    func testApplePathRecordsInProcessRouteResolution() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "managed-local-transcription-\(UUID().uuidString)",
            isDirectory: true
        )
        let routeTracker = LocalTranscriptionRouteTracker()
        let runtimeManager = ManagedLocalAppleSpeechRuntimeManagerStub(
            status: .ready(locale: Locale(identifier: "en_US")),
            snapshot: AppleSpeechRecognitionSnapshot(
                text: "apple local transcript",
                segments: [.init(start: 0, end: 1.2, text: "apple local transcript")]
            )
        )
        let service = ManagedLocalTranscriptionService(
            appleService: AppleLocalTranscriptionService(
                runtimeManager: runtimeManager,
                authorizationController: AppleSpeechAuthorizationController(
                    currentStatus: { .authorized },
                    requestStatus: { .authorized }
                )
            ),
            whisperKitService: WhisperKitLocalTranscriptionService(
                modelManager: WhisperKitModelManager(baseDirectoryURL: tempRoot),
                routeTracker: routeTracker
            ),
            whisperService: WhisperLocalTranscriptionService(
                modelManager: WhisperModelManager(baseDirectoryURL: tempRoot)
            ),
            whisperCppModelManager: WhisperModelManager(baseDirectoryURL: tempRoot),
            routeTracker: routeTracker
        )

        let transcript = try await service.transcribeBatch(
            audioURL: audioURL,
            options: TranscriptionOptions(
                modelID: LocalTranscriptionModel.appleOnDevice.rawValue,
                responseFormat: "text"
            )
        )
        let resolution = await service.latestRouteResolution()

        XCTAssertEqual(transcript.rawText, "apple local transcript")
        XCTAssertEqual(resolution?.configuredMode, .appleSpeech)
        XCTAssertEqual(resolution?.resolvedBackend, .appleSpeech)
        XCTAssertEqual(resolution?.selectedModel, .appleOnDevice)
        XCTAssertEqual(resolution?.transport, .inProcess)
        XCTAssertEqual(resolution?.lifecycleState, AppleSpeechAssetState.ready.rawValue)
        XCTAssertEqual(resolution?.helperState, nil)
        XCTAssertEqual(resolution?.prewarmState, nil)
        XCTAssertEqual(resolution?.failureStage, nil)
        XCTAssertEqual(resolution?.message, "Apple Dictation assets are installed for en_US.")
        XCTAssertFalse(resolution?.usedLegacyFallback ?? true)
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("managed-local-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private actor ManagedLocalAppleSpeechRuntimeManagerStub: AppleSpeechRuntimeManaging {
    let statusValue: AppleSpeechRuntimeStatus
    let snapshot: AppleSpeechRecognitionSnapshot

    init(status: AppleSpeechRuntimeStatus, snapshot: AppleSpeechRecognitionSnapshot) {
        self.statusValue = status
        self.snapshot = snapshot
    }

    func status(for preferredLocale: Locale) async -> AppleSpeechRuntimeStatus {
        statusValue
    }

    func installAssets(
        for preferredLocale: Locale,
        progress: (@Sendable (Double?) async -> Void)?
    ) async throws -> AppleSpeechRuntimeStatus {
        await progress?(1)
        return statusValue
    }

    func transcribe(audioFileURL: URL, preferredLocale: Locale) async throws -> AppleSpeechRecognitionSnapshot {
        snapshot
    }
}
