import Foundation
import Network
import WhisperKit

enum WhisperKitManagedHelperRunner {
    static func runIfNeeded(arguments: [String]) -> Bool {
        guard arguments.dropFirst().first == "--whisperkit-helper" else {
            return false
        }

        let helperArguments = Array(arguments.dropFirst(2))
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = EXIT_SUCCESS

        Task {
            defer { semaphore.signal() }
            do {
                let output = try await run(arguments: helperArguments)
                if output.isEmpty == false {
                    FileHandle.standardOutput.write(output)
                }
            } catch {
                let message = error.localizedDescription + "\n"
                if let data = message.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
                exitCode = EXIT_FAILURE
            }
        }

        semaphore.wait()
        Foundation.exit(exitCode)
    }

    private static func run(arguments: [String]) async throws -> Data {
        guard let command = arguments.first else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing WhisperKit helper command.")
        }

        switch command {
        case "health":
            return try JSONEncoder().encode(
                ManagedWhisperKitHealthResponse(
                    success: true,
                    message: "Managed WhisperKit helper is ready.",
                    activeModel: nil,
                    helperState: .running,
                    prewarmState: .idle,
                    restartCount: 0
                )
            )
        case "transcribe":
            let payload = try await transcribe(arguments: Array(arguments.dropFirst()))
            return try JSONEncoder().encode(payload)
        case "server":
            try await serve(arguments: Array(arguments.dropFirst()))
            return Data()
        default:
            throw LocalTranscriptionError.whisperTranscriptionFailed("Unknown WhisperKit helper command: \(command)")
        }
    }

    private static func transcribe(arguments: [String]) async throws -> ManagedWhisperKitHelperResponse {
        let parsed = try parseInferenceArguments(arguments: arguments)
        let state = ManagedWhisperKitServerState()
        return try await state.infer(
            request: ManagedWhisperKitInferenceRequest(
                audioPath: parsed.audioPath,
                modelName: parsed.modelName,
                modelFolder: parsed.modelFolder
            )
        )
    }

    private static func serve(arguments: [String]) async throws {
        let config = try ManagedWhisperKitServerConfig(arguments: arguments)
        let state = ManagedWhisperKitServerState(
            stateFileURL: config.stateFileURL,
            logFileURL: config.logFileURL
        )
        let server = try ManagedWhisperKitHTTPServer(config: config, state: state)
        try await server.run()
    }

    private static func parseInferenceArguments(arguments: [String]) throws -> (audioPath: String, modelName: String, modelFolder: String) {
        var audioPath: String?
        var modelName: String?
        var modelFolder: String?
        var iterator = arguments.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--audio-path":
                audioPath = iterator.next()
            case "--model":
                modelName = iterator.next()
            case "--model-folder":
                modelFolder = iterator.next()
            default:
                continue
            }
        }

        guard let audioPath, !audioPath.isEmpty else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing --audio-path for WhisperKit helper.")
        }
        guard let modelName, !modelName.isEmpty else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing --model for WhisperKit helper.")
        }
        guard let modelFolder, !modelFolder.isEmpty else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing --model-folder for WhisperKit helper.")
        }

        return (audioPath, modelName, modelFolder)
    }
}

private struct ManagedWhisperKitServerConfig {
    let host: String
    let port: UInt16
    let stateFileURL: URL?
    let logFileURL: URL?

    init(arguments: [String]) throws {
        var baseURL: URL?
        var stateFileURL: URL?
        var logFileURL: URL?

        var iterator = arguments.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--base-url":
                if let value = iterator.next() {
                    baseURL = URL(string: value)
                }
            case "--state-file":
                if let value = iterator.next() {
                    stateFileURL = URL(fileURLWithPath: value)
                }
            case "--log-file":
                if let value = iterator.next() {
                    logFileURL = URL(fileURLWithPath: value)
                }
            default:
                continue
            }
        }

        guard let baseURL, let host = baseURL.host, let port = baseURL.port else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Missing valid --base-url for WhisperKit helper server.")
        }

        self.host = host
        self.port = UInt16(port)
        self.stateFileURL = stateFileURL
        self.logFileURL = logFileURL
    }
}

