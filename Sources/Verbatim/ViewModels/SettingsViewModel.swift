import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var startSoundEnabled: Bool = true
    @Published var stopSoundEnabled: Bool = true
    @Published var doubleTapFnLockEnabled: Bool = true
    @Published var overlayMeterEnabled: Bool = true
    @Published var silenceThreshold: Float = 0.06

    @Published var provider: TranscriptionProvider = .openai
    @Published var openAIModel: OpenAITranscriptionModel = .gpt4oMiniTranscribe
    @Published var openAIKeyInput: String = ""
    @Published var whisperCppPath: String = ""
    @Published var whisperModelPath: String = ""
    @Published var whisperBackend: WhisperLocalBackend = .server
    @Published var whisperModelId: String = WhisperLocalModel.defaultId.rawValue
    @Published var whisperModelsDir: String = WhisperModelDirectory.defaultPath
    @Published var whisperServerAutoStart: Bool = true
    @Published var whisperLocalThreads: Int = 4
    @Published var language: String = "en"

    @Published var autoInsertEnabled: Bool = true
    @Published var clipboardFallbackEnabled: Bool = true
    @Published var showCapturedToastEnabled: Bool = true
    @Published var insertionModePreferred: InsertionModePreferred = .accessibilityFirst

    @Published var isDownloadingModel: Bool = false
    @Published var modelDownloadMessage: String = ""
    @Published var isDownloadingServerBinary: Bool = false
    @Published var serverBinaryMessage: String = ""

    @Published var historyRetentionDays: Int = 30
    @Published var autoSaveLongCapturesToNotes: Bool = false
    @Published var longCaptureThresholdWords: Int = 120

    let keyStore: OpenAIKeyStore
    private let whisperModelManager: WhisperModelManager
    private let whisperServerManager: WhisperServerManager
    private let settingsRepository: SettingsRepository

    private var settings: AppSettings!

    init(settingsRepository: SettingsRepository, keyStore: OpenAIKeyStore) {
        self.settingsRepository = settingsRepository
        self.keyStore = keyStore
        self.whisperModelManager = WhisperModelManager()
        self.whisperServerManager = WhisperServerManager()
        syncFromStored()
    }

    func syncFromStored() {
        settings = settingsRepository.settings()
        startSoundEnabled = settings.startSoundEnabled
        stopSoundEnabled = settings.stopSoundEnabled
        doubleTapFnLockEnabled = settings.doubleTapFnLockEnabled
        overlayMeterEnabled = settings.overlayMeterEnabled
        silenceThreshold = settings.silenceThreshold
        provider = settings.provider
        openAIModel = settings.openAIModel
        whisperCppPath = settings.whisperCppPath
        whisperModelPath = settings.whisperModelPath
        whisperBackend = settings.whisperBackend
        whisperModelId = settings.whisperModelId
        whisperModelsDir = settings.whisperModelsDir
        whisperServerAutoStart = settings.whisperServerAutoStart
        whisperLocalThreads = settings.whisperLocalThreads
        language = settings.language
        autoInsertEnabled = settings.autoInsertEnabled
        clipboardFallbackEnabled = settings.clipboardFallbackEnabled
        showCapturedToastEnabled = settings.showCapturedToastEnabled
        insertionModePreferred = settings.insertionModePreferred
        historyRetentionDays = settings.historyRetentionDays
        autoSaveLongCapturesToNotes = settings.autoSaveLongCapturesToNotes
        longCaptureThresholdWords = settings.longCaptureThresholdWords

        if let savedKey = (try? keyStore.load()), !savedKey.isEmpty {
            openAIKeyInput = ""
        }
    }

    func save(_ repository: SettingsRepository) {
        settings.startSoundEnabled = startSoundEnabled
        settings.stopSoundEnabled = stopSoundEnabled
        settings.doubleTapFnLockEnabled = doubleTapFnLockEnabled
        settings.overlayMeterEnabled = overlayMeterEnabled
        settings.silenceThreshold = silenceThreshold

        settings.provider = provider
        settings.openAIModel = openAIModel
        settings.whisperCppPath = whisperCppPath
        settings.whisperModelPath = whisperModelPath
        settings.whisperBackend = whisperBackend
        settings.whisperModelId = whisperModelManager.normalizeModelId(whisperModelId)
        settings.whisperModelsDir = whisperModelsDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? WhisperModelDirectory.defaultPath
            : whisperModelsDir
        settings.whisperServerAutoStart = whisperServerAutoStart
        settings.whisperLocalThreads = max(1, whisperLocalThreads)
        settings.language = language
        settings.autoInsertEnabled = autoInsertEnabled
        settings.clipboardFallbackEnabled = clipboardFallbackEnabled
        settings.showCapturedToastEnabled = showCapturedToastEnabled
        settings.insertionModePreferred = insertionModePreferred
        settings.historyRetentionDays = historyRetentionDays
        settings.autoSaveLongCapturesToNotes = autoSaveLongCapturesToNotes
        settings.longCaptureThresholdWords = longCaptureThresholdWords

        let trimmedKeyInput = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyInput.isEmpty {
            try? keyStore.save(trimmedKeyInput)
            settings.openAIKeyRef = "openai-api-key"
        }

        repository.save(settings: settings)
    }

    func clearOpenAIKey(repository: SettingsRepository) {
        try? keyStore.clear()
        settings.openAIKeyRef = ""
        repository.save(settings: settings)
    }

    func hasStoredOpenAIKey() -> Bool {
        if !settings.openAIKeyRef.isEmpty {
            return true
        }

        guard let storedKey = try? keyStore.load() else { return false }
        return !storedKey.isEmpty
    }

    func clearHistory(_ captureRepository: CaptureRepository) {
        captureRepository.deleteAll()
    }

    var availableWhisperModels: [WhisperModelDescriptor] {
        whisperModelManager.availableModels()
    }

    var selectedModelStatus: WhisperModelStatus {
        whisperModelManager.status(for: whisperModelId, modelsDirectory: whisperModelsDir)
    }

    var serverBinaryStatus: String {
        let normalizedOverride = whisperCppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedOverride.isEmpty {
            let overridePath = (normalizedOverride as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: overridePath) {
                return FileManager.default.isExecutableFile(atPath: overridePath)
                    ? "Using override executable at \(overridePath)"
                    : "Override exists but is not executable"
            }
            return "Override executable not found"
        }

        return whisperServerManager.isAvailable() ? "Downloaded in app support" : "Not downloaded"
    }

    func modelDisplayName(_ descriptor: WhisperModelDescriptor) -> String {
        let status = whisperModelManager.status(for: descriptor.id, modelsDirectory: whisperModelsDir)
        let sizeText = status.fileSizeBytes.flatMap(formatBytes) ?? "unknown"
        return "\(descriptor.title) — \(status.isDownloaded ? "Downloaded (\(sizeText))" : "Not downloaded")"
    }

    func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return "\(Int64(kb)) KB" }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    func downloadSelectedWhisperModel() {
        isDownloadingModel = true
        modelDownloadMessage = "Downloading model \(whisperModelId)..."

        Task {
            do {
                let selectedModel = whisperModelManager.normalizeModelId(whisperModelId)
                let destination = try await whisperModelManager.downloadModel(
                    selectedModel,
                    modelsDirectory: whisperModelsDir
                )
                modelDownloadMessage = "Downloaded: \(destination.lastPathComponent)"
                whisperModelId = selectedModel
            } catch {
                modelDownloadMessage = "Model download failed: \(error.localizedDescription)"
            }
            isDownloadingModel = false
        }
    }

    func downloadServerBinary() {
        isDownloadingServerBinary = true
        serverBinaryMessage = "Downloading whisper server binary..."

        Task {
            do {
                let endpoint = try await whisperServerManager.ensureServerBinaryPath(overridePath: nil)
                serverBinaryMessage = "Server binary ready: \(endpoint.lastPathComponent)"
                whisperCppPath = endpoint.path
            } catch {
                serverBinaryMessage = "Server download failed: \(error.localizedDescription)"
            }
            isDownloadingServerBinary = false
        }
    }
}
