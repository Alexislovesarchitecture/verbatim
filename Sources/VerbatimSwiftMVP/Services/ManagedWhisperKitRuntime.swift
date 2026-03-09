import Foundation

enum LocalTranscriptionTransport: String, Codable, Sendable {
    case inProcess = "in_process"
    case managedHelper = "managed_helper"
    case externalServer = "external_server"
}

enum ManagedWhisperKitHelperState: String, Codable, Sendable {
    case stopped
    case launching
    case running
    case restarting
    case failed
}

enum ManagedWhisperKitPrewarmState: String, Codable, Sendable {
    case idle
    case warming
    case ready
    case failed
}

enum LocalTranscriptionFailureStage: String, Codable, Sendable {
    case launch
    case health
    case convert
    case inference
    case responseParse
}

struct ManagedWhisperKitRuntimeMetadata: Equatable, Sendable {
    let baseURL: String?
    let helperState: ManagedWhisperKitHelperState
    let prewarmState: ManagedWhisperKitPrewarmState
    let activeModel: String?
    let restartCount: Int
    let recoveredFromCrash: Bool
    let lastFailureMessage: String?
}

enum ManagedWhisperKitRuntimeError: LocalizedError {
    case executableUnavailable
    case launchFailed(String)
    case healthCheckFailed(String)
    case inferenceFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "Managed WhisperKit helper executable is unavailable."
        case .launchFailed(let message):
            return "Managed WhisperKit helper launch failed: \(message)"
        case .healthCheckFailed(let message):
            return "Managed WhisperKit helper health check failed: \(message)"
        case .inferenceFailed(let message):
            return "Managed WhisperKit inference failed: \(message)"
        case .invalidResponse(let message):
            return "Managed WhisperKit returned an invalid response: \(message)"
        }
    }
}

struct ManagedWhisperKitHealthResponse: Codable, Equatable, Sendable {
    let success: Bool
    let message: String?
    let activeModel: String?
    let helperState: ManagedWhisperKitHelperState
    let prewarmState: ManagedWhisperKitPrewarmState
    let restartCount: Int
}

struct ManagedWhisperKitPrewarmRequest: Codable, Equatable, Sendable {
    let modelName: String
    let modelFolder: String
}

struct ManagedWhisperKitInferenceRequest: Codable, Equatable, Sendable {
    let audioPath: String
    let modelName: String
    let modelFolder: String
}

struct ManagedWhisperKitShutdownRequest: Codable, Equatable, Sendable {
    let reason: String
}

