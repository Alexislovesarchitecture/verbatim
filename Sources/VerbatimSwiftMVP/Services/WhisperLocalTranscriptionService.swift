import AVFoundation
import Foundation
import whisper

enum LocalTranscriptionBackend: String, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisperKitSDK = "whisperkit_sdk"
    case whisperCpp = "whisper_cpp"

    var engineID: String {
        switch self {
        case .appleSpeech:
            return "apple-speech-ondevice"
        case .whisperKitSDK:
            return "whisperkit-sdk"
        case .whisperCpp:
            return "whisper-cpp-xcframework"
        }
    }
}

struct WhisperRuntimeStatus: Equatable, Sendable {
    let isSupported: Bool
    let message: String

    var isAvailable: Bool { isSupported }
}

enum WhisperModelInstallState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double?)
    case downloaded(stagedURL: URL)
    case installing
    case ready(installedURL: URL)
    case failed(message: String)

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .installing:
            return true
        case .notDownloaded, .downloaded, .ready, .failed:
            return false
        }
    }

    var lifecycleIdentifier: String {
        switch self {
        case .notDownloaded:
            return "not_downloaded"
        case .downloading:
            return "downloading"
        case .downloaded:
            return "downloaded"
        case .installing:
            return "installing"
        case .ready:
            return "ready"
        case .failed:
            return "failed"
        }
    }
}

struct WhisperDownloadManifestEntry: Equatable, Sendable {
    let model: LocalTranscriptionModel
    let backendModelName: String
    let fileName: String
    let downloadURL: URL
    let approximateSizeLabel: String
    let qualityNote: String
    let minimumValidBytes: Int64
}

enum WhisperAudioLoader {
    private static let targetSampleRate: Double = 16_000
    private static let targetChannelCount: AVAudioChannelCount = 1

    static func loadSamples(from url: URL) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: url)
        guard inputFile.length > 0 else {
            throw LocalTranscriptionError.invalidAudioFile(
                "Recorded audio file contained no audio samples. Try recording again."
            )
        }

        if inputFile.processingFormat.commonFormat == .pcmFormatFloat32,
           inputFile.processingFormat.channelCount == targetChannelCount,
           abs(inputFile.processingFormat.sampleRate - targetSampleRate) < 0.5,
           inputFile.processingFormat.isInterleaved == false {
            return try readSamplesDirectly(from: inputFile)
        }

        return try readAndConvertSamples(from: inputFile)
    }

    private static func readSamplesDirectly(from inputFile: AVAudioFile) throws -> [Float] {
        let frameCapacity = try wholeFileFrameCapacity(for: inputFile)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate input audio buffer.")
        }

        try inputFile.read(into: buffer)
        guard buffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }
        guard let channelData = buffer.floatChannelData?.pointee else {
            throw LocalTranscriptionError.invalidAudioFile("Could not read audio channel data.")
        }

        let frameLength = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }

    private static func readAndConvertSamples(from inputFile: AVAudioFile) throws -> [Float] {
        let inputFrameCapacity = try wholeFileFrameCapacity(for: inputFile)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not configure audio conversion.")
        }
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not create audio converter.")
        }
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: inputFrameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate input audio buffer.")
        }

        do {
            try inputFile.read(into: inputBuffer)
        } catch {
            throw LocalTranscriptionError.invalidAudioFile("Audio read failed: \(error.localizedDescription)")
        }

        guard inputBuffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }

        let convertedFrameEstimate = Int(
            ceil(Double(inputBuffer.frameLength) * targetSampleRate / inputFile.processingFormat.sampleRate)
        ) + 64
        let outputFrameCapacity = AVAudioFrameCount(
            max(Int(inputBuffer.frameLength), max(1, convertedFrameEstimate))
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw LocalTranscriptionError.invalidAudioFile("Could not allocate output audio buffer.")
        }

        var didConsumeInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didConsumeInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            didConsumeInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion failed: \(conversionError.localizedDescription)")
        }

        switch status {
        case .haveData, .endOfStream:
            break
        case .inputRanDry:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion ran dry before producing output.")
        case .error:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion failed.")
        @unknown default:
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion returned an unknown status.")
        }

        guard outputBuffer.frameLength > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Audio conversion produced no samples.")
        }
        guard let channelData = outputBuffer.floatChannelData?.pointee else {
            throw LocalTranscriptionError.invalidAudioFile("Could not read converted audio channel data.")
        }

        let frameLength = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }

    private static func wholeFileFrameCapacity(for inputFile: AVAudioFile) throws -> AVAudioFrameCount {
        guard inputFile.length > 0 else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file contained no audio samples. Try recording again.")
        }
        guard inputFile.length <= Int64(UInt32.max) else {
            throw LocalTranscriptionError.invalidAudioFile("Recorded audio file is too large for local Whisper.")
        }
        return AVAudioFrameCount(inputFile.length)
    }
}