private actor ManagedWhisperKitServerState {
    private let stateFileURL: URL?
    private let logFileURL: URL?

    private var helperState: ManagedWhisperKitHelperState = .running
    private var prewarmState: ManagedWhisperKitPrewarmState = .idle
    private var activeModel: String?
    private var activeModelFolder: String?
    private var pipe: WhisperKit?

    init(stateFileURL: URL? = nil, logFileURL: URL? = nil) {
        self.stateFileURL = stateFileURL
        self.logFileURL = logFileURL
    }

    func healthResponse(message: String? = nil) throws -> ManagedWhisperKitHealthResponse {
        try writeStateSnapshot(message: message)
        return ManagedWhisperKitHealthResponse(
            success: true,
            message: message,
            activeModel: activeModel,
            helperState: helperState,
            prewarmState: prewarmState,
            restartCount: 0
        )
    }

    func prewarm(request: ManagedWhisperKitPrewarmRequest) async throws -> ManagedWhisperKitHealthResponse {
        prewarmState = .warming
        try await ensurePipeline(modelName: request.modelName, modelFolder: request.modelFolder)
        prewarmState = .ready
        return try healthResponse(message: "Model prewarmed.")
    }

    func infer(request: ManagedWhisperKitInferenceRequest) async throws -> ManagedWhisperKitHelperResponse {
        try await ensurePipeline(modelName: request.modelName, modelFolder: request.modelFolder)
        prewarmState = .ready
        let results = try await pipe?.transcribe(
            audioPath: request.audioPath,
            decodeOptions: DecodingOptions(verbose: false, withoutTimestamps: false, wordTimestamps: true)
        )

        let transcript = try Self.makeTranscript(results: results, modelID: request.modelName)
        try writeStateSnapshot(message: "Inference complete.")
        return ManagedWhisperKitHelperResponse(
            success: true,
            message: nil,
            transcript: transcript
        )
    }

    func prepareForShutdown() throws -> ManagedWhisperKitHealthResponse {
        helperState = .stopped
        prewarmState = .idle
        try writeStateSnapshot(message: "Shutting down helper.")
        return ManagedWhisperKitHealthResponse(
            success: true,
            message: "Managed WhisperKit helper shutting down.",
            activeModel: activeModel,
            helperState: helperState,
            prewarmState: prewarmState,
            restartCount: 0
        )
    }

    private func ensurePipeline(modelName: String, modelFolder: String) async throws {
        if activeModel == modelName, activeModelFolder == modelFolder, pipe != nil {
            return
        }

        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        pipe = try await WhisperKit(config)
        activeModel = modelName
        activeModelFolder = modelFolder
        try writeStateSnapshot(message: "Loaded model \(modelName).")
    }

    private func writeStateSnapshot(message: String?) throws {
        if let stateFileURL {
            let snapshot = ManagedWhisperKitHealthResponse(
                success: true,
                message: message,
                activeModel: activeModel,
                helperState: helperState,
                prewarmState: prewarmState,
                restartCount: 0
            )
            let data = try JSONEncoder().encode(snapshot)
            let parent = stateFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: stateFileURL, options: .atomic)
        }

        guard let logFileURL else { return }
        let parent = logFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logFileURL.path) == false {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message ?? "state=\(helperState.rawValue) prewarm=\(prewarmState.rawValue)")\n"
        guard let data = line.data(using: .utf8) else { return }
        let handle = try FileHandle(forWritingTo: logFileURL)
        try handle.seekToEnd()
        handle.write(data)
        try handle.close()
    }

    private static func makeTranscript(results: [TranscriptionResult]?, modelID: String) throws -> Transcript {
        let segments = (results ?? [])
            .flatMap { $0.segments }
            .map {
                TranscriptSegment(
                    start: TimeInterval($0.start),
                    end: TimeInterval($0.end),
                    speaker: nil,
                    text: $0.text
                )
            }
        let rawText = (results ?? [])
            .map { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard rawText.isEmpty == false else {
            throw LocalTranscriptionError.noTranscriptionResult
        }

        return Transcript(
            rawText: rawText,
            segments: segments,
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: modelID,
            responseFormat: "text"
        )
    }
}

