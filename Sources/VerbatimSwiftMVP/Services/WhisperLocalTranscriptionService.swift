import AVFoundation
import Foundation
import whisper

enum LocalTranscriptionBackend: String, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisperCpp = "whisper_cpp"

    var engineID: String {
        switch self {
        case .appleSpeech:
            return "apple-speech-ondevice"
        case .whisperCpp:
            return "whisper-cpp-xcframework"
        }
    }
}

struct WhisperRuntimeStatus: Equatable, Sendable {
    let isSupported: Bool
    let systemInfo: String?
    let message: String

    var isAvailable: Bool { isSupported }
}

enum WhisperModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double?)
    case installed(fileURL: URL)
    case failed(message: String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }
}

struct WhisperDownloadManifestEntry: Equatable, Sendable {
    let model: LocalTranscriptionModel
    let backendModelName: String
    let fileName: String
    let downloadURL: URL
    let approximateSizeLabel: String
    let qualityNote: String
}

actor WhisperModelManager {
    typealias DownloadHandler = @Sendable (URL) async throws -> URL

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let downloadHandler: DownloadHandler
    private var installStates: [LocalTranscriptionModel: WhisperModelInstallState] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil,
        downloadHandler: DownloadHandler? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = WhisperModelManager.makeRootDirectoryURL(
            fileManager: fileManager,
            baseDirectoryURL: baseDirectoryURL
        )
        self.downloadHandler = downloadHandler ?? { url in
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            return tempURL
        }
    }

    func runtimeStatus() -> WhisperRuntimeStatus {
        #if arch(arm64)
        let info = String(cString: whisper_print_system_info())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperRuntimeStatus(
            isSupported: true,
            systemInfo: info.isEmpty ? nil : info,
            message: "Whisper runtime ready."
        )
        #else
        return WhisperRuntimeStatus(
            isSupported: false,
            systemInfo: nil,
            message: "Local Whisper currently requires Apple Silicon."
        )
        #endif
    }

    func manifestEntry(for model: LocalTranscriptionModel) -> WhisperDownloadManifestEntry? {
        Self.manifest[model]
    }

    func refreshInstallStates() -> [LocalTranscriptionModel: WhisperModelInstallState] {
        for model in LocalTranscriptionModel.allCases where model.backend == .whisperCpp {
            installStates[model] = resolvedInstallState(for: model)
        }
        return installStates
    }

    func installState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        let state = resolvedInstallState(for: model)
        installStates[model] = state
        return state
    }

    func installedModelURL(for model: LocalTranscriptionModel) -> URL? {
        guard case .installed(let url) = installState(for: model) else {
            return nil
        }
        return url
    }

    func downloadModel(_ model: LocalTranscriptionModel) async -> WhisperModelInstallState {
        guard let entry = Self.manifest[model] else {
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
            try ensureModelsDirectoryExists()
            let temporaryURL = try await downloadHandler(entry.downloadURL)
            let destinationURL = modelFileURL(for: model)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            let state = WhisperModelInstallState.installed(fileURL: destinationURL)
            installStates[model] = state
            return state
        } catch {
            let failedState = WhisperModelInstallState.failed(message: "Download failed: \(error.localizedDescription)")
            installStates[model] = failedState
            return failedState
        }
    }

    func removeModel(_ model: LocalTranscriptionModel) throws {
        let fileURL = modelFileURL(for: model)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        installStates[model] = .notInstalled
    }

    func modelsDirectoryURL() -> URL {
        rootDirectoryURL
    }

    private func resolvedInstallState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        guard Self.manifest[model] != nil else {
            return .notInstalled
        }

        let fileURL = modelFileURL(for: model)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .notInstalled
        }

        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                return .notInstalled
            }
        } catch {
            return .failed(message: "Model file validation failed: \(error.localizedDescription)")
        }

        return .installed(fileURL: fileURL)
    }

    private func modelFileURL(for model: LocalTranscriptionModel) -> URL {
        let fileName = Self.manifest[model]?.fileName ?? "ggml-\(model.whisperModelName ?? model.rawValue).bin"
        return rootDirectoryURL.appendingPathComponent(fileName)
    }

    private func ensureModelsDirectoryExists() throws {
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }

    private static func makeRootDirectoryURL(fileManager: FileManager, baseDirectoryURL: URL?) -> URL {
        if let baseDirectoryURL {
            return baseDirectoryURL
                .appendingPathComponent("Whisper", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
            .appendingPathComponent("Whisper", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    private static let manifest: [LocalTranscriptionModel: WhisperDownloadManifestEntry] = {
        func entry(
            _ model: LocalTranscriptionModel,
            backendModelName: String,
            approximateSizeLabel: String,
            qualityNote: String
        ) -> WhisperDownloadManifestEntry {
            WhisperDownloadManifestEntry(
                model: model,
                backendModelName: backendModelName,
                fileName: "ggml-\(backendModelName).bin",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(backendModelName).bin")!,
                approximateSizeLabel: approximateSizeLabel,
                qualityNote: qualityNote
            )
        }

        return [
            .whisperTiny: entry(.whisperTiny, backendModelName: "tiny", approximateSizeLabel: "74 MB", qualityNote: "Fastest, lowest accuracy"),
            .whisperBase: entry(.whisperBase, backendModelName: "base", approximateSizeLabel: "141 MB", qualityNote: "Recommended balance"),
            .whisperSmall: entry(.whisperSmall, backendModelName: "small", approximateSizeLabel: "465 MB", qualityNote: "Better accuracy, slower"),
            .whisperMedium: entry(.whisperMedium, backendModelName: "medium", approximateSizeLabel: "1.43 GB", qualityNote: "High accuracy, heavy"),
            .whisperLargeV3: entry(.whisperLargeV3, backendModelName: "large-v3", approximateSizeLabel: "2.88 GB", qualityNote: "Best quality, largest download")
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
        guard model.backend == .whisperCpp else {
            throw LocalTranscriptionError.unsupportedModel(model)
        }

        let runtime = await modelManager.runtimeStatus()
        guard runtime.isSupported else {
            throw LocalTranscriptionError.unsupportedHardware(runtime.message)
        }
        guard let modelURL = await modelManager.installedModelURL(for: model) else {
            throw LocalTranscriptionError.whisperModelNotInstalled(model)
        }

        let samples = try loadAudioSamples(from: audioFileURL)
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
        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true
        contextParams.flash_attn = false

        guard let ctx = whisper_init_from_file_with_params(modelURL.path, contextParams) else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("Could not initialize the Whisper context.")
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
            throw LocalTranscriptionError.whisperTranscriptionFailed("The Whisper runtime returned status \(status).")
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

    private func loadAudioSamples(from url: URL) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: url)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("Could not configure audio conversion.")
        }
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("Could not create audio converter.")
        }

        let inputFrameCapacity: AVAudioFrameCount = 4_096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputFrameCapacity) else {
            throw LocalTranscriptionError.whisperRuntimeUnavailable("Could not allocate output audio buffer.")
        }

        var samples: [Float] = []
        var readError: Error?

        while true {
            outputBuffer.frameLength = 0
            let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
                guard readError == nil else {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFile.processingFormat,
                    frameCapacity: inputFrameCapacity
                ) else {
                    readError = LocalTranscriptionError.whisperRuntimeUnavailable("Could not allocate input audio buffer.")
                    outStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    try inputFile.read(into: inputBuffer, frameCount: inputFrameCapacity)
                } catch {
                    readError = error
                    outStatus.pointee = .endOfStream
                    return nil
                }

                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let readError {
                throw LocalTranscriptionError.whisperRuntimeUnavailable("Audio read failed: \(readError.localizedDescription)")
            }

            switch status {
            case .haveData:
                if let channelData = outputBuffer.floatChannelData?.pointee {
                    let frameLength = Int(outputBuffer.frameLength)
                    samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameLength))
                }
            case .inputRanDry:
                continue
            case .endOfStream:
                return samples
            case .error:
                throw LocalTranscriptionError.whisperRuntimeUnavailable("Audio conversion failed.")
            @unknown default:
                throw LocalTranscriptionError.whisperRuntimeUnavailable("Audio conversion returned an unknown status.")
            }
        }
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
    private let whisperService: WhisperLocalTranscriptionService

    init(
        appleService: AppleLocalTranscriptionService = AppleLocalTranscriptionService(),
        whisperService: WhisperLocalTranscriptionService
    ) {
        self.appleService = appleService
        self.whisperService = whisperService
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let model = LocalTranscriptionModel(rawValue: options.modelID) ?? .appleOnDevice
        return try await transcribeLocally(audioFileURL: audioURL, model: model)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        switch model.backend {
        case .appleSpeech:
            return try await appleService.transcribeLocally(audioFileURL: audioFileURL, model: model)
        case .whisperCpp:
            return try await whisperService.transcribeLocally(audioFileURL: audioFileURL, model: model)
        }
    }
}