protocol ManagedWhisperKitRuntimeProtocol: AnyObject, Sendable {
    func ensureRunning() async throws -> ManagedWhisperKitRuntimeMetadata
    func health() async -> ManagedWhisperKitRuntimeMetadata
    func prewarm(model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> ManagedWhisperKitRuntimeMetadata
    func transcribe(audioFileURL: URL, model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> Transcript
    func shutdown() async
    func latestMetadata() async -> ManagedWhisperKitRuntimeMetadata
}

protocol ManagedWhisperKitProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

extension Process: ManagedWhisperKitProcessHandle {}

actor ManagedWhisperKitRuntime: ManagedWhisperKitRuntimeProtocol {
    typealias ExecutableURLProvider = @Sendable () -> URL?
    typealias PortProvider = @Sendable () -> UInt16
    typealias LaunchHandler = @Sendable (URL, URL, URL, URL) throws -> any ManagedWhisperKitProcessHandle

    private let session: URLSession
    private let fileManager: FileManager
    private let paths: LocalRuntimePaths
    private let executableURLProvider: ExecutableURLProvider
    private let portProvider: PortProvider
    private let healthTimeoutNanoseconds: UInt64
    private let launchHandler: LaunchHandler?

    private var process: (any ManagedWhisperKitProcessHandle)?
    private var logHandle: FileHandle?
    private var baseURL: URL?
    private var helperState: ManagedWhisperKitHelperState = .stopped
    private var prewarmState: ManagedWhisperKitPrewarmState = .idle
    private var activeModel: String?
    private var restartCount: Int = 0
    private var recoveredFromCrash = false
    private var lastFailureMessage: String?
    private var launchCount: Int = 0

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        executableURLProvider: @escaping ExecutableURLProvider = { Bundle.main.executableURL },
        portProvider: @escaping PortProvider = {
            UInt16(Int.random(in: 49_152...65_000))
        },
        launchHandler: LaunchHandler? = nil,
        healthTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.session = session
        self.fileManager = fileManager
        self.paths = LocalRuntimePaths(fileManager: fileManager, baseDirectoryURL: baseDirectoryURL)
        self.executableURLProvider = executableURLProvider
        self.portProvider = portProvider
        self.launchHandler = launchHandler
        self.healthTimeoutNanoseconds = healthTimeoutNanoseconds
    }

    func ensureRunning() async throws -> ManagedWhisperKitRuntimeMetadata {
        if let baseURL, let response = await probeHealth(baseURL: baseURL) {
            applyHealthResponse(response, baseURL: baseURL)
            return metadata(baseURL: baseURL)
        }

        if let process, process.isRunning == false {
            recoveredFromCrash = launchCount > 0
            if recoveredFromCrash {
                restartCount += 1
            }
            helperState = launchCount > 0 ? .restarting : .stopped
            self.process = nil
        }

        try paths.ensureDirectoriesExist()
        let executableURL = try resolveExecutableURL()
        let nextBaseURL = URL(string: "http://127.0.0.1:\(portProvider())")!
        helperState = launchCount == 0 ? .launching : .restarting
        prewarmState = .idle
        activeModel = nil

        do {
            try launchHelper(executableURL: executableURL, baseURL: nextBaseURL)
        } catch {
            helperState = .failed
            lastFailureMessage = error.localizedDescription
            throw ManagedWhisperKitRuntimeError.launchFailed(error.localizedDescription)
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + healthTimeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let response = await probeHealth(baseURL: nextBaseURL) {
                applyHealthResponse(response, baseURL: nextBaseURL)
                return metadata(baseURL: nextBaseURL)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        helperState = .failed
        lastFailureMessage = "Timed out waiting for the helper server to respond."
        if let process, process.isRunning {
            process.terminate()
        }
        try? logHandle?.close()
        logHandle = nil
        self.process = nil
        self.baseURL = nil
        throw ManagedWhisperKitRuntimeError.healthCheckFailed("Timed out waiting for the helper server to respond.")
    }

    func health() async -> ManagedWhisperKitRuntimeMetadata {
        if let baseURL, let response = await probeHealth(baseURL: baseURL) {
            applyHealthResponse(response, baseURL: baseURL)
            return metadata(baseURL: baseURL)
        }

        if let process, process.isRunning == false {
            recoveredFromCrash = launchCount > 0
            helperState = recoveredFromCrash ? .restarting : .stopped
            self.process = nil
        }

        return metadata(baseURL: baseURL)
    }

    func prewarm(model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> ManagedWhisperKitRuntimeMetadata {
        let runtime = try await ensureRunning()
        guard let baseURLString = runtime.baseURL, let runtimeBaseURL = URL(string: baseURLString) else {
            throw ManagedWhisperKitRuntimeError.healthCheckFailed("Managed WhisperKit helper URL is unavailable.")
        }
        let requestedModelName = model.whisperKitModelName ?? model.rawValue
        if activeModel == requestedModelName, prewarmState == .ready {
            return metadata(baseURL: runtimeBaseURL)
        }

        prewarmState = .warming
        let payload = ManagedWhisperKitPrewarmRequest(
            modelName: requestedModelName,
            modelFolder: modelDirectoryURL.path
        )
        let response = try await sendJSONRequest(
            baseURL: runtimeBaseURL,
            path: "/prewarm",
            method: "POST",
            payload: payload,
            responseType: ManagedWhisperKitHealthResponse.self
        )
        guard response.success else {
            prewarmState = .failed
            lastFailureMessage = response.message
            throw ManagedWhisperKitRuntimeError.inferenceFailed(response.message ?? "Prewarm failed.")
        }
        applyHealthResponse(response, baseURL: runtimeBaseURL)
        return metadata(baseURL: runtimeBaseURL)
    }

    func transcribe(audioFileURL: URL, model: LocalTranscriptionModel, modelDirectoryURL: URL) async throws -> Transcript {
        try paths.ensureDirectoriesExist()
        let canonicalAudioURL: URL
        do {
            canonicalAudioURL = try CanonicalAudioFileWriter.materializeCanonicalWAV(
                from: audioFileURL,
                outputDirectory: paths.helperAudioDirectory,
                fileManager: fileManager
            )
        } catch {
            throw error
        }
        defer {
            try? fileManager.removeItem(at: canonicalAudioURL)
        }

        let runtime = try await prewarm(model: model, modelDirectoryURL: modelDirectoryURL)
        guard let baseURLString = runtime.baseURL, let runtimeBaseURL = URL(string: baseURLString) else {
            throw ManagedWhisperKitRuntimeError.healthCheckFailed("Managed WhisperKit helper URL is unavailable.")
        }

        let payload = ManagedWhisperKitInferenceRequest(
            audioPath: canonicalAudioURL.path,
            modelName: model.whisperKitModelName ?? model.rawValue,
            modelFolder: modelDirectoryURL.path
        )
        let response = try await sendJSONRequest(
            baseURL: runtimeBaseURL,
            path: "/inference",
            method: "POST",
            payload: payload,
            responseType: ManagedWhisperKitHelperResponse.self
        )

        if response.success == false {
            lastFailureMessage = response.message
            throw ManagedWhisperKitRuntimeError.inferenceFailed(response.message ?? "Inference failed.")
        }
        guard let transcript = response.transcript else {
            lastFailureMessage = "Missing transcript payload."
            throw ManagedWhisperKitRuntimeError.invalidResponse("Missing transcript payload.")
        }
        return transcript
    }

    func shutdown() async {
        if let baseURL {
            _ = try? await sendJSONRequest(
                baseURL: baseURL,
                path: "/shutdown",
                method: "POST",
                payload: ManagedWhisperKitShutdownRequest(reason: "client_shutdown"),
                responseType: ManagedWhisperKitHealthResponse.self
            )
        }

        if let process, process.isRunning {
            process.terminate()
        }
        try? logHandle?.close()
        logHandle = nil
        process = nil
        baseURL = nil
        helperState = .stopped
        prewarmState = .idle
        activeModel = nil
    }

    func latestMetadata() async -> ManagedWhisperKitRuntimeMetadata {
        metadata(baseURL: baseURL)
    }

    private func resolveExecutableURL() throws -> URL {
        guard let executableURL = executableURLProvider() else {
            throw ManagedWhisperKitRuntimeError.executableUnavailable
        }
        return executableURL
    }

    private func launchHelper(executableURL: URL, baseURL: URL) throws {
        let stateFileURL = paths.helperStateDirectory.appendingPathComponent("helper-state.json")
        let logFileURL = paths.helperLogsDirectory.appendingPathComponent("helper.log")
        if let launchHandler {
            let process = try launchHandler(executableURL, baseURL, stateFileURL, logFileURL)
            self.process = process
            self.baseURL = baseURL
            launchCount += 1
            lastFailureMessage = nil
            return
        }

        if fileManager.fileExists(atPath: logFileURL.path) == false {
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }

        try logHandle?.close()
        let logHandle = try FileHandle(forWritingTo: logFileURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--whisperkit-helper",
            "server",
            "--base-url", baseURL.absoluteString,
            "--state-file", stateFileURL.path,
            "--log-file", logFileURL.path
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()

        self.process = process
        self.logHandle = logHandle
        self.baseURL = baseURL
        launchCount += 1
        lastFailureMessage = nil
    }

    private func probeHealth(baseURL: URL) async -> ManagedWhisperKitHealthResponse? {
        do {
            return try await sendJSONRequest(
                baseURL: baseURL,
                path: "/health",
                method: "GET",
                payload: Optional<String>.none,
                responseType: ManagedWhisperKitHealthResponse.self
            )
        } catch {
            lastFailureMessage = error.localizedDescription
            return nil
        }
    }

    private func applyHealthResponse(_ response: ManagedWhisperKitHealthResponse, baseURL: URL) {
        self.baseURL = baseURL
        helperState = response.helperState
        prewarmState = response.prewarmState
        activeModel = response.activeModel
        restartCount = max(restartCount, response.restartCount)
        lastFailureMessage = response.message
    }

    private func metadata(baseURL: URL?) -> ManagedWhisperKitRuntimeMetadata {
        ManagedWhisperKitRuntimeMetadata(
            baseURL: baseURL?.absoluteString,
            helperState: helperState,
            prewarmState: prewarmState,
            activeModel: activeModel,
            restartCount: restartCount,
            recoveredFromCrash: recoveredFromCrash,
            lastFailureMessage: lastFailureMessage
        )
    }

    private func sendJSONRequest<Payload: Encodable, Response: Decodable>(
        baseURL: URL,
        path: String,
        method: String,
        payload: Payload,
        responseType: Response.Type
    ) async throws -> Response {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ManagedWhisperKitRuntimeError.healthCheckFailed("HTTP \(statusCode). \(body)")
        }

        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw ManagedWhisperKitRuntimeError.invalidResponse(error.localizedDescription)
        }
    }
}