private struct ManagedHTTPRequest {
    let method: String
    let path: String
    let body: Data
}

private struct ManagedHTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    func encoded() -> Data {
        var data = Data()
        let header = "HTTP/1.1 \(statusCode) \(statusText(for: statusCode))\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        data.append(header.data(using: .utf8)!)
        data.append(body)
        return data
    }

    private func statusText(for code: Int) -> String {
        switch code {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 404:
            return "Not Found"
        case 500:
            return "Internal Server Error"
        default:
            return "OK"
        }
    }
}

private final class ManagedWhisperKitHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ManagedWhisperKitHTTPServer")
    private let state: ManagedWhisperKitServerState

    init(config: ManagedWhisperKitServerConfig, state: ManagedWhisperKitServerState) throws {
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw LocalTranscriptionError.whisperTranscriptionFailed("Invalid helper port.")
        }
        listener = try NWListener(using: .tcp, on: port)
        self.state = state
    }

    func run() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var combined = buffer
            if let data {
                combined.append(data)
            }

            if let request = self.parseRequest(from: combined) {
                Task {
                    let response = await self.response(for: request)
                    connection.send(content: response.encoded(), completion: .contentProcessed { _ in
                        if request.path == "/shutdown" {
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                                Foundation.exit(EXIT_SUCCESS)
                            }
                        }
                        connection.cancel()
                    })
                }
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }

            self.receive(on: connection, buffer: combined)
        }
    }

    private func parseRequest(from data: Data) -> ManagedHTTPRequest? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<range.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestComponents = requestLine.components(separatedBy: " ")
        guard requestComponents.count >= 2 else {
            return nil
        }

        var contentLength = 0
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            if parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = range.upperBound
        let availableBodyLength = data.count - bodyStart
        guard availableBodyLength >= contentLength else {
            return nil
        }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return ManagedHTTPRequest(
            method: requestComponents[0],
            path: requestComponents[1],
            body: body
        )
    }

    private func response(for request: ManagedHTTPRequest) async -> ManagedHTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                let payload = try await state.healthResponse(message: "Managed WhisperKit helper is ready.")
                return try jsonResponse(payload)
            case ("POST", "/prewarm"):
                let payload = try JSONDecoder().decode(ManagedWhisperKitPrewarmRequest.self, from: request.body)
                let response = try await state.prewarm(request: payload)
                return try jsonResponse(response)
            case ("POST", "/inference"):
                let payload = try JSONDecoder().decode(ManagedWhisperKitInferenceRequest.self, from: request.body)
                let response = try await state.infer(request: payload)
                return try jsonResponse(response)
            case ("POST", "/shutdown"):
                let response = try await state.prepareForShutdown()
                return try jsonResponse(response)
            default:
                return ManagedHTTPResponse(
                    statusCode: 404,
                    body: Data("{\"error\":\"not_found\"}".utf8),
                    contentType: "application/json"
                )
            }
        } catch {
            let body = Data("{\"error\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}".utf8)
            return ManagedHTTPResponse(statusCode: 500, body: body, contentType: "application/json")
        }
    }

    private func jsonResponse<T: Encodable>(_ value: T) throws -> ManagedHTTPResponse {
        ManagedHTTPResponse(
            statusCode: 200,
            body: try JSONEncoder().encode(value),
            contentType: "application/json"
        )
    }
}