actor WhisperModelManager {
    typealias DownloadHandler = @Sendable (URL) async throws -> URL
    typealias RuntimeStatusProvider = @Sendable () -> WhisperRuntimeStatus

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let manifest: [LocalTranscriptionModel: WhisperDownloadManifestEntry]
    private let downloadHandler: DownloadHandler
    private let runtimeStatusProvider: RuntimeStatusProvider
    private var installStates: [LocalTranscriptionModel: WhisperModelInstallState] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        manifest: [LocalTranscriptionModel: WhisperDownloadManifestEntry]? = nil,
        downloadHandler: DownloadHandler? = nil,
        runtimeStatusProvider: RuntimeStatusProvider? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = WhisperModelManager.makeRootDirectoryURL(
            fileManager: fileManager,
            baseDirectoryURL: baseDirectoryURL
        )
        self.manifest = manifest ?? Self.defaultManifest
        self.downloadHandler = downloadHandler ?? { url in
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            return tempURL
        }
        self.runtimeStatusProvider = runtimeStatusProvider ?? { Self.defaultRuntimeStatus() }
    }

    func runtimeStatus() -> WhisperRuntimeStatus {
        runtimeStatusProvider()
    }

    func manifestEntry(for model: LocalTranscriptionModel) -> WhisperDownloadManifestEntry? {
        manifest[model]
    }

    func refreshInstallStates() -> [LocalTranscriptionModel: WhisperModelInstallState] {
        for model in LocalTranscriptionModel.allCases where model.isWhisperModel {
            installStates[model] = resolvedInstallState(for: model)
        }
        return installStates
    }

    func installState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        let state = resolvedInstallState(for: model)
        installStates[model] = state
        return state
    }

    func refreshModelState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        installState(for: model)
    }

    func installedModelURL(for model: LocalTranscriptionModel) -> URL? {
        guard case .ready(let url) = installState(for: model) else {
            return nil
        }
        return url
    }

    func downloadModel(_ model: LocalTranscriptionModel) async -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) does not use a downloadable Whisper model.")
            installStates[model] = failedState
            return failedState
        }

        let runtime = runtimeStatus()
        guard runtime.isSupported else {
            let failedState = WhisperModelInstallState.failed(message: runtime.message)
            installStates[model] = failedState
            return failedState
        }

        installStates[model] = .downloading(progress: nil)

        do {
            try ensureDirectoriesExist()
            let temporaryURL = try await downloadHandler(entry.downloadURL)
            let destinationURL = stagedModelFileURL(for: model)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            try validateModelFile(at: destinationURL, entry: entry, locationDescription: "Downloaded model")
            let state = WhisperModelInstallState.downloaded(stagedURL: destinationURL)
            installStates[model] = state
            return state
        } catch {
            let failedState = WhisperModelInstallState.failed(message: "Download failed: \(error.localizedDescription)")
            installStates[model] = failedState
            return failedState
        }
    }

    func installModel(_ model: LocalTranscriptionModel) async -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) does not use a downloadable Whisper model.")
            installStates[model] = failedState
            return failedState
        }

        let runtime = runtimeStatus()
        guard runtime.isSupported else {
            let failedState = WhisperModelInstallState.failed(message: runtime.message)
            installStates[model] = failedState
            return failedState
        }

        let stagedURL = stagedModelFileURL(for: model)
        if !fileManager.fileExists(atPath: stagedURL.path) {
            let resolved = resolvedInstallState(for: model)
            installStates[model] = resolved
            if case .ready = resolved {
                return resolved
            }
            let failedState = WhisperModelInstallState.failed(message: "\(model.title) must be downloaded before it can be installed.")
            installStates[model] = failedState
            return failedState
        }

        installStates[model] = .installing

        do {
            try ensureDirectoriesExist()
            try validateModelFile(at: stagedURL, entry: entry, locationDescription: "Downloaded model")
            let destinationURL = installedModelFileURL(for: model)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
            try validateModelFile(at: destinationURL, entry: entry, locationDescription: "Installed model")
            let state = WhisperModelInstallState.ready(installedURL: destinationURL)
            installStates[model] = state
            return state
        } catch {
            let failedState = WhisperModelInstallState.failed(message: "Install failed: \(error.localizedDescription)")
            installStates[model] = failedState
            return failedState
        }
    }

    func removeModel(_ model: LocalTranscriptionModel) throws {
        let stagedURL = stagedModelFileURL(for: model)
        if fileManager.fileExists(atPath: stagedURL.path) {
            try fileManager.removeItem(at: stagedURL)
        }
        let installedURL = installedModelFileURL(for: model)
        if fileManager.fileExists(atPath: installedURL.path) {
            try fileManager.removeItem(at: installedURL)
        }
        installStates[model] = .notDownloaded
    }

    func modelsDirectoryURL() -> URL {
        installedModelsDirectoryURL
    }

    private func resolvedInstallState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        guard let entry = manifest[model] else {
            return .notDownloaded
        }

        let installedURL = installedModelFileURL(for: model)
        if fileManager.fileExists(atPath: installedURL.path) {
            do {
                try validateModelFile(at: installedURL, entry: entry, locationDescription: "Installed model")
                return .ready(installedURL: installedURL)
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }

        let stagedURL = stagedModelFileURL(for: model)
        if fileManager.fileExists(atPath: stagedURL.path) {
            do {
                try validateModelFile(at: stagedURL, entry: entry, locationDescription: "Downloaded model")
                return .downloaded(stagedURL: stagedURL)
            } catch {
                return .failed(message: error.localizedDescription)
            }
        }

        return .notDownloaded
    }

    private var stagedDownloadsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("downloads", isDirectory: true)
    }

    private var installedModelsDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("models", isDirectory: true)
    }

    private func stagedModelFileURL(for model: LocalTranscriptionModel) -> URL {
        let fileName = manifest[model]?.fileName ?? "ggml-\(model.whisperModelName ?? model.rawValue).bin"
        return stagedDownloadsDirectoryURL.appendingPathComponent(fileName)
    }

    private func installedModelFileURL(for model: LocalTranscriptionModel) -> URL {
        let fileName = manifest[model]?.fileName ?? "ggml-\(model.whisperModelName ?? model.rawValue).bin"
        return installedModelsDirectoryURL.appendingPathComponent(fileName)
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: stagedDownloadsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: installedModelsDirectoryURL, withIntermediateDirectories: true)
    }

    private func validateModelFile(
        at url: URL,
        entry: WhisperDownloadManifestEntry,
        locationDescription: String
    ) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("\(locationDescription) for \(entry.model.title) is missing or invalid.")
        }
        let fileSize = Int64(values.fileSize ?? 0)
        guard fileSize >= entry.minimumValidBytes else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("\(locationDescription) for \(entry.model.title) is incomplete. Retry the download.")
        }
    }

    private static func makeRootDirectoryURL(fileManager: FileManager, baseDirectoryURL: URL?) -> URL {
        if let baseDirectoryURL {
            return baseDirectoryURL.appendingPathComponent("Whisper", isDirectory: true)
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
    }

    private static func defaultRuntimeStatus() -> WhisperRuntimeStatus {
        #if arch(arm64)
        _ = String(cString: whisper_print_system_info())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperRuntimeStatus(
            isSupported: true,
            message: "Whisper runtime ready."
        )
        #else
        return WhisperRuntimeStatus(
            isSupported: false,
            message: "Local Whisper currently requires Apple Silicon."
        )
        #endif
    }

    private static let defaultManifest: [LocalTranscriptionModel: WhisperDownloadManifestEntry] = {
        func entry(
            _ model: LocalTranscriptionModel,
            backendModelName: String,
            approximateSizeLabel: String,
            qualityNote: String,
            minimumValidBytes: Int64
        ) -> WhisperDownloadManifestEntry {
            WhisperDownloadManifestEntry(
                model: model,
                backendModelName: backendModelName,
                fileName: "ggml-\(backendModelName).bin",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(backendModelName).bin")!,
                approximateSizeLabel: approximateSizeLabel,
                qualityNote: qualityNote,
                minimumValidBytes: minimumValidBytes
            )
        }

        return [
            .whisperTiny: entry(.whisperTiny, backendModelName: "tiny", approximateSizeLabel: "74 MB", qualityNote: "Fastest, lowest accuracy", minimumValidBytes: 60_000_000),
            .whisperBase: entry(.whisperBase, backendModelName: "base", approximateSizeLabel: "141 MB", qualityNote: "Recommended balance", minimumValidBytes: 120_000_000),
            .whisperSmall: entry(.whisperSmall, backendModelName: "small", approximateSizeLabel: "465 MB", qualityNote: "Better accuracy, slower", minimumValidBytes: 390_000_000),
            .whisperMedium: entry(.whisperMedium, backendModelName: "medium", approximateSizeLabel: "1.43 GB", qualityNote: "High accuracy, heavy", minimumValidBytes: 1_150_000_000),
            .whisperLargeV3: entry(.whisperLargeV3, backendModelName: "large-v3", approximateSizeLabel: "2.88 GB", qualityNote: "Best quality, largest download", minimumValidBytes: 2_300_000_000)
        ]
    }()
}

