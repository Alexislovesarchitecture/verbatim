import Foundation
import XCTest
@testable import VerbatimSwiftMVP

final class ManagedWhisperKitRuntimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ManagedWhisperKitRuntimeURLProtocol.requestHandler = nil
        ManagedWhisperKitRuntimeURLProtocol.requestCounts = [:]
    }

    func testEnsureRunningLaunchesAndReportsHealthy() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("managed-runtime-\(UUID().uuidString)", isDirectory: true)
        let process = FakeManagedWhisperKitProcess()
        let launchBox = RuntimeLaunchBox(ports: [53_001], processes: [process])

        ManagedWhisperKitRuntimeURLProtocol.requestHandler = { request in
            if request.url?.path == "/health" {
                let body = try JSONEncoder().encode(
                    ManagedWhisperKitHealthResponse(
                        success: true,
                        message: "ok",
                        activeModel: nil,
                        helperState: .running,
                        prewarmState: .idle,
                        restartCount: 0
                    )
                )
                return (200, body)
            }
            return (404, Data())
        }

        let runtime = ManagedWhisperKitRuntime(
            session: makeSession(),
            baseDirectoryURL: tempRoot,
            executableURLProvider: { URL(fileURLWithPath: "/tmp/fake-helper") },
            portProvider: { launchBox.nextPort() },
            launchHandler: { _, _, _, _ in
                launchBox.recordLaunch()
                return launchBox.nextProcess()
            },
            healthTimeoutNanoseconds: 500_000_000
        )

        let metadata = try await runtime.ensureRunning()

        XCTAssertEqual(launchBox.launchCount, 1)
        XCTAssertEqual(metadata.helperState, .running)
        XCTAssertEqual(metadata.prewarmState, .idle)
        XCTAssertEqual(metadata.baseURL, "http://127.0.0.1:53001")
    }

    func testEnsureRunningRestartsAfterCrash() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("managed-runtime-\(UUID().uuidString)", isDirectory: true)
        let firstProcess = FakeManagedWhisperKitProcess()
        let secondProcess = FakeManagedWhisperKitProcess()
        let launchBox = RuntimeLaunchBox(ports: [53_011, 53_012], processes: [firstProcess, secondProcess])

        ManagedWhisperKitRuntimeURLProtocol.requestHandler = { request in
            if request.url?.path == "/health" {
                if request.url?.port == 53_011, firstProcess.running == false {
                    throw URLError(.cannotConnectToHost)
                }
                let body = try JSONEncoder().encode(
                    ManagedWhisperKitHealthResponse(
                        success: true,
                        message: "healthy",
                        activeModel: nil,
                        helperState: .running,
                        prewarmState: .idle,
                        restartCount: 0
                    )
                )
                return (200, body)
            }
            return (404, Data())
        }

        let runtime = ManagedWhisperKitRuntime(
            session: makeSession(),
            baseDirectoryURL: tempRoot,
            executableURLProvider: { URL(fileURLWithPath: "/tmp/fake-helper") },
            portProvider: { launchBox.nextPort() },
            launchHandler: { _, _, _, _ in
                launchBox.recordLaunch()
                return launchBox.nextProcess()
            },
            healthTimeoutNanoseconds: 500_000_000
        )

        _ = try await runtime.ensureRunning()
        firstProcess.running = false

        let metadata = try await runtime.ensureRunning()

        XCTAssertEqual(launchBox.launchCount, 2)
        XCTAssertEqual(metadata.helperState, .running)
        XCTAssertEqual(metadata.restartCount, 1)
        XCTAssertTrue(metadata.recoveredFromCrash)
        XCTAssertEqual(metadata.baseURL, "http://127.0.0.1:53012")
    }

    func testPrewarmIsIdempotentForSameModel() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("managed-runtime-\(UUID().uuidString)", isDirectory: true)
        let process = FakeManagedWhisperKitProcess()
        let modelDirectory = tempRoot.appendingPathComponent("models/base", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let stateBox = RuntimePrewarmStateBox()

        ManagedWhisperKitRuntimeURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/health":
                let body = try JSONEncoder().encode(
                    ManagedWhisperKitHealthResponse(
                        success: true,
                        message: "healthy",
                        activeModel: stateBox.activeModel,
                        helperState: .running,
                        prewarmState: stateBox.prewarmState,
                        restartCount: 0
                    )
                )
                return (200, body)
            case "/prewarm":
                stateBox.recordPrewarm(model: "base")
                let body = try JSONEncoder().encode(
                    ManagedWhisperKitHealthResponse(
                        success: true,
                        message: "prewarmed",
                        activeModel: "base",
                        helperState: .running,
                        prewarmState: .ready,
                        restartCount: 0
                    )
                )
                return (200, body)
            default:
                return (404, Data())
            }
        }

        let runtime = ManagedWhisperKitRuntime(
            session: makeSession(),
            baseDirectoryURL: tempRoot,
            executableURLProvider: { URL(fileURLWithPath: "/tmp/fake-helper") },
            portProvider: { 53_021 },
            launchHandler: { _, _, _, _ in process },
            healthTimeoutNanoseconds: 500_000_000
        )

        _ = try await runtime.prewarm(model: .whisperBase, modelDirectoryURL: modelDirectory)
        let second = try await runtime.prewarm(model: .whisperBase, modelDirectoryURL: modelDirectory)

        XCTAssertEqual(stateBox.prewarmCount, 1)
        XCTAssertEqual(second.prewarmState, .ready)
        XCTAssertEqual(second.activeModel, "base")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManagedWhisperKitRuntimeURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class FakeManagedWhisperKitProcess: ManagedWhisperKitProcessHandle {
    var running = true
    var isRunning: Bool { running }

    func terminate() {
        running = false
    }
}

private final class RuntimeLaunchBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var launchCount = 0
    private var ports: [UInt16]
    private var processes: [FakeManagedWhisperKitProcess]

    init(ports: [UInt16], processes: [FakeManagedWhisperKitProcess]) {
        self.ports = ports
        self.processes = processes
    }

    func recordLaunch() {
        lock.lock()
        launchCount += 1
        lock.unlock()
    }

    func nextPort() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return ports.removeFirst()
    }

    func nextProcess() -> FakeManagedWhisperKitProcess {
        lock.lock()
        defer { lock.unlock() }
        return processes.removeFirst()
    }
}

private final class RuntimePrewarmStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var prewarmCount = 0
    private(set) var activeModel: String?
    private(set) var prewarmState: ManagedWhisperKitPrewarmState = .idle

    func recordPrewarm(model: String) {
        lock.lock()
        prewarmCount += 1
        activeModel = model
        prewarmState = .ready
        lock.unlock()
    }
}

private final class ManagedWhisperKitRuntimeURLProtocol: URLProtocol {
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
                url: request.url!,
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
