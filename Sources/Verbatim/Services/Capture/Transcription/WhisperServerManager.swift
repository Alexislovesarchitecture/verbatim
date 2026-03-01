import Foundation
import Darwin

enum WhisperServerManagerError: Error {
    case binaryNotFound
    case binaryNotExecutable
    case startupTimeout
    case processExited(String)
}

actor WhisperServerManager {
    private enum Constants {
        static let host = "127.0.0.1"
        static let portRangeStart = 8178
        static let portRangeEnd = 8199
        static let startupTimeout: TimeInterval = 30
        static let healthPollIntervalMS: UInt64 = 100
    }

    struct ServerConfig {
        var threads: Int = 4
        var language: String = "auto"
    }

    private var process: Process?
    private var currentModelPath: String?
    private var currentPort: Int?
    private var currentBinaryPath: String?
    private var ready: Bool = false

    private let repositoryDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Verbatim", isDirectory: true)
            .appendingPathComponent("whisper-server", isDirectory: true)
    }()

    private struct ReleaseAsset: Decodable { let name: String; let browser_download_url: String }
    private struct ReleaseResponse: Decodable { let assets: [ReleaseAsset] }

    func status() -> (running: Bool, port: Int?, modelPath: String?, binaryPath: String?, ready: Bool) {
        (running: process?.isRunning == true, port: currentPort, modelPath: currentModelPath, binaryPath: currentBinaryPath, ready: ready)
    }

    func stop() {
        if let process {
            process.terminate()
        }
        process = nil
        currentModelPath = nil
        currentPort = nil
        currentBinaryPath = nil
        ready = false
    }

    func ensureServerBinaryPath(overridePath: String?) async throws -> URL {
        if let rawOverride = overridePath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawOverride.isEmpty {
            let candidate = URL(fileURLWithPath: (rawOverride as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                throw WhisperServerManagerError.binaryNotFound
            }
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
                throw WhisperServerManagerError.binaryNotExecutable
            }
            return candidate
        }

        let cached = cachedBinaryPath()
        if FileManager.default.fileExists(atPath: cached.path) {
            guard FileManager.default.isExecutableFile(atPath: cached.path) else {
                throw WhisperServerManagerError.binaryNotExecutable
            }
            return cached
        }

        try await downloadAndCacheServerBinary()
        let downloaded = cachedBinaryPath()
        guard FileManager.default.fileExists(atPath: downloaded.path) else {
            throw WhisperServerManagerError.binaryNotFound
        }
        return downloaded
    }

    func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: cachedBinaryPath().path) &&
        FileManager.default.isExecutableFile(atPath: cachedBinaryPath().path)
    }

    func ensureServerRunning(modelPath: String, binaryPath: URL, config: ServerConfig = ServerConfig()) async throws -> URL {
        let normalizedModelPath = (modelPath as NSString).expandingTildeInPath
        if ready, process?.isRunning == true, currentModelPath == normalizedModelPath, let port = currentPort {
            return URL(string: "http://\(Constants.host):\(port)")!
        }

        if process != nil {
            stop()
        }

        if !FileManager.default.fileExists(atPath: normalizedModelPath) {
            throw WhisperServerManagerError.processExited("Model file not found: \(normalizedModelPath)")
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath.path) else {
            throw WhisperServerManagerError.binaryNotExecutable
        }

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        currentPort = try findAvailablePort()
        guard let port = currentPort else {
            throw WhisperServerManagerError.processExited("Unable to select a free whisper-server port")
        }

        let arguments = makeServerArguments(
            modelPath: normalizedModelPath,
            port: port,
            threads: config.threads,
            language: config.language
        )

        let process = Process()
        process.executableURL = binaryPath
        process.arguments = arguments
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        self.process = process
        self.currentModelPath = normalizedModelPath
        self.currentBinaryPath = binaryPath.path

        do {
            try process.run()
        } catch {
            stop()
            throw WhisperServerManagerError.processExited(error.localizedDescription)
        }

        do {
            try await waitForReady(port: port)
            ready = true
            return URL(string: "http://\(Constants.host):\(port)")!
        } catch {
            stop()
            throw error
        }
    }

    private func cachedBinaryPath() -> URL {
        let binaryName = cachedBinaryName()
        return repositoryDir.appendingPathComponent(binaryName, isDirectory: false)
    }

    private func cachedBinaryName() -> String {
        #if arch(arm64)
        return "whisper-server-darwin-arm64"
        #else
        return "whisper-server-darwin-x64"
        #endif
    }

    private func makeServerArguments(modelPath: String, port: Int, threads: Int, language: String) -> [String] {
        var args = ["--model", modelPath, "--host", Constants.host, "--port", String(port), "--language", language]
        if threads > 0 {
            args.append(contentsOf: ["--threads", String(threads)])
        }
        return args
    }

    private func findAvailablePort() throws -> Int {
        for port in Constants.portRangeStart...Constants.portRangeEnd {
            if isPortAvailable(port) {
                return port
            }
        }
        throw WhisperServerManagerError.processExited("No available local ports in \(Constants.portRangeStart)-\(Constants.portRangeEnd)")
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }

        var address = sockaddr_in(
            sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr(Constants.host)),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        let available = (bindResult == 0)
        close(socket)
        return available
    }

    private func waitForReady(port: Int) async throws {
        let deadline = Date().addingTimeInterval(Constants.startupTimeout)
        while Date() < deadline {
            if let process, !process.isRunning {
                throw WhisperServerManagerError.startupTimeout
            }

            do {
                if try await checkHealth(port: port) {
                    return
                }
            } catch {
                // ignore and keep polling
            }

            try await Task.sleep(nanoseconds: Constants.healthPollIntervalMS * 1_000_000)
        }
        throw WhisperServerManagerError.startupTimeout
    }

    private func checkHealth(port: Int) async throws -> Bool {
        let endpoint = URL(string: "http://\(Constants.host):\(port)/")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 1
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }

    private func downloadAndCacheServerBinary() async throws {
        try FileManager.default.createDirectory(at: repositoryDir, withIntermediateDirectories: true)

        var apiRequest = URLRequest(url: URL(string: "https://api.github.com/repos/OpenWhispr/whisper.cpp/releases/latest")!)
        apiRequest.httpMethod = "GET"
        apiRequest.setValue("VerbatimLocalWhisper", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: apiRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhisperServerManagerError.processExited("Failed to read whisper.cpp release metadata")
        }

        let release = try JSONDecoder().decode(ReleaseResponse.self, from: data)
        let wantedAsset = release.assets.first { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".zip") &&
                (lower == "\(cachedBinaryName()).zip" ||
                 (lower.contains("whisper-server") && lower.contains(cachedBinaryName())))
        }
        guard let assetURL = wantedAsset?.browser_download_url,
              let parsedAssetURL = URL(string: assetURL) else {
            throw WhisperServerManagerError.processExited("No matching whisper-server binary in release")
        }

        let zipRequest = URLRequest(url: parsedAssetURL)
        let (zipFileURL, zipResponse) = try await URLSession.shared.download(for: zipRequest)
        guard let zipHTTP = zipResponse as? HTTPURLResponse, (200..<300).contains(zipHTTP.statusCode) else {
            throw WhisperServerManagerError.processExited("Failed to download whisper-server binary archive")
        }

        defer {
            try? FileManager.default.removeItem(at: zipFileURL)
        }

        let unzipDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipFileURL.path, "-d", unzipDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        if unzip.terminationStatus != 0 {
            throw WhisperServerManagerError.processExited("Failed to extract whisper-server binary")
        }

        let extracted = unzipDir.appendingPathComponent(cachedBinaryName())
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw WhisperServerManagerError.processExited("No binary in downloaded archive")
        }

        if FileManager.default.fileExists(atPath: cachedBinaryPath().path) {
            try? FileManager.default.removeItem(at: cachedBinaryPath())
        }
        try FileManager.default.moveItem(at: extracted, to: cachedBinaryPath())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cachedBinaryPath().path)
    }
}
