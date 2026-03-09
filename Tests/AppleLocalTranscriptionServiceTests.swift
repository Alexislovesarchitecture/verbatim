import XCTest
@testable import VerbatimSwiftMVP

final class AppleLocalTranscriptionServiceTests: XCTestCase {
    func testTranscribeFailsWhenSpeechUsageDescriptionIsMissing() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(),
            authorizationController: .authorized,
            missingUsageDescription: { _ in "Missing speech usage description." }
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected missing speech usage description error.")
        } catch let error as LocalTranscriptionError {
            guard case .missingSpeechUsageDescription(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Missing speech usage description.")
        }
    }

    func testTranscribeFailsWhenSpeechPermissionIsDenied() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(),
            authorizationController: .denied
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected denied permission error.")
        } catch let error as LocalTranscriptionError {
            XCTAssertEqual(error.errorDescription, LocalTranscriptionError.speechPermissionDenied.errorDescription)
        }
    }

    func testTranscribeFailsWhenSpeechPermissionIsRestricted() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(),
            authorizationController: .restricted
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected restricted permission error.")
        } catch let error as LocalTranscriptionError {
            XCTAssertEqual(error.errorDescription, LocalTranscriptionError.speechPermissionRestricted.errorDescription)
        }
    }

    func testTranscribeMapsUnsupportedLocaleError() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                transcribeError: .unsupportedLocale("Locale not supported.")
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected unsupported locale error.")
        } catch let error as LocalTranscriptionError {
            guard case .unsupportedLocale(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Locale not supported.")
        }
    }

    func testTranscribeMapsAssetsNotInstalledError() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                transcribeError: .assetsNotInstalled("Install Apple Dictation assets first.")
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected assets not installed error.")
        } catch let error as LocalTranscriptionError {
            guard case .appleSpeechAssetsNotInstalled(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Install Apple Dictation assets first.")
        }
    }

    func testTranscribeMapsAssetsInstallingError() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                transcribeError: .assetsInstalling("Apple Dictation assets are still installing.")
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected assets installing error.")
        } catch let error as LocalTranscriptionError {
            guard case .appleSpeechAssetsInstalling(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Apple Dictation assets are still installing.")
        }
    }

    func testTranscribeMapsInstallFailureError() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                transcribeError: .installationFailed("Apple Dictation asset installation failed.")
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected install failure error.")
        } catch let error as LocalTranscriptionError {
            guard case .appleSpeechInstallFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Apple Dictation asset installation failed.")
        }
    }

    func testTranscribeMapsAnalyzerFailure() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                transcribeError: .analyzerFailed("Analyzer failed.")
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected analyzer failure.")
        } catch let error as LocalTranscriptionError {
            guard case .recognitionFailed(let wrappedError) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(wrappedError.localizedDescription, "Analyzer failed.")
        }
    }

    func testTranscribeFailsWhenSnapshotIsEmpty() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                snapshot: AppleSpeechRecognitionSnapshot(text: "", segments: [])
            ),
            authorizationController: .authorized
        )

        do {
            _ = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)
            XCTFail("Expected empty transcription error.")
        } catch let error as LocalTranscriptionError {
            XCTAssertEqual(error.errorDescription, LocalTranscriptionError.noTranscriptionResult.errorDescription)
        }
    }

    func testTranscribeBuildsTranscriptFromSnapshotSegments() async throws {
        let audioURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = AppleLocalTranscriptionService(
            runtimeManager: AppleSpeechRuntimeManagerStub(
                snapshot: AppleSpeechRecognitionSnapshot(
                    text: "hello world",
                    segments: [
                        .init(start: 0, end: 0.4, text: "hello"),
                        .init(start: 0.4, end: 0.9, text: "world"),
                    ]
                )
            ),
            authorizationController: .authorized
        )

        let transcript = try await service.transcribeLocally(audioFileURL: audioURL, model: .appleOnDevice)

        XCTAssertEqual(transcript.rawText, "hello world")
        XCTAssertEqual(transcript.modelID, LocalTranscriptionModel.appleOnDevice.rawValue)
        XCTAssertEqual(transcript.responseFormat, "text")
        XCTAssertEqual(transcript.segments.count, 2)
        XCTAssertEqual(transcript.segments[0].text, "hello")
        XCTAssertEqual(transcript.segments[0].start, 0)
        XCTAssertEqual(transcript.segments[1].text, "world")
        XCTAssertEqual(transcript.segments[1].end, 0.9)
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("apple-local-service-\(UUID().uuidString).wav")
        try Data("audio".utf8).write(to: url)
        return url
    }
}

private actor AppleSpeechRuntimeManagerStub: AppleSpeechRuntimeManaging {
    private let snapshot: AppleSpeechRecognitionSnapshot
    private let transcribeError: AppleSpeechRuntimeError?

    init(
        snapshot: AppleSpeechRecognitionSnapshot = AppleSpeechRecognitionSnapshot(
            text: "hello",
            segments: [.init(start: 0, end: 1, text: "hello")]
        ),
        transcribeError: AppleSpeechRuntimeError? = nil
    ) {
        self.snapshot = snapshot
        self.transcribeError = transcribeError
    }

    func status(for preferredLocale: Locale) async -> AppleSpeechRuntimeStatus {
        .ready(locale: preferredLocale)
    }

    func installAssets(
        for preferredLocale: Locale,
        progress: (@Sendable (Double?) async -> Void)?
    ) async throws -> AppleSpeechRuntimeStatus {
        await progress?(1)
        return .ready(locale: preferredLocale)
    }

    func transcribe(audioFileURL: URL, preferredLocale: Locale) async throws -> AppleSpeechRecognitionSnapshot {
        if let transcribeError {
            throw transcribeError
        }
        return snapshot
    }
}

private extension AppleSpeechAuthorizationController {
    static let authorized = AppleSpeechAuthorizationController(
        currentStatus: { .authorized },
        requestStatus: { .authorized }
    )

    static let denied = AppleSpeechAuthorizationController(
        currentStatus: { .denied },
        requestStatus: { .denied }
    )

    static let restricted = AppleSpeechAuthorizationController(
        currentStatus: { .restricted },
        requestStatus: { .restricted }
    )
}
