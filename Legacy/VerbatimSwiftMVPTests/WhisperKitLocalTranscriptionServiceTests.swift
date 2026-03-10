import AVFoundation
import XCTest
@testable import VerbatimSwiftMVP

final class WhisperKitLocalTranscriptionServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ExternalWhisperServerURLProtocol.requestHandler = nil
        ExternalWhisperServerURLProtocol.requestCounts = [:]
    }

    func testCanonicalAudioFileWriterProduces16KMonoWAV() throws {
        let inputURL = try makeAudioFile(sampleRate: 48_000, channelCount: 1, frameCount: 4_800)
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("canonical-wav-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        let outputURL = try CanonicalAudioFileWriter.materializeCanonicalWAV(
            from: inputURL,
            outputDirectory: outputDirectory
        )
        let file = try AVAudioFile(forReading: outputURL)

        XCTAssertEqual(file.processingFormat.sampleRate, 16_000, accuracy: 0.5)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
    }

    func testManagedHelperPathRecordsManagedTransport() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whisperkit-service-\(UUID().uuidString)", isDirectory: true)
        let modelManager = makeModelManager(tempRoot: tempRoot)
        let routeTracker = LocalTranscriptionRouteTracker()
        let fakeRuntime = FakeManagedWhisperKitRuntime()
        let serverManager = WhisperKitServerManager(managedRuntime: fakeRuntime)
        let service = WhisperKitLocalTranscriptionService(
            modelManager: modelManager,
            routeTracker: routeTracker,
            serverManager: serverManager
        )
        let audioURL = try makeAudioFile(sampleRate: 48_000, channelCount: 1, frameCount: 4_800)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let transcript = try await service.transcribeBatch(
            audioURL: audioURL,
            options: TranscriptionOptions(
                modelID: LocalTranscriptionModel.whisperBase.rawValue,
                responseFormat: "text",
                localEngineMode: .whisperKit,
                whisperKitServerConnectionMode: .managedHelper
            )
        )

        let route = await routeTracker.latest()

        XCTAssertEqual(transcript.rawText, "managed helper transcript")
        XCTAssertEqual(route?.transport, .managedHelper)
        XCTAssertEqual(route?.helperState, .running)
        XCTAssertEqual(route?.prewarmState, .ready)
        XCTAssertNil(route?.failureStage)
    }

    func testManagedHelperInferenceFailureRecordsFailureStage() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whisperkit-service-\(UUID().uuidString)", isDirectory: true)
        let modelManager = makeModelManager(tempRoot: tempRoot)
        let routeTracker = LocalTranscriptionRouteTracker()
        let fakeRuntime = FakeManagedWhisperKitRuntime()
        await fakeRuntime.setErrors([ManagedWhisperKitRuntimeError.inferenceFailed("boom")])
        let service = WhisperKitLocalTranscriptionService(
            modelManager: modelManager,
            routeTracker: routeTracker,
            serverManager: WhisperKitServerManager(managedRuntime: fakeRuntime)
        )
        let audioURL = try makeAudioFile(sampleRate: 16_000, channelCount: 1, frameCount: 1_600)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await XCTAssertThrowsErrorAsync(
            try await service.transcribeBatch(
                audioURL: audioURL,
                options: TranscriptionOptions(
                    modelID: LocalTranscriptionModel.whisperBase.rawValue,
                    responseFormat: "text",
                    localEngineMode: .whisperKit,
                    whisperKitServerConnectionMode: .managedHelper
                )
            )
        ) { error in
            guard case LocalTranscriptionError.whisperTranscriptionFailed(let message) = error else {
                return XCTFail("Expected whisperTranscriptionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("Managed WhisperKit inference failed"))
        }

        let route = await routeTracker.latest()
        XCTAssertEqual(route?.failureStage, .inference)
        XCTAssertEqual(route?.transport, .managedHelper)
    }

    func testManagedHelperMalformedResponseRecordsResponseParseStage() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whisperkit-service-\(UUID().uuidString)", isDirectory: true)
        let modelManager = makeModelManager(tempRoot: tempRoot)
        let routeTracker = LocalTranscriptionRouteTracker()
        let fakeRuntime = FakeManagedWhisperKitRuntime()
        await fakeRuntime.setErrors([ManagedWhisperKitRuntimeError.invalidResponse("bad payload")])
        let service = WhisperKitLocalTranscriptionService(
            modelManager: modelManager,
            routeTracker: routeTracker,
            serverManager: WhisperKitServerManager(managedRuntime: fakeRuntime)
        )
        let audioURL = try makeAudioFile(sampleRate: 16_000, channelCount: 1, frameCount: 1_600)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await XCTAssertThrowsErrorAsync(
            try await service.transcribeBatch(
                audioURL: audioURL,
                options: TranscriptionOptions(
                    modelID: LocalTranscriptionModel.whisperBase.rawValue,
                    responseFormat: "text",
                    localEngineMode: .whisperKit,
                    whisperKitServerConnectionMode: .managedHelper
                )
            )
        ) { _ in }

        let route = await routeTracker.latest()
        XCTAssertEqual(route?.failureStage, .responseParse)
    }

    func testManagedHelperCanRecoverAfterFailedInference() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whisperkit-service-\(UUID().uuidString)", isDirectory: true)
        let modelManager = makeModelManager(tempRoot: tempRoot)
        let routeTracker = LocalTranscriptionRouteTracker()
        let fakeRuntime = FakeManagedWhisperKitRuntime()
        await fakeRuntime.setErrors([
            ManagedWhisperKitRuntimeError.inferenceFailed("first failure")
        ])
        let service = WhisperKitLocalTranscriptionService(
            modelManager: modelManager,
            routeTracker: routeTracker,
            serverManager: WhisperKitServerManager(managedRuntime: fakeRuntime)
        )
        let audioURL = try makeAudioFile(sampleRate: 16_000, channelCount: 1, frameCount: 1_600)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await service.transcribeBatch(
                audioURL: audioURL,
                options: TranscriptionOptions(
                    modelID: LocalTranscriptionModel.whisperBase.rawValue,
                    responseFormat: "text",
                    localEngineMode: .whisperKit,
                    whisperKitServerConnectionMode: .managedHelper
                )
            )
            XCTFail("Expected first inference to fail")
        } catch {}

        let transcript = try await service.transcribeBatch(
            audioURL: audioURL,
            options: TranscriptionOptions(
                modelID: LocalTranscriptionModel.whisperBase.rawValue,
                responseFormat: "text",
                localEngineMode: .whisperKit,
                whisperKitServerConnectionMode: .managedHelper
            )
        )

        let route = await routeTracker.latest()
        XCTAssertEqual(transcript.rawText, "managed helper transcript")
        XCTAssertNil(route?.failureStage)
    }

    func testExternalServerPathUsesOpenWhisprInferenceWithoutLocalInstall() async throws {
        ExternalWhisperServerURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/v1/audio/transcriptions":
                return (404, Data("missing".utf8))
            case "/inference":
                return (200, Data(#"{"text":"openwhispr transcript"}"#.utf8))
            default:
                return (404, Data())
            }
        }

        let routeTracker = LocalTranscriptionRouteTracker()
        let service = WhisperKitLocalTranscriptionService(
            modelManager: WhisperKitModelManager(
                runtimeStatusProvider: {
                    WhisperRuntimeStatus(isSupported: false, message: "Local WhisperKit install unavailable.")
                }
            ),
            routeTracker: routeTracker,
            serverManager: WhisperKitServerManager(
                session: makeSession(),
                managedRuntime: FakeManagedWhisperKitRuntime()
            )
        )
        let audioURL = try makeAudioFile(sampleRate: 16_000, channelCount: 1, frameCount: 1_600)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let transcript = try await service.transcribeBatch(
            audioURL: audioURL,
            options: TranscriptionOptions(
                modelID: LocalTranscriptionModel.whisperBase.rawValue,
                responseFormat: "text",
                localEngineMode: .whisperKit,
                whisperKitServerConnectionMode: .externalServer,
                whisperKitServerBaseURL: "http://127.0.0.1:8178"
            )
        )

        let route = await routeTracker.latest()
        XCTAssertEqual(transcript.rawText, "openwhispr transcript")
        XCTAssertEqual(route?.transport, .externalServer)
        XCTAssertEqual(route?.lifecycleState, "external_server")
        XCTAssertNil(route?.failureStage)
        XCTAssertEqual(ExternalWhisperServerURLProtocol.requestCounts["/v1/audio/transcriptions"], 1)
        XCTAssertEqual(ExternalWhisperServerURLProtocol.requestCounts["/inference"], 1)
    }

    func testExternalServerStatusFallsBackToRootHealthCheck() async throws {
        ExternalWhisperServerURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/health":
                return (404, Data())
            case "/":
                return (200, Data(#"{"activeModel":"large-v3"}"#.utf8))
            default:
                return (404, Data())
            }
        }

        let status = await WhisperKitServerManager(
            session: makeSession(),
            managedRuntime: FakeManagedWhisperKitRuntime()
        ).status(
            connectionMode: .externalServer,
            externalBaseURL: "http://127.0.0.1:8178"
        )

        XCTAssertTrue(status.isReachable)
        XCTAssertEqual(status.activeModel, "large-v3")
        XCTAssertEqual(status.message, "OpenWhispr-style Whisper server is reachable.")
        XCTAssertEqual(ExternalWhisperServerURLProtocol.requestCounts["/health"], 1)
        XCTAssertEqual(ExternalWhisperServerURLProtocol.requestCounts["/"], 1)
    }

    private func makeModelManager(tempRoot: URL) -> WhisperKitModelManager {
        let paths = LocalRuntimePaths(baseDirectoryURL: tempRoot)
        let modelDirectory = paths.whisperKitRoot
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai_whisper-base", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("AudioEncoder.mlmodelc").path, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("TextDecoder.mlmodelc").path, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent("MelSpectrogram.mlmodelc").path, contents: Data("x".utf8))

        return WhisperKitModelManager(
            baseDirectoryURL: tempRoot,
            runtimeStatusProvider: {
                WhisperRuntimeStatus(isSupported: true, message: "WhisperKit is available on this Mac.")
            }
        )
    }

    private func makeAudioFile(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        frameCount: AVAudioFrameCount
    ) throws -> URL {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("managed-helper-audio-\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for channel in 0..<Int(channelCount) {
            let channelData = buffer.floatChannelData![channel]
            for index in 0..<Int(frameCount) {
                channelData[index] = channel == 0 ? 0.2 : 0.05
            }
        }

        try file.write(from: buffer)
        return url
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExternalWhisperServerURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private actor FakeManagedWhisperKitRuntime: ManagedWhisperKitRuntimeProtocol {
    private var metadata = ManagedWhisperKitRuntimeMetadata(
        baseURL: "http://127.0.0.1:54001",
        helperState: .running,
        prewarmState: .idle,
        activeModel: nil,
        restartCount: 0,
        recoveredFromCrash: false,
        lastFailureMessage: nil
    )
    private var errors: [Error] = []

    func setErrors(_ errors: [Error]) {
        self.errors = errors
    }

    func ensureRunning() async throws -> ManagedWhisperKitRuntimeMetadata {
        metadata
    }

    func health() async -> ManagedWhisperKitRuntimeMetadata {
        metadata
    }

    func prewarm(model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> ManagedWhisperKitRuntimeMetadata {
        metadata = ManagedWhisperKitRuntimeMetadata(
            baseURL: metadata.baseURL,
            helperState: .running,
            prewarmState: .ready,
            activeModel: model.whisperKitModelName ?? model.rawValue,
            restartCount: metadata.restartCount,
            recoveredFromCrash: metadata.recoveredFromCrash,
            lastFailureMessage: nil
        )
        return metadata
    }

    func transcribe(audioFileURL: URL, model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> Transcript {
        if errors.isEmpty == false {
            throw errors.removeFirst()
        }
        metadata = ManagedWhisperKitRuntimeMetadata(
            baseURL: metadata.baseURL,
            helperState: .running,
            prewarmState: .ready,
            activeModel: model.whisperKitModelName ?? model.rawValue,
            restartCount: metadata.restartCount,
            recoveredFromCrash: metadata.recoveredFromCrash,
            lastFailureMessage: nil
        )
        return Transcript(
            rawText: "managed helper transcript",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: model.rawValue,
            responseFormat: "text"
        )
    }

    func shutdown() async {}

    func latestMetadata() async -> ManagedWhisperKitRuntimeMetadata {
        metadata
    }
}

private final class ExternalWhisperServerURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (Int, Data))?
    static var requestCounts: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let path = request.url?.path ?? "/"
            Self.requestCounts[path, default: 0] += 1
            let (statusCode, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ verify: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        verify(error)
    }
}
