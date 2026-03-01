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
    @Published var language: String = "en"

    @Published var autoInsertEnabled: Bool = true
    @Published var clipboardFallbackEnabled: Bool = true
    @Published var showCapturedToastEnabled: Bool = true
    @Published var insertionModePreferred: InsertionModePreferred = .accessibilityFirst

    @Published var historyRetentionDays: Int = 30
    @Published var autoSaveLongCapturesToNotes: Bool = false
    @Published var longCaptureThresholdWords: Int = 120

    let keyStore: OpenAIKeyStore
    private let settingsRepository: SettingsRepository

    private var settings: AppSettings!

    init(settingsRepository: SettingsRepository, keyStore: OpenAIKeyStore) {
        self.settingsRepository = settingsRepository
        self.keyStore = keyStore
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
}
