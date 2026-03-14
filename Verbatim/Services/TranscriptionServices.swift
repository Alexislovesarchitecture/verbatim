@preconcurrency import AVFoundation
import CoreMedia
import Darwin
import Foundation
import OSLog
import Speech

enum VerbatimTranscriptionError: LocalizedError {
    case microphonePermissionDenied
    case recordingUnavailable
    case providerUnavailable(String)
    case missingModel(String)
    case invalidAudio(String)
    case noTranscription
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record."
        case .recordingUnavailable:
            return "Recording is unavailable."
        case .providerUnavailable(let message),
             .missingModel(let message),
             .invalidAudio(let message),
             .processFailed(let message):
            return message
        case .noTranscription:
            return "No speech was detected."
        }
    }
}

private struct InstalledModelMetadata: Codable, Equatable, Sendable {
    var source: InstalledAssetSource
    var installedAt: Date
}

final class RecordingManager: RecordingManagerProtocol, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var isRecording = false

    func startRecording() async throws {
        guard isRecording == false else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFile = file
        outputURL = url

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            do {
                try self?.audioFile?.write(from: buffer)
            } catch {
                transcriptionLogger.error("Audio write failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stopRecording() async throws -> URL {
        guard isRecording, let url = outputURL else {
            throw VerbatimTranscriptionError.recordingUnavailable
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        outputURL = nil
        isRecording = false
        return url
    }

    func cancel() {
        if isRecording {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        audioFile = nil
        outputURL = nil
        isRecording = false
    }
}

struct AudioNormalizationService: AudioNormalizationServiceProtocol {
    func normalizeAudioFile(at sourceURL: URL) async throws -> URL {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw VerbatimTranscriptionError.invalidAudio("Could not configure audio conversion.")
        }

        let inputFrameCapacity = AVAudioFrameCount(max(AVAudioFramePosition(1), inputFile.length))
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: inputFrameCapacity
        )!
        try inputFile.read(into: inputBuffer)

        let estimatedFrames = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * outputFormat.sampleRate / inputFile.processingFormat.sampleRate) + 256
        )
        let outputFrameCapacity = max(estimatedFrames, inputBuffer.frameLength)
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity)!

        var didRead = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if didRead {
                outStatus.pointee = .endOfStream
                return nil
            }
            didRead = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status == .haveData || status == .endOfStream else {
            throw VerbatimTranscriptionError.invalidAudio("Audio conversion produced no usable data.")
        }

        guard let channelData = outputBuffer.floatChannelData?.pointee else {
            throw VerbatimTranscriptionError.invalidAudio("Converted audio was unreadable.")
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-normalized-\(UUID().uuidString).wav")
        let wavFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let wavFile = try AVAudioFile(forWriting: outputURL, settings: wavFormat.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: wavFormat, frameCapacity: outputBuffer.frameLength)!
        pcmBuffer.frameLength = outputBuffer.frameLength
        let samples = pcmBuffer.int16ChannelData!.pointee
        for index in 0 ..< Int(outputBuffer.frameLength) {
            let sample = max(-1.0, min(1.0, channelData[index]))
            samples[index] = Int16((sample * Float(Int16.max)).rounded())
        }
        try wavFile.write(from: pcmBuffer)
        return outputURL
    }
}

actor WhisperModelManager {
    private let descriptors: [ModelDescriptor]
    private let paths: VerbatimPaths
    private let logStore: VerbatimLogStore

    init(descriptors: [ModelDescriptor], paths: VerbatimPaths, logStore: VerbatimLogStore) {
        self.descriptors = descriptors.filter { $0.provider == .whisper }
        self.paths = paths
        self.logStore = logStore
    }

    func statuses() -> [ModelStatus] {
        descriptors.map { descriptor in
            let url = installedURL(for: descriptor.id)
            return ModelStatus(
                descriptor: descriptor,
                state: FileManager.default.fileExists(atPath: url.path) ? .ready : .notInstalled,
                location: FileManager.default.fileExists(atPath: url.path) ? url : nil
            )
        }
    }

    func installedURL(for modelID: String) -> URL {
        let descriptor = descriptors.first(where: { $0.id == modelID })
        return paths.whisperModelsRoot.appendingPathComponent(descriptor?.fileName ?? modelID)
    }

    func installSource(for modelID: String) -> InstalledAssetSource? {
        guard let data = try? Data(contentsOf: metadataURL(for: modelID)),
              let metadata = try? JSONDecoder().decode(InstalledModelMetadata.self, from: data) else {
            return nil
        }
        return metadata.source
    }

    func importFromElectronCacheIfNeeded() async {
        let legacyRoot = paths.electronOpenWhisprCacheRoot.appendingPathComponent("whisper-models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyRoot.path) else { return }
        for descriptor in descriptors {
            let destination = installedURL(for: descriptor.id)
            guard FileManager.default.fileExists(atPath: destination.path) == false,
                  let fileName = descriptor.fileName else { continue }
            let source = legacyRoot.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.copyItem(at: source, to: destination)
                persistMetadata(for: descriptor.id, source: .importedFromOpenWhisprCache)
                downloadLogger.info("Imported Whisper model \(descriptor.id, privacy: .public) from OpenWhispr cache")
                logStore.append("Imported Whisper model \(descriptor.id) from OpenWhispr cache", category: .downloads)
            } else if FileManager.default.fileExists(atPath: destination.path),
                      installSource(for: descriptor.id) == nil {
                persistMetadata(for: descriptor.id, source: .importedFromOpenWhisprCache)
            }
        }
    }

    func download(modelID: String) async throws {
        guard let descriptor = descriptors.first(where: { $0.id == modelID }),
              let fileName = descriptor.fileName else {
            throw VerbatimTranscriptionError.missingModel("Unknown Whisper model.")
        }
        let destination = paths.whisperModelsRoot.appendingPathComponent(fileName)
        try await DownloadService.download(
            from: descriptor.downloadURL,
            to: destination,
            expectedSize: descriptor.expectedSizeBytes,
            logStore: logStore,
            label: "Whisper \(modelID)"
        )
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw VerbatimTranscriptionError.processFailed("Whisper model download did not produce a file on disk.")
        }
        persistMetadata(for: modelID, source: .downloadedByVerbatim)
    }

    func delete(modelID: String) throws {
        let url = installedURL(for: modelID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let metadataURL = metadataURL(for: modelID)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }

    private func metadataURL(for modelID: String) -> URL {
        paths.whisperModelsRoot.appendingPathComponent("\(modelID).verbatim-model.json")
    }

    private func persistMetadata(for modelID: String, source: InstalledAssetSource) {
        let metadata = InstalledModelMetadata(source: source, installedAt: .now)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(for: modelID), options: [.atomic])
    }
}