final class WhisperLocalTranscriptionService: LocalTranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = LocalTranscriptionBackend.whisperCpp.engineID
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: false,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: true,
        supportsPrompt: false
    )

    private let modelManager: WhisperModelManager

    init(modelManager: WhisperModelManager) {
        self.modelManager = modelManager
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let selectedModel = LocalTranscriptionModel(rawValue: options.modelID) ?? .whisperBase
        return try await transcribeLocally(audioFileURL: audioURL, model: selectedModel)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }
        guard model.isWhisperModel else {
            throw LocalTranscriptionError.unsupportedModel(model)
        }

        let runtime = await modelManager.runtimeStatus()
        guard runtime.isSupported else {
            throw LocalTranscriptionError.unsupportedHardware(runtime.message)
        }
        let modelState = await modelManager.installState(for: model)
        let modelURL: URL
        switch modelState {
        case .ready(let installedURL):
            modelURL = installedURL
        case .downloaded:
            throw LocalTranscriptionError.whisperModelNeedsInstall(model)
        case .notDownloaded:
            throw LocalTranscriptionError.whisperModelNotInstalled(model)
        case .downloading:
            throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still downloading.")
        case .installing:
            throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still installing.")
        case .failed(let message):
            throw LocalTranscriptionError.whisperRuntimeUnavailable(message)
        }

        let samples = try WhisperAudioLoader.loadSamples(from: audioFileURL)
        return try await Task.detached(priority: .userInitiated) {
            try Self.performTranscription(
                samples: samples,
                modelURL: modelURL,
                model: model
            )
        }.value
    }

    private static func performTranscription(
        samples: [Float],
        modelURL: URL,
        model: LocalTranscriptionModel
    ) throws -> Transcript {
        let gpuAttempt = Result {
            try performTranscriptionAttempt(samples: samples, modelURL: modelURL, model: model, useGPU: true)
        }
        switch gpuAttempt {
        case .success(let transcript):
            return transcript
        case .failure(let gpuError):
            let cpuAttempt = Result {
                try performTranscriptionAttempt(samples: samples, modelURL: modelURL, model: model, useGPU: false)
            }
            switch cpuAttempt {
            case .success(let transcript):
                return transcript
            case .failure(let cpuError):
                throw LocalTranscriptionError.whisperTranscriptionFailed(
                    "\(model.title) failed with GPU and CPU attempts. GPU: \(gpuError.localizedDescription) CPU: \(cpuError.localizedDescription)"
                )
            }
        }
    }

    private static func performTranscriptionAttempt(
        samples: [Float],
        modelURL: URL,
        model: LocalTranscriptionModel,
        useGPU: Bool
    ) throws -> Transcript {
        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = useGPU
        contextParams.flash_attn = false

        guard let ctx = whisper_init_from_file_with_params(modelURL.path, contextParams) else {
            let mode = useGPU ? "GPU" : "CPU"
            throw LocalTranscriptionError.whisperRuntimeUnavailable("Could not initialize the Whisper context using \(mode).")
        }
        defer { whisper_free(ctx) }

        var fullParams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        fullParams.n_threads = Int32(Self.defaultThreadCount)
        fullParams.translate = false
        fullParams.no_context = true
        fullParams.no_timestamps = false
        fullParams.print_special = false
        fullParams.print_progress = false
        fullParams.print_realtime = false
        fullParams.print_timestamps = false
        fullParams.token_timestamps = true
        fullParams.language = nil
        fullParams.detect_language = true

        let status = samples.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, fullParams, buffer.baseAddress, Int32(buffer.count))
        }
        guard status == 0 else {
            let mode = useGPU ? "GPU" : "CPU"
            throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) returned status \(status) using \(mode).")
        }

        let segmentCount = Int(whisper_full_n_segments(ctx))
        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(segmentCount)

        for index in 0..<segmentCount {
            guard let textPointer = whisper_full_get_segment_text(ctx, Int32(index)) else {
                continue
            }
            let text = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = Double(whisper_full_get_segment_t0(ctx, Int32(index))) / 100.0
            let end = Double(whisper_full_get_segment_t1(ctx, Int32(index))) / 100.0

            if !text.isEmpty {
                segments.append(
                    TranscriptSegment(
                        start: start,
                        end: end,
                        speaker: nil,
                        text: text
                    )
                )
            }
        }

        let rawText = segments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            throw LocalTranscriptionError.noTranscriptionResult
        }

        return Transcript(
            rawText: rawText,
            segments: segments,
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: model.rawValue,
            responseFormat: "text"
        )
    }

    private static var defaultThreadCount: Int {
        max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1))
    }
}