actor ParakeetModelManager {
    private let descriptors: [ModelDescriptor]
    private let paths: VerbatimPaths
    private let logStore: VerbatimLogStore

    init(descriptors: [ModelDescriptor], paths: VerbatimPaths, logStore: VerbatimLogStore) {
        self.descriptors = descriptors.filter { $0.provider == .parakeet }
        self.paths = paths
        self.logStore = logStore
    }

    func statuses() -> [ModelStatus] {
        descriptors.map { descriptor in
            let location = installedURL(for: descriptor.id)
            return ModelStatus(
                descriptor: descriptor,
                state: validateDirectory(location) ? .ready : .notInstalled,
                location: validateDirectory(location) ? location : nil
            )
        }
    }

    func installedURL(for modelID: String) -> URL {
        paths.parakeetModelsRoot.appendingPathComponent(modelID, isDirectory: true)
    }

    func installSource(for modelID: String) -> InstalledAssetSource? {
        guard let data = try? Data(contentsOf: metadataURL(for: modelID)),
              let metadata = try? JSONDecoder().decode(InstalledModelMetadata.self, from: data) else {
            return nil
        }
        return metadata.source
    }

    func importFromElectronCacheIfNeeded() async {
        let legacyRoot = paths.electronOpenWhisprCacheRoot.appendingPathComponent("parakeet-models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyRoot.path) else { return }
        for descriptor in descriptors {
            let source = legacyRoot.appendingPathComponent(descriptor.id, isDirectory: true)
            let destination = installedURL(for: descriptor.id)
            guard FileManager.default.fileExists(atPath: destination.path) == false,
                  validateDirectory(source) else { continue }
            try? FileManager.default.copyItem(at: source, to: destination)
            persistMetadata(for: descriptor.id, source: .importedFromOpenWhisprCache)
            downloadLogger.info("Imported Parakeet model \(descriptor.id, privacy: .public) from OpenWhispr cache")
            logStore.append("Imported Parakeet model \(descriptor.id) from OpenWhispr cache", category: .downloads)
        }
    }

    func download(modelID: String) async throws {
        guard let descriptor = descriptors.first(where: { $0.id == modelID }) else {
            throw VerbatimTranscriptionError.missingModel("Unknown Parakeet model.")
        }
        let archiveURL = paths.parakeetModelsRoot.appendingPathComponent("\(modelID).tar.bz2")
        let extractRoot = paths.parakeetModelsRoot.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
        let destination = installedURL(for: modelID)

        try await DownloadService.download(
            from: descriptor.downloadURL,
            to: archiveURL,
            expectedSize: descriptor.expectedSizeBytes,
            logStore: logStore,
            label: "Parakeet \(modelID)"
        )
        try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", extractRoot.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VerbatimTranscriptionError.processFailed("Parakeet archive extraction failed.")
        }

        let sourceDir = extractRoot.appendingPathComponent(descriptor.extractDirectory ?? "", isDirectory: true)
        let resolvedSource: URL
        if validateDirectory(sourceDir) {
            resolvedSource = sourceDir
        } else {
            let children = (try? FileManager.default.contentsOfDirectory(at: extractRoot, includingPropertiesForKeys: nil)) ?? []
            guard let firstValid = children.first(where: validateDirectory(_:)) else {
                throw VerbatimTranscriptionError.processFailed("Parakeet model archive did not contain the expected files.")
            }
            resolvedSource = firstValid
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: resolvedSource, to: destination)
        try? FileManager.default.removeItem(at: archiveURL)
        try? FileManager.default.removeItem(at: extractRoot)
        guard validateDirectory(destination) else {
            throw VerbatimTranscriptionError.processFailed("Parakeet model installation is incomplete.")
        }
        persistMetadata(for: modelID, source: .downloadedByVerbatim)
    }

    func delete(modelID: String) throws {
        let url = installedURL(for: modelID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let metadataURL = metadataURL(for: modelID)
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }

    private func validateDirectory(_ directory: URL) -> Bool {
        let required = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        return required.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    private func metadataURL(for modelID: String) -> URL {
        paths.parakeetModelsRoot.appendingPathComponent("\(modelID).verbatim-model.json")
    }

    private func persistMetadata(for modelID: String, source: InstalledAssetSource) {
        let metadata = InstalledModelMetadata(source: source, installedAt: .now)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL(for: modelID), options: [.atomic])
    }
}

enum DownloadService {
    static func download(
        from urlString: String,
        to destinationURL: URL,
        expectedSize: Int64?,
        logStore: VerbatimLogStore?,
        label: String
    ) async throws {
        guard let url = URL(string: urlString) else {
            throw VerbatimTranscriptionError.processFailed("Invalid download URL.")
        }
        downloadLogger.info("Starting download for \(label, privacy: .public) from \(urlString, privacy: .public)")
        logStore?.append("Starting download for \(label) from \(urlString)", category: .downloads)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = destinationURL.appendingPathExtension("tmp")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        let actual = response.expectedContentLength
        if let expectedSize, actual > 0, actual != expectedSize {
            transcriptionLogger.warning("Expected size mismatch for \(urlString, privacy: .public)")
        }
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.moveItem(at: downloadedURL, to: tempURL)
        if let expectedSize {
            let size = (try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size > 0, abs(size - expectedSize) > max(Int64(1024 * 512), expectedSize / 50) {
                downloadLogger.error("Downloaded file size mismatch for \(label, privacy: .public)")
                logStore?.append("Downloaded file size mismatch for \(label)", category: .downloads)
                throw VerbatimTranscriptionError.processFailed("Downloaded file size was unexpected.")
            }
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        downloadLogger.info("Completed download for \(label, privacy: .public)")
        logStore?.append("Completed download for \(label)", category: .downloads)
    }
}

actor WhisperRuntimeManager {
    private let paths: VerbatimPaths
    private let logStore: VerbatimLogStore
    private let binaryName = "whisper-server-darwin-arm64"
    private let runtimeLogFileName = "whisper-runtime.log"
    private var process: Process?
    private var outputCapture: ProcessOutputCapture?
    private var activeModelURL: URL?
    private var activePort: Int?
    private var state: RuntimeState = .stopped
    private var lastCheck: Date?
    private var lastError: String?

    init(paths: VerbatimPaths, logStore: VerbatimLogStore) {
        self.paths = paths
        self.logStore = logStore
    }

    func ensureRunning(modelURL: URL) async throws -> URL {
        if let activeModelURL, activeModelURL == modelURL, await isHealthy(), let activePort {
            state = .ready
            lastCheck = .now
            return URL(string: "http://127.0.0.1:\(activePort)")!
        }
        try await stop()
        let binaryURL = paths.runtimeRoot.appendingPathComponent(binaryName)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            let message = "whisper-server is missing from the runtime bundle."
            markFailed(message)
            throw VerbatimTranscriptionError.providerUnavailable(message)
        }

        let port = try availablePort(in: 8178 ... 8199)
        let process = Process()
        let outputCapture = ProcessOutputCapture(logStore: logStore, fileName: runtimeLogFileName, streamLabel: "whisper")
        outputCapture.start()
        process.executableURL = binaryURL
        process.currentDirectoryURL = paths.runtimeRoot
        process.environment = [
            "PATH": paths.runtimeRoot.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
        ]
        process.arguments = [
            "--model", modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)"
        ]
        process.standardOutput = outputCapture.stdout
        process.standardError = outputCapture.stderr
        let owner = self
        process.terminationHandler = { process in
            Task {
                await owner.handleTermination(status: process.terminationStatus)
            }
        }
        state = .starting
        lastCheck = .now
        lastError = nil
        runtimeLogger.info("Starting whisper runtime for model \(modelURL.lastPathComponent, privacy: .public) on port \(port)")
        logStore.append("Starting whisper runtime for model \(modelURL.lastPathComponent) on port \(port)", category: .runtime)
        try process.run()
        self.process = process
        self.outputCapture = outputCapture
        self.activeModelURL = modelURL
        self.activePort = port

        for _ in 0 ..< 40 {
            if await isHealthy() {
                state = .ready
                lastCheck = .now
                lastError = nil
                runtimeLogger.info("Whisper runtime is healthy on port \(port)")
                logStore.append("Whisper runtime is healthy on port \(port)", category: .runtime)
                return URL(string: "http://127.0.0.1:\(port)")!
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let message = "whisper-server did not start successfully."
        markFailed(message)
        try await stop(clearLastError: false)
        throw VerbatimTranscriptionError.providerUnavailable(message)
    }

    func snapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            binaryName: binaryName,
            binaryPresent: FileManager.default.fileExists(atPath: binaryURL.path),
            state: state,
            endpoint: activePort.map { "http://127.0.0.1:\($0)" },
            lastCheck: lastCheck,
            lastError: lastError,
            logFileName: runtimeLogFileName
        )
    }

    func restart(modelURL: URL?) async throws -> RuntimeHealthSnapshot {
        try await stop(clearLastError: false)
        guard let modelURL else {
            lastCheck = .now
            return snapshot()
        }
        _ = try await ensureRunning(modelURL: modelURL)
        return snapshot()
    }

    func stop(clearLastError: Bool = true) async throws {
        outputCapture?.stop()
        outputCapture = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        activeModelURL = nil
        activePort = nil
        state = .stopped
        lastCheck = .now
        if clearLastError {
            lastError = nil
        }
        runtimeLogger.info("Stopped whisper runtime")
        logStore.append("Stopped whisper runtime", category: .runtime)
    }

    private func isHealthy() async -> Bool {
        guard let activePort else { return false }
        let url = URL(string: "http://127.0.0.1:\(activePort)/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private var binaryURL: URL {
        paths.runtimeRoot.appendingPathComponent(binaryName)
    }

    private func handleTermination(status: Int32) {
        outputCapture?.stop()
        outputCapture = nil
        if process != nil {
            let message = "Whisper runtime exited with status \(status)."
            runtimeLogger.error("\(message, privacy: .public)")
            logStore.append(message, category: .runtime)
            process = nil
            activeModelURL = nil
            activePort = nil
            markFailed(message)
        }
    }

    private func markFailed(_ message: String) {
        state = .failed
        lastCheck = .now
        lastError = message
        runtimeLogger.error("\(message, privacy: .public)")
        logStore.append(message, category: .runtime)
    }

    private func availablePort(in range: ClosedRange<Int>) throws -> Int {
        for port in range {
            let handle = socket(AF_INET, SOCK_STREAM, 0)
            guard handle >= 0 else { continue }
            defer { close(handle) }

            var value: Int32 = 1
            setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
            if result == 0 {
                return port
            }
        }
        throw VerbatimTranscriptionError.providerUnavailable("No available port for whisper-server.")
    }
}

actor ParakeetRuntimeManager {
    private let paths: VerbatimPaths
    private let logStore: VerbatimLogStore
    private let binaryName = "sherpa-onnx-ws-darwin-arm64"
    private let runtimeLogFileName = "parakeet-runtime.log"
    private var process: Process?
    private var outputCapture: ProcessOutputCapture?
    private var activeModelID: String?
    private var activePort: Int?
    private var state: RuntimeState = .stopped
    private var lastCheck: Date?
    private var lastError: String?

    init(paths: VerbatimPaths, logStore: VerbatimLogStore) {
        self.paths = paths
        self.logStore = logStore
    }

    func ensureRunning(modelID: String, modelDirectory: URL) async throws -> URL {
        if activeModelID == modelID, let activePort,
           await isHealthy(url: URL(string: "ws://127.0.0.1:\(activePort)")!) {
            state = .ready
            lastCheck = .now
            return URL(string: "ws://127.0.0.1:\(activePort)")!
        }
        try await stop()

        let binaryURL = paths.runtimeRoot.appendingPathComponent(binaryName)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            let message = "sherpa-onnx runtime is missing from the bundle."
            markFailed(message)
            throw VerbatimTranscriptionError.providerUnavailable(message)
        }
        let port = try availablePort(in: 6006 ... 6029)
        let process = Process()
        let outputCapture = ProcessOutputCapture(logStore: logStore, fileName: runtimeLogFileName, streamLabel: "parakeet")
        outputCapture.start()
        process.executableURL = binaryURL
        process.currentDirectoryURL = paths.runtimeRoot
        process.environment = [
            "PATH": paths.runtimeRoot.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")
        ]
        process.arguments = [
            "--tokens=\(modelDirectory.appendingPathComponent("tokens.txt").path)",
            "--encoder=\(modelDirectory.appendingPathComponent("encoder.int8.onnx").path)",
            "--decoder=\(modelDirectory.appendingPathComponent("decoder.int8.onnx").path)",
            "--joiner=\(modelDirectory.appendingPathComponent("joiner.int8.onnx").path)",
            "--port=\(port)",
            "--num-threads=4"
        ]
        process.standardOutput = outputCapture.stdout
        process.standardError = outputCapture.stderr
        let owner = self
        process.terminationHandler = { process in
            Task {
                await owner.handleTermination(status: process.terminationStatus)
            }
        }
        state = .starting
        lastCheck = .now
        lastError = nil
        runtimeLogger.info("Starting Parakeet runtime for model \(modelID, privacy: .public) on port \(port)")
        logStore.append("Starting Parakeet runtime for model \(modelID) on port \(port)", category: .runtime)
        try process.run()
        self.process = process
        self.outputCapture = outputCapture
        self.activePort = port
        self.activeModelID = modelID

        let url = URL(string: "ws://127.0.0.1:\(port)")!
        for _ in 0 ..< 40 {
            if await isHealthy(url: url) {
                state = .ready
                lastCheck = .now
                lastError = nil
                runtimeLogger.info("Parakeet runtime is healthy on port \(port)")
                logStore.append("Parakeet runtime is healthy on port \(port)", category: .runtime)
                return url
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let message = "Parakeet runtime did not start successfully."
        markFailed(message)
        try await stop(clearLastError: false)
        throw VerbatimTranscriptionError.providerUnavailable(message)
    }

    func snapshot() -> RuntimeHealthSnapshot {
        RuntimeHealthSnapshot(
            binaryName: binaryName,
            binaryPresent: FileManager.default.fileExists(atPath: binaryURL.path),
            state: state,
            endpoint: activePort.map { "ws://127.0.0.1:\($0)" },
            lastCheck: lastCheck,
            lastError: lastError,
            logFileName: runtimeLogFileName
        )
    }

    func restart(modelID: String?, modelDirectory: URL?) async throws -> RuntimeHealthSnapshot {
        try await stop(clearLastError: false)
        guard let modelID, let modelDirectory else {
            lastCheck = .now
            return snapshot()
        }
        _ = try await ensureRunning(modelID: modelID, modelDirectory: modelDirectory)
        return snapshot()
    }

    func stop(clearLastError: Bool = true) async throws {
        outputCapture?.stop()
        outputCapture = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        activePort = nil
        activeModelID = nil
        state = .stopped
        lastCheck = .now
        if clearLastError {
            lastError = nil
        }
        runtimeLogger.info("Stopped Parakeet runtime")
        logStore.append("Stopped Parakeet runtime", category: .runtime)
    }

    private var binaryURL: URL {
        paths.runtimeRoot.appendingPathComponent(binaryName)
    }

    private func isHealthy(url: URL) async -> Bool {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        return await withCheckedContinuation { continuation in
            task.sendPing { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func handleTermination(status: Int32) {
        outputCapture?.stop()
        outputCapture = nil
        if process != nil {
            let message = "Parakeet runtime exited with status \(status)."
            runtimeLogger.error("\(message, privacy: .public)")
            logStore.append(message, category: .runtime)
            process = nil
            activeModelID = nil
            activePort = nil
            markFailed(message)
        }
    }

    private func markFailed(_ message: String) {
        state = .failed
        lastCheck = .now
        lastError = message
        runtimeLogger.error("\(message, privacy: .public)")
        logStore.append(message, category: .runtime)
    }

    private func availablePort(in range: ClosedRange<Int>) throws -> Int {
        for port in range {
            let handle = socket(AF_INET, SOCK_STREAM, 0)
            guard handle >= 0 else { continue }
            defer { close(handle) }

            var value: Int32 = 1
            setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
            if result == 0 {
                return port
            }
        }
        throw VerbatimTranscriptionError.providerUnavailable("No available port for Parakeet runtime.")
    }
}

actor AppleSpeechProvider: TranscriptionProvider, LocaleAssetProvider {
    let id: ProviderID = .appleSpeech

    func availability() async -> ProviderAvailability {
        ProviderAvailability(
            isAvailable: SpeechTranscriber.isAvailable,
            reason: SpeechTranscriber.isAvailable ? nil : "Apple Speech is unavailable on this Mac."
        )
    }

    func readiness(for language: LanguageSelection) async -> ProviderReadiness {
        guard SpeechTranscriber.isAvailable else {
            return ProviderReadiness(kind: .unavailable, message: "Apple Speech is unavailable on this Mac.", actionTitle: nil)
        }
        guard language.isAuto == false else {
            return ProviderReadiness(kind: .missingLanguage, message: "Apple Speech requires an explicit language.", actionTitle: nil)
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.identifier)) else {
            return ProviderReadiness(kind: .unavailable, message: "Apple Speech does not support \(language.identifier).", actionTitle: nil)
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [module])
        switch status {
        case .installed:
            return .ready
        case .supported:
            return ProviderReadiness(kind: .missingAsset, message: "Apple Speech assets for \(language.title) are not installed.", actionTitle: "Install")
        case .downloading:
            return ProviderReadiness(kind: .installing, message: "Apple Speech assets are installing.", actionTitle: nil)
        case .unsupported:
            return ProviderReadiness(kind: .unavailable, message: "Apple Speech assets are unavailable for \(language.title).", actionTitle: nil)
        @unknown default:
            return ProviderReadiness(kind: .unavailable, message: "Apple Speech returned an unknown asset state.", actionTitle: nil)
        }
    }

    func transcribe(
        audioFileURL: URL,
        language: LanguageSelection,
        dictionaryHints: [DictionaryEntry]
    ) async throws -> TranscriptionResult {
        _ = dictionaryHints
        guard language.isAuto == false else {
            throw VerbatimTranscriptionError.providerUnavailable("Apple Speech requires an explicit language.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.identifier)) else {
            throw VerbatimTranscriptionError.providerUnavailable("Apple Speech does not support \(language.identifier).")
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw VerbatimTranscriptionError.providerUnavailable("Apple Speech language assets are not installed.")
        }

        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        async let textTask = collectAppleSpeechText(from: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            if let finalTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: finalTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let text = try await textTask
        guard text.isEmpty == false else {
            throw VerbatimTranscriptionError.noTranscription
        }
        return TranscriptionResult(originalText: text, finalText: text, provider: .appleSpeech, language: language)
    }

    func installedLanguages() async -> [LanguageSelection] {
        guard SpeechTranscriber.isAvailable else { return [] }
        return await SpeechTranscriber.installedLocales
            .map { LanguageSelection(identifier: $0.identifier) }
            .sorted { $0.identifier < $1.identifier }
    }

    func installAssets(for language: LanguageSelection) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.identifier)) else {
            throw VerbatimTranscriptionError.providerUnavailable("Unsupported Apple Speech locale.")
        }
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else { return }
        try await request.downloadAndInstall()
    }
}

private func collectAppleSpeechText(from transcriber: SpeechTranscriber) async throws -> String {
    var finalSegments: [(start: Double, text: String)] = []
    var latestVolatile = ""

    for try await result in transcriber.results {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { continue }

        if result.isFinal {
            let startSeconds = CMTimeGetSeconds(result.range.start)
            finalSegments.append((start: startSeconds.isFinite ? startSeconds : Double(finalSegments.count), text: text))
        } else {
            latestVolatile = text
        }
    }

    let finalText = finalSegments
        .sorted { $0.start < $1.start }
        .map(\.text)
        .joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if finalText.isEmpty == false {
        return finalText
    }

    return latestVolatile
}

actor WhisperProvider: TranscriptionProvider {
    let id: ProviderID = .whisper

    private let settingsStore: SettingsStoreProtocol
    private let modelManager: WhisperModelManager
    private let runtimeManager: WhisperRuntimeManager

    init(
        settingsStore: SettingsStoreProtocol,
        modelManager: WhisperModelManager,
        runtimeManager: WhisperRuntimeManager
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.runtimeManager = runtimeManager
    }

    func availability() async -> ProviderAvailability {
        let snapshot = await runtimeManager.snapshot()
        return ProviderAvailability(
            isAvailable: snapshot.binaryPresent,
            reason: snapshot.binaryPresent ? nil : "whisper-server is not staged in Verbatim Runtime."
        )
    }

    func readiness(for language: LanguageSelection) async -> ProviderReadiness {
        let settings = settingsStore.settings
        let statuses = await modelManager.statuses()
        guard let status = statuses.first(where: { $0.id == settings.selectedWhisperModelID }),
              status.state == .ready else {
            return ProviderReadiness(kind: .missingModel, message: "Download the selected Whisper model first.", actionTitle: "Download")
        }
        let snapshot = await runtimeManager.snapshot()
        guard snapshot.binaryPresent else {
            return ProviderReadiness(kind: .binaryMissing, message: "whisper-server is missing from the runtime bundle.", actionTitle: nil)
        }
        _ = status
        _ = language
        return .ready
    }

    func transcribe(
        audioFileURL: URL,
        language: LanguageSelection,
        dictionaryHints: [DictionaryEntry]
    ) async throws -> TranscriptionResult {
        let settings = settingsStore.settings
        let modelURL = await modelManager.installedURL(for: settings.selectedWhisperModelID)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw VerbatimTranscriptionError.missingModel("The selected Whisper model is not installed.")
        }
        transcriptionLogger.info("Starting Whisper transcription with model \(settings.selectedWhisperModelID, privacy: .public)")
        let baseURL = try await runtimeManager.ensureRunning(modelURL: modelURL)
        let text = try await WhisperHTTPClient.transcribe(
            baseURL: baseURL,
            audioFileURL: audioFileURL,
            language: language,
            prompt: dictionaryHints.map(\.phrase).joined(separator: ", ")
        )
        transcriptionLogger.info("Completed Whisper transcription with model \(settings.selectedWhisperModelID, privacy: .public)")
        return TranscriptionResult(originalText: text, finalText: text, provider: .whisper, language: language)
    }
}

actor ParakeetProvider: TranscriptionProvider {
    let id: ProviderID = .parakeet

    private let settingsStore: SettingsStoreProtocol
    private let modelManager: ParakeetModelManager
    private let runtimeManager: ParakeetRuntimeManager

    init(
        settingsStore: SettingsStoreProtocol,
        modelManager: ParakeetModelManager,
        runtimeManager: ParakeetRuntimeManager
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.runtimeManager = runtimeManager
    }

    func availability() async -> ProviderAvailability {
        let snapshot = await runtimeManager.snapshot()
        return ProviderAvailability(
            isAvailable: snapshot.binaryPresent,
            reason: snapshot.binaryPresent ? nil : "sherpa-onnx runtime is not staged in Verbatim Runtime."
        )
    }

    func readiness(for language: LanguageSelection) async -> ProviderReadiness {
        let settings = settingsStore.settings
        let statuses = await modelManager.statuses()
        guard let model = statuses.first(where: { $0.descriptor.id == settings.selectedParakeetModelID }),
              model.state == .ready,
              let _ = model.location else {
            return ProviderReadiness(kind: .missingModel, message: "Download the selected Parakeet model first.", actionTitle: "Download")
        }
        let snapshot = await runtimeManager.snapshot()
        guard snapshot.binaryPresent else {
            return ProviderReadiness(kind: .binaryMissing, message: "sherpa-onnx runtime is missing from the runtime bundle.", actionTitle: nil)
        }
        if language.isAuto == false {
            if model.descriptor.supportedLanguageIDs.isEmpty == false,
               model.descriptor.supportedLanguageIDs.contains(language.identifier.split(separator: "-").first.map(String.init) ?? language.identifier) == false {
                return ProviderReadiness(kind: .unavailable, message: "The selected Parakeet model does not support \(language.title).", actionTitle: nil)
            }
        }
        return .ready
    }

    func transcribe(
        audioFileURL: URL,
        language: LanguageSelection,
        dictionaryHints: [DictionaryEntry]
    ) async throws -> TranscriptionResult {
        _ = dictionaryHints
        let settings = settingsStore.settings
        let modelID = settings.selectedParakeetModelID
        let modelURL = await modelManager.installedURL(for: modelID)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw VerbatimTranscriptionError.missingModel("The selected Parakeet model is not installed.")
        }
        transcriptionLogger.info("Starting Parakeet transcription with model \(modelID, privacy: .public)")
        let websocketURL = try await runtimeManager.ensureRunning(modelID: modelID, modelDirectory: modelURL)
        let text = try await ParakeetWebSocketClient.transcribe(websocketURL: websocketURL, wavURL: audioFileURL)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw VerbatimTranscriptionError.noTranscription
        }
        transcriptionLogger.info("Completed Parakeet transcription with model \(modelID, privacy: .public)")
        return TranscriptionResult(originalText: text, finalText: text, provider: .parakeet, language: language)
    }
}

enum WhisperHTTPClient {
    static func transcribe(baseURL: URL, audioFileURL: URL, language: LanguageSelection, prompt: String) async throws -> String {
        let boundary = "----Verbatim\(UUID().uuidString)"
        var body = Data()
        let audioData = try Data(contentsOf: audioFileURL)

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        if language.isAuto == false {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language.identifier)\r\n")
        }

        if prompt.isEmpty == false {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }

        append("--\(boundary)--\r\n")

        let url = baseURL.appendingPathComponent("inference")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = json["text"] as? String {
                return normalize(text)
            }
            if let segments = json["transcription"] as? [[String: Any]] {
                let text = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
                return normalize(text)
            }
        }
        let fallback = String(data: data, encoding: .utf8) ?? ""
        let normalized = normalize(fallback)
        guard normalized.isEmpty == false else {
            throw VerbatimTranscriptionError.noTranscription
        }
        return normalized
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ParakeetWebSocketClient {
    static func transcribe(websocketURL: URL, wavURL: URL) async throws -> String {
        let message = try buildMessage(from: wavURL)
        let task = URLSession.shared.webSocketTask(with: websocketURL)
        task.resume()
        try await task.send(.data(message))
        let firstMessage = try await task.receive()
        try await task.send(.string("Done"))
        task.cancel(with: .normalClosure, reason: nil)

        switch firstMessage {
        case .string(let text):
            return normalize(text)
        case .data(let data):
            return normalize(String(decoding: data, as: UTF8.self))
        @unknown default:
            return ""
        }
    }

    private static func buildMessage(from wavURL: URL) throws -> Data {
        let file = try AVAudioFile(forReading: wavURL)
        let frameCapacity = AVAudioFrameCount(max(AVAudioFramePosition(1), file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity) else {
            throw VerbatimTranscriptionError.invalidAudio("Could not allocate Parakeet audio buffer.")
        }
        try file.read(into: buffer)
        let samples = try extractSamples(from: buffer)
        let sampleCount = samples.count
        var payload = Data()
        var sampleRate = Int32(file.processingFormat.sampleRate.rounded()).littleEndian
        var byteCount = Int32(sampleCount * MemoryLayout<Float>.size).littleEndian
        withUnsafeBytes(of: &sampleRate) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &byteCount) { payload.append(contentsOf: $0) }
        samples.withUnsafeBufferPointer { bufferPointer in
            payload.append(Data(buffer: bufferPointer))
        }
        return payload
    }

    private static func extractSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let sampleCount = Int(buffer.frameLength)
        guard sampleCount > 0 else { return [] }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData?.pointee {
                return Array(UnsafeBufferPointer(start: channelData, count: sampleCount))
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData?.pointee {
                return UnsafeBufferPointer(start: channelData, count: sampleCount).map {
                    Float($0) / Float(Int16.max)
                }
            }
        case .pcmFormatInt32:
            if let channelData = buffer.int32ChannelData?.pointee {
                return UnsafeBufferPointer(start: channelData, count: sampleCount).map {
                    Float($0) / Float(Int32.max)
                }
            }
        default:
            break
        }

        guard let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: buffer.format, to: floatFormat),
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: buffer.frameCapacity) else {
            throw VerbatimTranscriptionError.invalidAudio("Could not convert audio for Parakeet.")
        }

        var didRead = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if didRead {
                outStatus.pointee = .endOfStream
                return nil
            }
            didRead = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard (status == .haveData || status == .endOfStream),
              let channelData = outputBuffer.floatChannelData?.pointee else {
            throw VerbatimTranscriptionError.invalidAudio("Could not read converted audio for Parakeet.")
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CoordinatorOutcome: Equatable {
    var result: TranscriptionResult
    var pasteResult: PasteResult
    var pasteDiagnostic: PasteInsertionDiagnostic
    var historyItem: HistoryItem
    var styleEvent: StyleDecisionReport
}

@MainActor
final class TranscriptionCoordinator {
    private let recordingManager: RecordingManagerProtocol
    private let normalizer: AudioNormalizationServiceProtocol
    private let pasteService: PasteServiceProtocol
    private let sharedCoreBridge: SharedCoreBridgeProtocol
    private let historyStore: HistoryStoreProtocol
    private let settingsStore: SettingsStoreProtocol
    private let logStore: VerbatimLogStore
    private var providers: [ProviderID: any TranscriptionProvider]
    private var currentTarget: PasteTarget?
    private var currentContext: ActiveAppContext?
    private var currentStyleDecision: StyleDecisionReport?

    init(
        recordingManager: RecordingManagerProtocol,
        normalizer: AudioNormalizationServiceProtocol,
        pasteService: PasteServiceProtocol,
        sharedCoreBridge: SharedCoreBridgeProtocol,
        historyStore: HistoryStoreProtocol,
        settingsStore: SettingsStoreProtocol,
        providers: [ProviderID: any TranscriptionProvider],
        logStore: VerbatimLogStore? = nil
    ) {
        self.recordingManager = recordingManager
        self.normalizer = normalizer
        self.pasteService = pasteService
        self.sharedCoreBridge = sharedCoreBridge
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.logStore = logStore ?? VerbatimLogStore(paths: VerbatimPaths())
        self.providers = providers
    }

    func startRecording(provider providerID: ProviderID, activeContext: ActiveAppContext?, styleDecision: StyleDecisionReport?) async throws {
        currentTarget = pasteService.captureTarget()
        currentContext = activeContext
        currentStyleDecision = styleDecision
        transcriptionLogger.info("Starting recording for provider \(providerID.rawValue, privacy: .public)")
        logStore.append("Starting recording for provider \(providerID.rawValue)", category: .transcription)
        try await recordingManager.startRecording()
    }

    func stopRecordingAndTranscribe(
        provider providerID: ProviderID,
        language: LanguageSelection,
        dictionaryEntries: [DictionaryEntry],
        accessibilityGranted: Bool
    ) async throws -> CoordinatorOutcome {
        let settings = settingsStore.settings
        let rawAudioURL = try await recordingManager.stopRecording()
        let normalizedURL = try await normalizer.normalizeAudioFile(at: rawAudioURL)
        guard let provider = providers[providerID] else {
            throw VerbatimTranscriptionError.providerUnavailable("No provider is configured.")
        }

        do {
            transcriptionLogger.info("Transcription request started for provider \(providerID.rawValue, privacy: .public)")
            logStore.append("Transcription request started for provider \(providerID.rawValue)", category: .transcription)
            let result = try await provider.transcribe(
                audioFileURL: normalizedURL,
                language: language,
                dictionaryHints: dictionaryEntries
            )
            let processed = sharedCoreBridge.processTranscript(
                text: result.finalText,
                context: currentContext,
                settings: settings.styleSettings,
                resolvedDecision: currentStyleDecision
            )
            let pasteOperation = pasteService.paste(
                text: processed.finalText,
                to: currentTarget,
                pasteMode: settings.pasteMode,
                accessibilityGranted: accessibilityGranted
            )
            let historyItem = historyStore.save(
                provider: result.provider,
                language: result.language,
                originalText: result.originalText,
                finalText: processed.finalText,
                error: pasteOperation.result == .pasted ? nil : pasteOperation.result.message
            )
            transcriptionLogger.info("Transcription request finished for provider \(result.provider.rawValue, privacy: .public)")
            logStore.append("Transcription request finished for provider \(result.provider.rawValue)", category: .transcription)
            currentTarget = nil
            currentContext = nil
            currentStyleDecision = nil
            return CoordinatorOutcome(
                result: result,
                pasteResult: pasteOperation.result,
                pasteDiagnostic: pasteOperation.diagnostic,
                historyItem: historyItem,
                styleEvent: processed.decision
            )
        } catch {
            transcriptionLogger.error("Transcription request failed for provider \(providerID.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            logStore.append("Transcription request failed for provider \(providerID.rawValue): \(error.localizedDescription)", category: .transcription)
            let historyItem = historyStore.save(
                provider: providerID,
                language: language,
                originalText: "",
                finalText: "",
                error: error.localizedDescription
            )
            currentTarget = nil
            currentContext = nil
            currentStyleDecision = nil
            throw NSError(domain: "VerbatimCoordinator", code: Int(historyItem.id), userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }
}