final class ManagedLocalTranscriptionService: LocalTranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = "local-managed-transcription"
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: false,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: true,
        supportsPrompt: false
    )

    private let appleService: AppleLocalTranscriptionService
    private let whisperKitService: WhisperKitLocalTranscriptionService
    private let whisperService: WhisperLocalTranscriptionService
    private let whisperCppModelManager: WhisperModelManager
    private let routeTracker: LocalTranscriptionRouteTracker

    init(
        appleService: AppleLocalTranscriptionService = AppleLocalTranscriptionService(),
        whisperKitService: WhisperKitLocalTranscriptionService,
        whisperService: WhisperLocalTranscriptionService,
        whisperCppModelManager: WhisperModelManager,
        routeTracker: LocalTranscriptionRouteTracker
    ) {
        self.appleService = appleService
        self.whisperKitService = whisperKitService
        self.whisperService = whisperService
        self.whisperCppModelManager = whisperCppModelManager
        self.routeTracker = routeTracker
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let model = LocalTranscriptionModel(rawValue: options.modelID) ?? .appleOnDevice
        return try await transcribeLocally(audioFileURL: audioURL, model: model)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        if model.isAppleModel {
            return try await appleService.transcribeLocally(audioFileURL: audioFileURL, model: model)
        }

        return try await transcribeWhisperLocally(
            audioFileURL: audioFileURL,
            model: model,
            options: TranscriptionOptions(
                modelID: model.rawValue,
                responseFormat: "text",
                localEngineMode: .whisperKit
            )
        )
    }

    func latestRouteResolution() async -> LocalTranscriptionRouteResolution? {
        await routeTracker.latest()
    }

    private func transcribeWhisperLocally(
        audioFileURL: URL,
        model: LocalTranscriptionModel,
        options: TranscriptionOptions
    ) async throws -> Transcript {
        let configuredMode = options.localEngineMode ?? (model.isAppleModel ? .appleSpeech : .whisperKit)

        switch configuredMode {
        case .appleSpeech:
            await routeTracker.record(
                LocalTranscriptionRouteResolution(
                    configuredMode: configuredMode,
                    resolvedBackend: .appleSpeech,
                    selectedModel: .appleOnDevice,
                    serverConnectionMode: nil,
                    lifecycleState: nil,
                    message: nil,
                    usedLegacyFallback: false
                )
            )
            return try await appleService.transcribeLocally(audioFileURL: audioFileURL, model: .appleOnDevice)

        case .whisperKit:
            return try await whisperKitService.transcribeBatch(audioURL: audioFileURL, options: options)

        case .legacyWhisper:
            let legacyState = await whisperCppModelManager.installState(for: model)
            await routeTracker.record(
                LocalTranscriptionRouteResolution(
                    configuredMode: configuredMode,
                    resolvedBackend: .whisperCpp,
                    selectedModel: model,
                    serverConnectionMode: nil,
                    lifecycleState: legacyState.lifecycleIdentifier,
                    message: nil,
                    usedLegacyFallback: false
                )
            )
            let legacyRuntime = await whisperCppModelManager.runtimeStatus()
            guard legacyRuntime.isSupported else {
                throw LocalTranscriptionError.unsupportedHardware(legacyRuntime.message)
            }

            switch legacyState {
            case .ready:
                return try await whisperService.transcribeLocally(audioFileURL: audioFileURL, model: model)
            case .failed(let message):
                throw LocalTranscriptionError.whisperTranscriptionFailed(message)
            case .downloaded:
                throw LocalTranscriptionError.whisperModelNeedsInstall(model)
            case .notDownloaded:
                throw LocalTranscriptionError.whisperModelNotInstalled(model)
            case .downloading:
                throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still downloading.")
            case .installing:
                throw LocalTranscriptionError.whisperTranscriptionFailed("\(model.title) is still installing.")
            }
        }
    }
}
