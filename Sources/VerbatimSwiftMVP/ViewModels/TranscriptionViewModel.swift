@preconcurrency import AVFoundation
import Foundation
import Speech
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum RecorderState: Equatable {
    case idle
    case recording
    case transcribing
    case formatting
    case done
    case error(String)
}

enum RemoteModelsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

enum LocalLogicRuntimeLoadState: Equatable {
    case idle
    case checking
    case ready
    case error(String)
}

enum WhisperRuntimeLoadState: Equatable {
    case idle
    case checking
    case ready
    case error(String)
}

enum WhisperKitServerLoadState: Equatable {
    case idle
    case checking
    case ready
    case error(String)
}

enum LocalWhisperInstallStateDescription: Equatable {
    case none
    case progress(String)
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .auto:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum HotkeyStatusState: Equatable {
    case inactive
    case active(bindingTitle: String, message: String)
    case fallback(original: String, effective: String, message: String)
    case failed(message: String)
}

struct HotkeyRuntimeLog: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let selectedBindingTitle: String
    let effectiveBindingTitle: String
    let backend: HotkeyBackend
    let fallbackWasUsed: Bool
    let permissionGranted: Bool
    let event: GlobalHotkeyEvent?
}

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var transcript: Transcript? = nil
    @Published private(set) var formattedOutput: FormattedOutput? = nil
    @Published private(set) var deterministicResult: DeterministicResult? = nil
    @Published private(set) var latestLLMResult: LLMResult? = nil
    @Published private(set) var promptProfiles: [PromptProfile] = []
    @Published private(set) var transcriptHistory: [TranscriptRecord] = []
    @Published private(set) var dictionaryEntries: [GlossaryEntry] = []
    @Published var selectedTranscriptViewMode: TranscriptViewMode = .raw
    @Published var apiKey: String = ""
    @Published var refineSettings: RefineSettings = RefineSettings() {
        didSet {
            persistRefineSettings()
        }
    }
    @Published var interactionSettings: InteractionSettings = InteractionSettings() {
        didSet {
            persistInteractionSettings()
            if !isCapturingHotkey {
                configureHotkeyMonitoring()
            }
        }
    }
    @Published var pendingActionItemsJSON: String?
    @Published var pendingActionItemsRenderedText: String?
    @Published private(set) var hotkeyPermissionGranted: Bool = true
    @Published private(set) var hotkeyStatusMessage: String = "Hotkey monitoring is off."
    @Published private(set) var hotkeyStatusState: HotkeyStatusState = .inactive
    @Published private(set) var isCapturingHotkey: Bool = false
    @Published private(set) var effectiveHotkeyBindingTitle: String = HotkeyBinding.defaultFunctionKey.displayTitle
    @Published private(set) var recommendedHotkeyFallbackTitle: String?
    @Published private(set) var hotkeyRuntimeLogs: [HotkeyRuntimeLog] = []
    @Published private(set) var hotkeyTestMessage: String?
    @Published private(set) var diagnosticSessions: [DiagnosticSessionRecord] = []
    @Published private(set) var diagnosticSessionSummary: DiagnosticSessionSummary = .empty
    @Published var diagnosticsSessionLimit: DiagnosticsSessionLimit = .last20 {
        didSet {
            reloadDiagnosticSessions(limit: diagnosticsSessionLimit.rawValue)
        }
    }

    @Published var selectedSection: AppSection = .home {
        didSet {
            UserDefaults.standard.set(selectedSection.rawValue, forKey: Self.savedSectionDefaultsKey)
        }
    }

    @Published var transcriptionMode: TranscriptionMode = .local {
        didSet {
            if transcriptionMode != .local {
                transcriptionMode = .local
                return
            }
            UserDefaults.standard.set(transcriptionMode.rawValue, forKey: Self.savedTranscriptionModeDefaultsKey)
            applyTranscriptionModelSelectionDefaults()
        }
    }

    @Published var selectedLocalModel: LocalTranscriptionModel = .appleOnDevice {
        didSet {
            UserDefaults.standard.set(selectedLocalModel.rawValue, forKey: Self.savedLocalModelDefaultsKey)
            if selectedLocalModel.isWhisperModel {
                refreshWhisperRuntime()
            }
        }
    }
    @Published var selectedLocalEngineMode: LocalTranscriptionEngineMode = .appleSpeech {
        didSet {
            UserDefaults.standard.set(selectedLocalEngineMode.rawValue, forKey: Self.savedLocalEngineModeDefaultsKey)
            if selectedLocalEngineMode != .appleSpeech {
                refreshWhisperRuntime()
            } else {
                refreshAppleSpeechRuntime()
            }
        }
    }
    @Published var selectedWhisperServerConnectionMode: WhisperKitServerConnectionMode = .managedHelper {
        didSet {
            UserDefaults.standard.set(selectedWhisperServerConnectionMode.rawValue, forKey: Self.savedWhisperServerConnectionModeDefaultsKey)
            prewarmSelectedWhisperModelIfNeeded()
        }
    }
    @Published var whisperServerBaseURL: String = "" {
        didSet {
            UserDefaults.standard.set(whisperServerBaseURL, forKey: Self.savedWhisperServerBaseURLDefaultsKey)
        }
    }

    @Published var selectedRemoteModelID: String = ModelRegistry.entry(for: "gpt-4o-mini-transcribe")?.id ?? "" {
        didSet {
            UserDefaults.standard.set(selectedRemoteModelID, forKey: Self.savedRemoteModelDefaultsKey)
        }
    }

    @Published var showAdvancedTranscriptionModels: Bool = false {
        didSet {
            UserDefaults.standard.set(showAdvancedTranscriptionModels, forKey: Self.savedShowAdvancedRemoteModelsDefaultsKey)
        }
    }

    @Published var transcribeResponseFormat: String = "json" {
        didSet {
            UserDefaults.standard.set(transcribeResponseFormat, forKey: Self.savedTranscriptionResponseFormatKey)
            applyTranscriptionModelSelectionDefaults()
        }
    }
    @Published var transcribeUseStream: Bool = false {
        didSet { UserDefaults.standard.set(transcribeUseStream, forKey: Self.savedTranscriptionUseStreamKey) }
    }
    @Published var transcribePrompt: String = "" {
        didSet {
            UserDefaults.standard.set(transcribePrompt, forKey: Self.savedTranscriptionPromptKey)
        }
    }
    @Published var transcribeKnownSpeakerNamesText: String = "" {
        didSet {
            UserDefaults.standard.set(transcribeKnownSpeakerNamesText, forKey: Self.savedTranscriptionKnownSpeakerNamesKey)
        }
    }
    @Published var transcribeKnownSpeakerReferencesText: String = "" {
        didSet {
            UserDefaults.standard.set(transcribeKnownSpeakerReferencesText, forKey: Self.savedTranscriptionKnownSpeakerReferencesKey)
        }
    }
    @Published var transcribeChunkingStrategy: String = "" {
        didSet {
            UserDefaults.standard.set(transcribeChunkingStrategy, forKey: Self.savedTranscriptionChunkingStrategyKey)
        }
    }
    @Published var transcribeUseTimestamps: Bool = false {
        didSet { UserDefaults.standard.set(transcribeUseTimestamps, forKey: Self.savedTranscriptionUseTimestampsKey) }
    }
    @Published var transcribeUseDiarization: Bool = false {
        didSet {
            UserDefaults.standard.set(transcribeUseDiarization, forKey: Self.savedTranscriptionUseDiarizationKey)
            if oldValue != transcribeUseDiarization {
                applyTranscriptionModelSelectionDefaults()
            }
        }
    }
    @Published var transcribeUseLogprobs: Bool = false {
        didSet { UserDefaults.standard.set(transcribeUseLogprobs, forKey: Self.savedTranscriptionUseLogprobsKey) }
    }

    @Published var remoteModelsLoadState: RemoteModelsLoadState = .idle
    @Published private(set) var remoteTranscriptionModels: [ModelAvailabilityRow] = []
    @Published private(set) var whisperRuntimeLoadState: WhisperRuntimeLoadState = .idle
    @Published private(set) var whisperRuntimeStatus: WhisperRuntimeStatus = WhisperRuntimeStatus(
        isSupported: false,
        message: "Whisper not checked yet."
    )
    @Published private(set) var whisperModelInstallStates: [LocalTranscriptionModel: WhisperModelInstallState] = [:]
    @Published private(set) var legacyWhisperInstallStates: [LocalTranscriptionModel: WhisperModelInstallState] = [:]
    @Published private(set) var legacyWhisperRuntimeStatus: WhisperRuntimeStatus = WhisperRuntimeStatus(
        isSupported: false,
        message: "Legacy Whisper not checked yet."
    )
    @Published private(set) var whisperKitServerLoadState: WhisperKitServerLoadState = .idle
    @Published private(set) var whisperKitServerStatus: WhisperKitServerStatus = .idle
    @Published private(set) var appleSpeechRuntimeStatus: AppleSpeechRuntimeStatus = .pendingCheck(locale: .current)
    @Published private(set) var remoteLogicModels: [ModelAvailabilityRow] = []
    @Published private(set) var localLogicModels: [ModelAvailabilityRow] = []
    @Published private(set) var localLogicRuntimeLoadState: LocalLogicRuntimeLoadState = .idle
    @Published private(set) var localLogicAvailableModels: [String] = []

    @Published var logicMode: LogicMode = .local {
        didSet {
            if logicMode != .local {
                logicMode = .local
                return
            }
            UserDefaults.standard.set(logicMode.rawValue, forKey: Self.savedLogicModeDefaultsKey)
            if logicMode == .local {
                formattedOutput = nil
            }
            applyLogicModeDefaults()
        }
    }
    @Published var selectedRemoteLogicModelID: String = ModelRegistry.entry(for: "gpt-5-mini")?.id ?? "" {
        didSet {
            UserDefaults.standard.set(selectedRemoteLogicModelID, forKey: Self.savedRemoteLogicModelDefaultsKey)
        }
    }
    @Published var selectedLocalLogicModelID: String = "gpt-oss-20b" {
        didSet {
            UserDefaults.standard.set(selectedLocalLogicModelID, forKey: Self.savedLocalLogicModelDefaultsKey)
        }
    }

    @Published var logicSettings: LogicSettings = LogicSettings() {
        didSet {
            persistLogicSettings()
        }
    }
    @Published var autoFormatEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoFormatEnabled, forKey: Self.savedAutoFormatDefaultsKey)
        }
    }
    @Published var appearanceMode: AppAppearanceMode = .auto {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.savedAppearanceModeDefaultsKey)
        }
    }

    @Published var lastErrorSummary: String?
    @Published private(set) var lastSessionCompletionResult: RecordingCompletionResult?
    @Published private(set) var lastInsertionResult: InsertionResult?

    @Published private(set) var availableModelIDs: Set<String> = []

    private let transcriptionCoordinator: TranscriptionCoordinator
    private let localLogicService: OllamaLocalLogicService
    private let promptProfileStore: PromptProfileStore
    private let transcriptRecordStore: TranscriptRecordStoreProtocol
    private let postTranscriptionPipeline: PostTranscriptionPipeline
    private let activeAppContextService: ActiveAppContextServiceProtocol
    private let whisperModelManager: WhisperModelManager
    private let whisperKitModelManager: WhisperKitModelManager
    private let whisperKitServerManager: WhisperKitServerManager
    private let appleSpeechRuntimeManager: AppleSpeechRuntimeManaging
    private let appleSpeechPermissionProvider: AppleSpeechPermissionProviding
    private let managedLocalTranscriptionService: ManagedLocalTranscriptionService?
    private let insertionService: InsertionServiceProtocol
    private let globalHotkeyService: GlobalHotkeyServiceProtocol
    private let listeningIndicatorService: ListeningIndicatorServiceProtocol
    private let soundCueService: SoundCueServiceProtocol
    private var remoteModelTask: Task<Void, Never>?
    private var localLogicRuntimeTask: Task<Void, Never>?
    private var appleSpeechRuntimeTask: Task<Void, Never>?
    private var appleSpeechInstallTask: Task<Void, Never>?
    private var hotkeyIsPressed = false
    private var pendingDoubleTapDate: Date?
    private var hasRequestedAccessibilityPrompt = false
    private var shouldForceInsertionForCurrentRecording = false
    private var activeRecordingSessionContext: RecordingSessionContext?
    private var activeLocalModelLifecycleState: String?
    private var activeHotkeyStartResult: HotkeyStartResult?
    private var hotkeyTestTask: Task<Void, Never>?
    private var whisperPrewarmTask: Task<Void, Never>?
    private var isRunningHotkeyTest = false
#if canImport(AppKit)
    private var hotkeyCaptureLocalMonitor: Any?
#endif

    private static let savedApiKeyDefaultsKey = "VerbatimSwiftMVP.OpenAIAPIKey"
    private static let savedTranscriptionModeDefaultsKey = "VerbatimSwiftMVP.TranscriptionMode"
    private static let savedRemoteModelDefaultsKey = "VerbatimSwiftMVP.RemoteModelID"
    private static let savedLocalModelDefaultsKey = "VerbatimSwiftMVP.LocalModelID"
    private static let savedLocalEngineModeDefaultsKey = "VerbatimSwiftMVP.LocalEngineMode"
    private static let savedWhisperServerConnectionModeDefaultsKey = "VerbatimSwiftMVP.WhisperServerConnectionMode"
    private static let savedWhisperServerBaseURLDefaultsKey = "VerbatimSwiftMVP.WhisperServerBaseURL"
    private static let savedSectionDefaultsKey = "VerbatimSwiftMVP.SelectedSection"
    private static let savedShowAdvancedRemoteModelsDefaultsKey = "VerbatimSwiftMVP.ShowAdvancedRemoteModels"
    private static let savedLogicModeDefaultsKey = "VerbatimSwiftMVP.LogicMode"
    private static let savedRemoteLogicModelDefaultsKey = "VerbatimSwiftMVP.RemoteLogicModelID"
    private static let savedLocalLogicModelDefaultsKey = "VerbatimSwiftMVP.LocalLogicModelID"
    private static let savedAutoFormatDefaultsKey = "VerbatimSwiftMVP.AutoFormatEnabled"
    private static let savedAppearanceModeDefaultsKey = "VerbatimSwiftMVP.AppearanceMode"
    private static let savedLogicSettingsKey = "VerbatimSwiftMVP.LogicSettingsV1"
    private static let savedRefineSettingsKey = "VerbatimSwiftMVP.RefineSettingsV1"
    private static let savedInteractionSettingsKey = "VerbatimSwiftMVP.InteractionSettingsV1"
    private static let savedTranscriptionResponseFormatKey = "VerbatimSwiftMVP.TranscriptionResponseFormat"
    private static let savedTranscriptionPromptKey = "VerbatimSwiftMVP.TranscriptionPrompt"
    private static let savedTranscriptionKnownSpeakerNamesKey = "VerbatimSwiftMVP.TranscriptionKnownSpeakerNames"
    private static let savedTranscriptionKnownSpeakerReferencesKey = "VerbatimSwiftMVP.TranscriptionKnownSpeakerReferences"
    private static let savedTranscriptionChunkingStrategyKey = "VerbatimSwiftMVP.TranscriptionChunkingStrategy"
    private static let savedTranscriptionUseStreamKey = "VerbatimSwiftMVP.TranscriptionUseStream"
    private static let savedTranscriptionUseTimestampsKey = "VerbatimSwiftMVP.TranscriptionUseTimestamps"
    private static let savedTranscriptionUseDiarizationKey = "VerbatimSwiftMVP.TranscriptionUseDiarization"
    private static let savedTranscriptionUseLogprobsKey = "VerbatimSwiftMVP.TranscriptionUseLogprobs"
    private static let legacySavedModelDefaultsKey = "VerbatimSwiftMVP.TranscriptionModel"
    private static let diarizationModelID = "gpt-4o-transcribe-diarize"
    private static let diarizedJSONFormat = "diarized_json"

    init(
        transcriptionService: TranscriptionServiceProtocol = OpenAITranscriptionService(),
        localTranscriptionService: LocalTranscriptionServiceProtocol? = nil,
        whisperModelManager: WhisperModelManager? = nil,
        whisperKitModelManager: WhisperKitModelManager? = nil,
        whisperKitServerManager: WhisperKitServerManager? = nil,
        appleSpeechRuntimeManager: AppleSpeechRuntimeManaging? = nil,
        appleSpeechPermissionProvider: AppleSpeechPermissionProviding = LiveAppleSpeechPermissionProvider(),
        logicService: OpenAILogicService = OpenAILogicService(),
        localLogicService: OllamaLocalLogicService = OllamaLocalLogicService(),
        modelCatalogService: ModelCatalogServiceProtocol? = nil,
        transcriptionCoordinator: TranscriptionCoordinator? = nil,
        transcriptIntentResolver: TranscriptIntentResolverProtocol = TranscriptIntentResolver(),
        deterministicFormatter: DeterministicFormatterServiceProtocol = DeterministicFormatterService(),
        contextPackBuilder: ContextPackBuilder = ContextPackBuilder(),
        activeAppContextService: ActiveAppContextServiceProtocol = ActiveAppContextService(),
        promptProfileStore: PromptProfileStore = PromptProfileStore(),
        transcriptRecordStore: TranscriptRecordStoreProtocol = TranscriptRecordStore(),
        insertionService: InsertionServiceProtocol = ClipboardInsertionService(),
        postTranscriptionPipeline: PostTranscriptionPipeline? = nil,
        globalHotkeyService: GlobalHotkeyServiceProtocol = GlobalHotkeyService(),
        listeningIndicatorService: ListeningIndicatorServiceProtocol? = nil,
        soundCueService: SoundCueServiceProtocol = SoundCueService()
    ) {
        let resolvedWhisperModelManager = whisperModelManager ?? WhisperModelManager()
        let resolvedWhisperKitModelManager = whisperKitModelManager ?? WhisperKitModelManager()
        let resolvedWhisperKitServerManager = whisperKitServerManager ?? WhisperKitServerManager()
        let resolvedAppleSpeechRuntimeManager = appleSpeechRuntimeManager ?? AppleSpeechRuntimeManager()
        let routeTracker = LocalTranscriptionRouteTracker()
        let appleService = AppleLocalTranscriptionService(runtimeManager: resolvedAppleSpeechRuntimeManager)
        let resolvedLocalTranscriptionService = localTranscriptionService
            ?? ManagedLocalTranscriptionService(
                appleService: appleService,
                whisperKitService: WhisperKitLocalTranscriptionService(
                    modelManager: resolvedWhisperKitModelManager,
                    routeTracker: routeTracker,
                    serverManager: resolvedWhisperKitServerManager
                ),
                whisperService: WhisperLocalTranscriptionService(modelManager: resolvedWhisperModelManager),
                whisperCppModelManager: resolvedWhisperModelManager,
                routeTracker: routeTracker
            )
        let formatterRouter = LLMFormatterRouter(
            remoteService: logicService,
            localService: localLogicService,
            recordStore: transcriptRecordStore
        )
        let resolvedModelCatalogService = modelCatalogService ?? OpenAIModelCatalogService()
        let resolvedListeningIndicatorService = listeningIndicatorService ?? FloatingListeningIndicatorService()

        self.transcriptionCoordinator = transcriptionCoordinator
            ?? TranscriptionCoordinator(
                remoteEngine: transcriptionService,
                localEngine: resolvedLocalTranscriptionService,
                modelCatalogService: resolvedModelCatalogService
            )
        self.localLogicService = localLogicService
        self.promptProfileStore = promptProfileStore
        self.transcriptRecordStore = transcriptRecordStore
        self.activeAppContextService = activeAppContextService
        self.whisperModelManager = resolvedWhisperModelManager
        self.whisperKitModelManager = resolvedWhisperKitModelManager
        self.whisperKitServerManager = resolvedWhisperKitServerManager
        self.appleSpeechRuntimeManager = resolvedAppleSpeechRuntimeManager
        self.appleSpeechPermissionProvider = appleSpeechPermissionProvider
        self.managedLocalTranscriptionService = resolvedLocalTranscriptionService as? ManagedLocalTranscriptionService
        self.postTranscriptionPipeline = postTranscriptionPipeline
            ?? PostTranscriptionPipeline(
                transcriptIntentResolver: transcriptIntentResolver,
                deterministicFormatter: deterministicFormatter,
                contextPackBuilder: contextPackBuilder,
                activeAppContextService: activeAppContextService,
                transcriptRecordStore: transcriptRecordStore,
                insertionService: insertionService,
                llmFormatterService: formatterRouter
            )
        self.insertionService = insertionService
        self.globalHotkeyService = globalHotkeyService
        self.listeningIndicatorService = resolvedListeningIndicatorService
        self.soundCueService = soundCueService

        apiKey = UserDefaults.standard.string(forKey: Self.savedApiKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applySavedState()
        enforceLocalOnlyDefaults()
        migrateLegacyGlossaryIfNeeded()
        reloadDictionaryEntries()
        reloadTranscriptHistory()
        reloadDiagnosticSessions(limit: diagnosticsSessionLimit.rawValue)
        rebuildModelRows()
        applyTranscriptionModelSelectionDefaults()
        applyLogicModeDefaults()

        if logicMode == .local {
            checkLocalLogicRuntime()
        }
        refreshAppleSpeechRuntime()
        configureHotkeyMonitoring()

        Task { [weak self] in
            guard let self else { return }
            await self.reloadPromptProfiles()
        }
    }

    deinit {}

    var transcriptText: String {
        transcript?.rawText ?? ""
    }

    var statusMessage: String {
        switch state {
        case .idle:
            return idleStatusMessage
        case .recording:
            return "Recording… click again to stop."
        case .transcribing:
            return transcriptionMode == .remote ? "Transcribing with OpenAI..." : "Transcribing on device..."
        case .formatting:
            return "Formatting transcript..."
        case .done:
            if let sessionOutcomeStatusMessage {
                return sessionOutcomeStatusMessage
            }
            if let summary = lastErrorSummary, !summary.isEmpty {
                return "Raw transcript ready. Formatting warning: \(summary)"
            }
            return "Transcript ready."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var accessibilityPermissionStateDescription: String {
        hotkeyPermissionGranted ? "Accessibility access is enabled." : "Accessibility access is not enabled."
    }

    var accessibilityPermissionHelpText: String {
        "Global hotkeys and auto-paste need Accessibility permission. Fn / Globe may still require a fallback shortcut for reliable use outside the app."
    }

    var shouldShowPermissionWarning: Bool {
        interactionSettings.showPermissionWarnings && !hotkeyPermissionGranted
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording:
            return "Stop"
        case .transcribing, .formatting:
            return "Processing..."
        case .error, .done, .idle:
            return "Start recording"
        }
    }

    var canToggleRecording: Bool {
        switch state {
        case .recording:
            return true
        case .transcribing, .formatting:
            return false
        default:
            return canStartForCurrentMode
        }
    }

    var hotkeyBindingTitle: String {
        interactionSettings.hotkeyBinding.displayTitle
    }

    var canUseRecommendedHotkeyFallback: Bool {
        interactionSettings.hotkeyBinding.isFunctionOnlyBinding
            && (activeHotkeyStartResult?.recommendedFallback != nil || HotkeyBinding.recommendedFallbacks.first != nil)
    }

    var hasEffectiveHotkeyOverride: Bool {
        effectiveHotkeyBindingTitle != hotkeyBindingTitle
    }

    var hotkeyValidationResult: HotkeyValidationResult {
        interactionSettings.hotkeyBinding.validationResult
    }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        appleSpeechPermissionProvider.microphoneAuthorizationStatus()
    }

    var speechAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        appleSpeechPermissionProvider.speechAuthorizationStatus()
    }

    var canInstallAppleSpeechAssets: Bool {
        appleSpeechRuntimeStatus.canInstallAssets && appleSpeechRuntimeStatus.isInstallingAssets == false && !isBusy
    }

    var appleSpeechInstallProgressValue: Double? {
        appleSpeechRuntimeStatus.installationProgress
    }

    var appleSpeechPrimaryActionTitle: String? {
        switch appleSpeechRuntimeStatus.lifecycleState {
        case .installRequired:
            return "Install"
        case .failed:
            return appleSpeechRuntimeStatus.canInstallAssets ? "Retry Install" : nil
        case .ready, .installing, .unsupportedLocale, .unavailable:
            return nil
        }
    }

    var canStartForCurrentMode: Bool {
        switch transcriptionMode {
        case .remote:
            return effectiveApiKey != nil && selectedTranscriptionModel != nil && isSelectedRemoteModelAvailable
        case .local:
            switch selectedLocalEngineMode {
            case .appleSpeech:
                if microphoneAuthorizationStatus == .denied || microphoneAuthorizationStatus == .restricted {
                    return false
                }
                switch speechAuthorizationStatus {
                case .denied, .restricted:
                    return false
                case .authorized, .notDetermined:
                    break
                @unknown default:
                    return false
                }
                if appleSpeechRuntimeStatus.isPendingCheck {
                    return true
                }
                return appleSpeechRuntimeStatus.isReady
            case .whisperKit:
                return selectedLocalModel.isWhisperModel
                    && whisperRuntimeStatus.isAvailable
                    && localWhisperInstallState(for: selectedLocalModel).isReady
            case .legacyWhisper:
                return selectedLocalModel.isWhisperModel
                    && legacyWhisperRuntimeStatus.isAvailable
                    && legacyWhisperInstallState(for: selectedLocalModel).isReady
            }
        }
    }

    var hasApiKeyConfigured: Bool {
        effectiveApiKey != nil
    }

    var canSaveApiKey: Bool {
        !sanitizedApiKey.isEmpty
    }

    var canClearApiKey: Bool {
        !sanitizedApiKey.isEmpty || hasStoredApiKey
    }

    var hasStoredApiKey: Bool {
        !storedApiKey.isEmpty
    }

    var keyStatusMessage: String {
        if !sanitizedApiKey.isEmpty {
            return "Using API key from app."
        }
        if let env = environmentApiKey, !env.isEmpty {
            return "Using OPENAI_API_KEY from environment."
        }
        if hasStoredApiKey {
            return "Using saved app key."
        }
        return "No API key configured."
    }

    var remoteTranscriptionStatusMessage: String {
        if availableModelIDs.isEmpty {
            return "Add an API key and click Refresh to load OpenAI model availability."
        }
        switch remoteModelsLoadState {
        case .idle:
            return "Remote models ready."
        case .loading:
            return "Loading remote model availability..."
        case .loaded:
            return "Remote models loaded from OpenAI."
        case .error(let message):
            return message
        }
    }

    var isRemoteModelsStatusError: Bool {
        if case .error = remoteModelsLoadState {
            return true
        }
        return false
    }

    var shouldShowTranscriptTabs: Bool {
        transcript != nil
    }

    var isAnyRemoteModeEnabled: Bool {
        transcriptionMode == .remote || logicMode == .remote
    }

    var showApiKeyControls: Bool {
        transcriptionMode == .remote || logicMode == .remote
    }

    var selectedTranscriptionModel: ModelRegistryEntry? {
        ModelRegistry.entry(for: selectedRemoteModelID)
    }

    var selectedLogicModel: ModelRegistryEntry? {
        switch logicMode {
        case .remote:
            return ModelRegistry.entry(for: selectedRemoteLogicModelID)
        case .local:
            return ModelRegistry.entry(for: selectedLocalLogicModelID)
        }
    }

    var isSelectedRemoteModelAvailable: Bool {
        guard let selectedModel = selectedTranscriptionModel else { return false }
        return availableModelIDs.contains(selectedModel.id)
    }

    var shouldShowLogicLocalPhase2Note: Bool {
        false
    }

    var canRunAutoFormat: Bool {
        if !autoFormatEnabled { return false }
        if logicMode == .local {
            guard let logicModel = selectedLogicModel else { return false }
            return logicModel.isEnabled
        }
        return false
    }

    var canConfigureReasoningEffort: Bool {
        guard let modelID = selectedLogicModel?.id else { return false }
        switch logicMode {
        case .local:
            return modelID.hasPrefix("gpt-oss")
        case .remote:
            return false
        }
    }

    var localLogicRuntimeStatusMessage: String {
        switch localLogicRuntimeLoadState {
        case .idle:
            return "Local runtime not checked yet."
        case .checking:
            return "Checking local runtime..."
        case .ready:
            return "Local runtime ready."
        case .error(let message):
            return message
        }
    }

    var localTranscriptionRuntimeStatusMessage: String {
        switch selectedLocalEngineMode {
        case .appleSpeech:
            switch microphoneAuthorizationStatus {
            case .denied, .restricted:
                return AudioRecorderError.microphonePermissionDenied.localizedDescription
            case .authorized, .notDetermined:
                break
            @unknown default:
                return "Microphone permission is unavailable."
            }

            switch speechAuthorizationStatus {
            case .denied:
                return LocalTranscriptionError.speechPermissionDenied.localizedDescription
            case .restricted:
                return LocalTranscriptionError.speechPermissionRestricted.localizedDescription
            case .authorized:
                return appleSpeechRuntimeStatus.message
            case .notDetermined:
                if appleSpeechRuntimeStatus.isReady {
                    return "Apple Dictation is ready. Speech recognition permission will be requested on first use."
                }
                return appleSpeechRuntimeStatus.message
            @unknown default:
                return "Speech recognition permission is unavailable."
            }
        case .whisperKit:
            return whisperRuntimeStatus.message
        case .legacyWhisper:
            return legacyWhisperRuntimeStatus.message
        }
    }

    var isLocalTranscriptionRuntimeStatusError: Bool {
        switch selectedLocalEngineMode {
        case .appleSpeech:
            if microphoneAuthorizationStatus == .denied || microphoneAuthorizationStatus == .restricted {
                return true
            }
            if speechAuthorizationStatus == .denied || speechAuthorizationStatus == .restricted {
                return true
            }
            if appleSpeechRuntimeStatus.isPendingCheck {
                return false
            }
            return appleSpeechRuntimeStatus.isReady == false
        case .whisperKit:
            if case .error = whisperRuntimeLoadState {
                return true
            }
            return !whisperRuntimeStatus.isAvailable
        case .legacyWhisper:
            return !legacyWhisperRuntimeStatus.isAvailable
        }
    }

    var selectedLocalModelSecondaryNote: String {
        switch selectedLocalEngineMode {
        case .appleSpeech:
            if let resolvedLocale = appleSpeechRuntimeStatus.resolvedLocale {
                return "Apple Dictation uses system-managed speech assets for \(resolvedLocale.identifier)."
            }
            return "Apple Dictation uses system-managed speech assets for the current macOS locale."
        case .whisperKit:
            if selectedLocalModel.recommendedForFirstDownload {
                return "Recommended first Whisper download."
            }
            return selectedLocalModel.detail
        case .legacyWhisper:
            return "Uses local whisper.cpp model files already installed on this Mac."
        }
    }

    var isLocalLogicRuntimeStatusError: Bool {
        if case .error = localLogicRuntimeLoadState {
            return true
        }
        return false
    }

    var canShowFormattingWarning: Bool {
        lastErrorSummary != nil && !lastErrorSummary!.isEmpty
    }

    var shouldShowLowConfidenceToggle: Bool {
        selectedTranscriptionModel?.supportsLogprobs ?? false
    }

    var canUseTimestamps: Bool {
        selectedTranscriptionModel?.supportsTimestamps ?? false
    }

    var canEnableStreaming: Bool {
        selectedTranscriptionModel?.supportsStreaming ?? false
    }

    var canUseDiarization: Bool {
        selectedTranscriptionModel?.supportsDiarization ?? false
    }

    var canUsePromptForTranscription: Bool {
        selectedTranscriptionModel?.supportsPrompt ?? false
    }

    var shouldForceDiarizedSpeakerOutput: Bool {
        selectedTranscriptionModel?.id == Self.diarizationModelID && transcribeUseDiarization
    }

    var isBusy: Bool {
        switch state {
        case .recording, .transcribing, .formatting:
            return true
        default:
            return false
        }
    }

    var statusSymbol: String {
        switch state {
        case .idle:
            return "checkmark.circle"
        case .recording:
            return "waveform"
        case .transcribing:
            return "hourglass"
        case .formatting:
            return "brain"
        case .done:
            return "checkmark.seal"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    func selectRemoteTranscriptionModel(_ id: String) {
        selectedRemoteModelID = id
        applyTranscriptionModelSelectionDefaults()
    }

    func selectLocalModel(_ model: LocalTranscriptionModel) {
        selectedLocalModel = model
        if model.isAppleModel {
            selectedLocalEngineMode = .appleSpeech
            refreshAppleSpeechRuntime()
        } else if selectedLocalEngineMode == .appleSpeech {
            selectedLocalEngineMode = .whisperKit
        }
        if model.isWhisperModel {
            refreshWhisperRuntime()
            prewarmSelectedWhisperModelIfNeeded()
        }
    }

    func selectLocalEngineMode(_ mode: LocalTranscriptionEngineMode) {
        selectedLocalEngineMode = mode
        if mode == .appleSpeech {
            selectedLocalModel = .appleOnDevice
            refreshAppleSpeechRuntime()
        } else if selectedLocalModel.isAppleModel {
            selectedLocalModel = .whisperBase
        }
        prewarmSelectedWhisperModelIfNeeded()
    }

    func refreshAppleSpeechRuntime() {
        appleSpeechRuntimeTask?.cancel()
        appleSpeechRuntimeTask = Task { [weak self] in
            guard let self else { return }
            let status = await appleSpeechRuntimeManager.status(for: .current)
            guard !Task.isCancelled else { return }
            appleSpeechRuntimeStatus = status
        }
    }

    func installAppleSpeechAssets() {
        guard canInstallAppleSpeechAssets else { return }
        appleSpeechInstallTask?.cancel()
        appleSpeechInstallTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await appleSpeechRuntimeManager.installAssets(for: .current) { [weak self] progress in
                    guard let self else { return }
                    await MainActor.run {
                        self.appleSpeechRuntimeStatus = .installing(
                            locale: self.appleSpeechRuntimeStatus.resolvedLocale ?? .current,
                            progress: progress
                        )
                    }
                }
                guard !Task.isCancelled else { return }
                appleSpeechRuntimeStatus = status
            } catch {
                guard !Task.isCancelled else { return }
                appleSpeechRuntimeStatus = .failed(
                    message: error.localizedDescription,
                    locale: appleSpeechRuntimeStatus.resolvedLocale ?? .current,
                    canInstallAssets: true
                )
            }
            appleSpeechInstallTask = nil
        }
    }

    func selectRemoteLogicModel(_ id: String) {
        selectedRemoteLogicModelID = id
    }

    func selectLocalLogicModel(_ id: String) {
        selectedLocalLogicModelID = id
        if logicMode == .local {
            checkLocalLogicRuntime()
        }
    }

    func refreshRemoteModels() {
        remoteModelTask?.cancel()

        guard let apiKeyToUse = effectiveApiKey else {
            rebuildModelRows()
            remoteModelsLoadState = .idle
            return
        }

        remoteModelTask = Task {
            await refreshRemoteModelsTask(apiKey: apiKeyToUse)
        }
    }

    func checkLocalLogicRuntime() {
        localLogicRuntimeTask?.cancel()
        localLogicRuntimeLoadState = .checking
        let modelID = selectedLocalLogicModelID
        localLogicRuntimeTask = Task {
            let status = await localLogicService.checkRuntime(expectedModelID: modelID)
            guard !Task.isCancelled else { return }
            localLogicAvailableModels = status.availableModels
            if status.isReachable && status.hasExpectedModel {
                localLogicRuntimeLoadState = .ready
            } else {
                localLogicRuntimeLoadState = .error(status.message)
            }
        }
    }

    func refreshWhisperRuntime() {
        whisperRuntimeLoadState = .checking
        Task { [weak self] in
            guard let self else { return }
            let runtime = await whisperKitModelManager.runtimeStatus()
            let states = await whisperKitModelManager.refreshInstallStates()
            let legacyRuntime = await whisperModelManager.runtimeStatus()
            let legacyStates = await whisperModelManager.refreshInstallStates()
            guard !Task.isCancelled else { return }
            whisperRuntimeStatus = runtime
            whisperModelInstallStates = states
            legacyWhisperRuntimeStatus = legacyRuntime
            legacyWhisperInstallStates = legacyStates
            whisperRuntimeLoadState = runtime.isAvailable ? .ready : .error(runtime.message)
            prewarmSelectedWhisperModelIfNeeded()
        }
    }

    func checkWhisperKitServer() {
        whisperKitServerLoadState = .checking
        Task { [weak self] in
            guard let self else { return }
            let status = await whisperKitServerManager.status(
                connectionMode: selectedWhisperServerConnectionMode,
                externalBaseURL: whisperServerBaseURL
            )
            guard !Task.isCancelled else { return }
            whisperKitServerStatus = status
            whisperKitServerLoadState = status.isReachable ? .ready : .error(status.message)
        }
    }

    func performPrimaryLocalModelAction(for model: LocalTranscriptionModel) {
        if model.isAppleModel {
            installAppleSpeechAssets()
            return
        }
        performPrimaryWhisperAction(for: model)
    }

    func downloadWhisperModel(_ model: LocalTranscriptionModel) {
        guard model.isWhisperModel else { return }
        whisperModelInstallStates[model] = .downloading(progress: nil)
        Task { [weak self] in
            guard let self else { return }
            let state = await whisperKitModelManager.downloadModel(model) { progress in
                await MainActor.run {
                    self.whisperModelInstallStates[model] = .downloading(progress: progress)
                }
            }
            let runtime = await whisperKitModelManager.runtimeStatus()
            let states = await whisperKitModelManager.refreshInstallStates()
            guard !Task.isCancelled else { return }
            whisperRuntimeStatus = runtime
            whisperModelInstallStates = states.merging([model: state]) { _, new in new }
            switch state {
            case .failed(let message):
                whisperRuntimeLoadState = .error(message)
            default:
                whisperRuntimeLoadState = runtime.isAvailable ? .ready : .error(runtime.message)
                prewarmSelectedWhisperModelIfNeeded()
            }
        }
    }

    func installWhisperModel(_ model: LocalTranscriptionModel) {
        guard model.isWhisperModel else { return }
        whisperModelInstallStates[model] = .installing
        Task { [weak self] in
            guard let self else { return }
            let state = await whisperKitModelManager.installModel(model) { progress in
                await MainActor.run {
                    if let progress {
                        self.whisperModelInstallStates[model] = .downloading(progress: progress)
                    } else {
                        self.whisperModelInstallStates[model] = .installing
                    }
                }
            }
            let runtime = await whisperKitModelManager.runtimeStatus()
            let states = await whisperKitModelManager.refreshInstallStates()
            guard !Task.isCancelled else { return }
            whisperRuntimeStatus = runtime
            whisperModelInstallStates = states.merging([model: state]) { _, new in new }
            switch state {
            case .failed(let message):
                whisperRuntimeLoadState = .error(message)
            default:
                whisperRuntimeLoadState = runtime.isAvailable ? .ready : .error(runtime.message)
                prewarmSelectedWhisperModelIfNeeded()
            }
        }
    }

    private func prewarmSelectedWhisperModelIfNeeded() {
        whisperPrewarmTask?.cancel()
        guard transcriptionMode == .local,
              selectedLocalEngineMode == .whisperKit,
              selectedWhisperServerConnectionMode == .managedHelper,
              selectedLocalModel.isWhisperModel else {
            return
        }

        whisperPrewarmTask = Task { [weak self] in
            guard let self else { return }
            guard let modelDirectoryURL = await whisperKitModelManager.installedModelURL(for: selectedLocalModel) else {
                return
            }
            do {
                let metadata = try await whisperKitServerManager.prewarmManagedRuntime(
                    model: selectedLocalModel,
                    modelDirectoryURL: modelDirectoryURL
                )
                guard !Task.isCancelled else { return }
                whisperKitServerStatus = WhisperKitServerStatus(
                    isReachable: metadata.helperState == .running,
                    message: metadata.lastFailureMessage ?? "Managed WhisperKit helper is available.",
                    activeModel: metadata.activeModel
                )
                whisperKitServerLoadState = metadata.helperState == .running ? .ready : .error(metadata.lastFailureMessage ?? "Managed WhisperKit helper is unavailable.")
            } catch {
                guard !Task.isCancelled else { return }
                whisperKitServerStatus = WhisperKitServerStatus(
                    isReachable: false,
                    message: error.localizedDescription,
                    activeModel: nil
                )
                whisperKitServerLoadState = .error(error.localizedDescription)
            }
        }
    }

    func removeWhisperModel(_ model: LocalTranscriptionModel) {
        guard model.isWhisperModel else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await whisperKitModelManager.removeModel(model)
                let states = await whisperKitModelManager.refreshInstallStates()
                guard !Task.isCancelled else { return }
                whisperModelInstallStates = states
                whisperRuntimeLoadState = whisperRuntimeStatus.isAvailable ? .ready : .error(whisperRuntimeStatus.message)
            } catch {
                guard !Task.isCancelled else { return }
                whisperModelInstallStates[model] = .failed(message: error.localizedDescription)
                whisperRuntimeLoadState = .error(error.localizedDescription)
            }
        }
    }

    func performPrimaryWhisperAction(for model: LocalTranscriptionModel) {
        guard selectedLocalEngineMode == .whisperKit else { return }
        guard whisperRuntimeStatus.isAvailable else { return }

        switch localWhisperInstallState(for: model) {
        case .notDownloaded:
            downloadWhisperModel(model)
        case .downloaded:
            installWhisperModel(model)
        case .failed:
            downloadWhisperModel(model)
        case .downloading, .installing, .ready:
            break
        }
    }

    @discardableResult
    func refreshWhisperModelState(_ model: LocalTranscriptionModel) -> WhisperModelInstallState {
        let state = whisperModelInstallStates[model] ?? .notDownloaded
        Task { [weak self] in
            guard let self else { return }
            let refreshedState = await whisperKitModelManager.refreshModelState(for: model)
            guard !Task.isCancelled else { return }
            whisperModelInstallStates[model] = refreshedState
        }
        return state
    }

    func start(fromHotkey: Bool = false) {
        guard canStartForCurrentMode else {
            state = .error(blockedStartMessage)
            return
        }
        if case .recording = state { return }
        if isBusy {
            return
        }

        shouldForceInsertionForCurrentRecording = fromHotkey
        let activeContext = activeAppContextService.currentContext()
        if transcriptionMode == .local {
            if selectedLocalEngineMode == .appleSpeech {
                activeLocalModelLifecycleState = appleSpeechRuntimeStatus.lifecycleIdentifier
            } else if selectedLocalModel.isWhisperModel {
                activeLocalModelLifecycleState = activeWhisperLifecycleState(for: selectedLocalModel).lifecycleIdentifier
            } else {
                activeLocalModelLifecycleState = nil
            }
        } else {
            activeLocalModelLifecycleState = nil
        }
        activeRecordingSessionContext = RecordingSessionContext(
            activeAppContext: activeContext,
            insertionTarget: activeContext.insertionTarget,
            stylePreset: refineSettings.preset(for: activeContext.styleCategory),
            triggerSource: fromHotkey ? .hotkey : .manual,
            triggerMode: fromHotkey ? interactionSettings.hotkeyTriggerMode : nil,
            lockTargetAtStart: fromHotkey ? interactionSettings.lockTargetAtStart : false
        )

        Task {
            do {
                lastSessionCompletionResult = nil
                lastInsertionResult = nil
                guard let request = makeTranscriptionSessionRequest() else {
                    state = .error(blockedStartMessage)
                    return
                }
                _ = try await transcriptionCoordinator.startSession(request: request)
                state = .recording
                if interactionSettings.showListeningIndicator {
                    listeningIndicatorService.showListening()
                }
                if interactionSettings.playSoundCues {
                    soundCueService.playStartCue()
                }
            } catch {
                listeningIndicatorService.hideListening()
                if let err = error as? AudioRecorderError {
                    state = .error(err.localizedDescription)
                } else {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        guard case .recording = state else { return }
        hotkeyIsPressed = false
        pendingDoubleTapDate = nil
        let shouldInsertOnStop = shouldForceInsertionForCurrentRecording
        let recordingSessionContext = activeRecordingSessionContext
        let recordedLocalModelLifecycleState = activeLocalModelLifecycleState
        shouldForceInsertionForCurrentRecording = false
        activeRecordingSessionContext = nil
        activeLocalModelLifecycleState = nil
        if interactionSettings.showListeningIndicator {
            listeningIndicatorService.showProcessing()
        } else {
            listeningIndicatorService.hideListening()
        }
        if interactionSettings.playSoundCues {
            soundCueService.playStopCue()
        }

        Task {
            state = .transcribing
            lastErrorSummary = nil
            latestLLMResult = nil
            pendingActionItemsJSON = nil
            pendingActionItemsRenderedText = nil
            lastSessionCompletionResult = nil
            lastInsertionResult = nil
            let transcriptionStartedAt = Date()

            do {
                transcript = nil
                deterministicResult = nil
                formattedOutput = nil
                var finalTranscript: Transcript?
                let updates = transcriptionCoordinator.stopSessionAndTranscribe()
                for try await update in updates {
                    switch update {
                    case .session:
                        break
                    case .completion(let completion):
                        lastSessionCompletionResult = completion
                    case .transcript(_, let snapshot):
                        transcript = snapshot.currentTranscript
                        if let authoritative = snapshot.finalTranscript {
                            finalTranscript = authoritative
                        }
                    }
                }
                let localRouteResolution = await managedLocalTranscriptionService?.latestRouteResolution()

                if case .some(.skippedSilence(let context)) = lastSessionCompletionResult {
                    appendDiagnosticSession(
                        DiagnosticSessionRecord(
                            sessionID: context.sessionID,
                            startedAt: context.startedAt,
                            durationMs: max(Int(Date().timeIntervalSince(context.startedAt) * 1000), 0),
                            triggerSource: context.triggerSource,
                            triggerMode: context.triggerMode,
                            transcriptionEngine: selectedTranscriptionEngineIDForDiagnostics,
                            localEngineMode: transcriptionMode == .local ? selectedLocalEngineMode.rawValue : nil,
                            resolvedBackend: localRouteResolution?.resolvedBackend.rawValue,
                            transport: localRouteResolution?.transport?.rawValue,
                            serverConnectionMode: localRouteResolution?.serverConnectionMode?.rawValue,
                            modelID: resultModelIDForDiagnostics,
                            localModelLifecycleState: recordedLocalModelLifecycleState,
                            helperState: localRouteResolution?.helperState?.rawValue,
                            prewarmState: localRouteResolution?.prewarmState?.rawValue,
                            failureStage: localRouteResolution?.failureStage?.rawValue,
                            logicModelID: selectedLogicModelIDForDiagnostics,
                            reasoningEffort: logicSettings.reasoningEffort.rawValue,
                            formattingProfile: nil,
                            transcriptionLatencyMs: max(Int(Date().timeIntervalSince(transcriptionStartedAt) * 1000), 0),
                            llmLatencyMs: nil,
                            totalLatencyMs: max(Int(Date().timeIntervalSince(context.startedAt) * 1000), 0),
                            tokensIn: nil,
                            cachedTokens: nil,
                            insertionOutcome: nil,
                            fallbackReason: nil,
                            targetApp: context.targetAppName,
                            targetBundleID: context.targetBundleID,
                            silencePeak: context.audioActivitySummary?.peakLevel,
                            silenceAverageRMS: context.audioActivitySummary?.averagePower,
                            silenceVoicedRatio: context.audioActivitySummary?.voicedRatio,
                            skippedForSilence: true,
                            failureMessage: nil
                        )
                    )
                    selectedTranscriptViewMode = .raw
                    if interactionSettings.showListeningIndicator {
                        listeningIndicatorService.showOutcome(.noSpeechDetected)
                    } else {
                        listeningIndicatorService.hideListening()
                    }
                    reloadDiagnosticSessions(limit: diagnosticsSessionLimit.rawValue)
                    state = .done
                    return
                }

                guard let result = finalTranscript ?? transcript else {
                    listeningIndicatorService.hideListening()
                    state = .error("No transcription text was produced.")
                    return
                }

                transcript = result
                if autoFormatEnabled && canRunAutoFormat {
                    state = .formatting
                }

                let pipelineResult = await postTranscriptionPipeline.processCompletedTranscript(
                    PostTranscriptionPipelineRequest(
                        transcript: result,
                        recordingSessionContext: recordingSessionContext,
                        activeAppContextOverride: recordingSessionContext?.lockTargetAtStart == true
                            ? recordingSessionContext?.activeAppContext
                            : nil,
                        glossaryEntries: dictionaryEntries,
                        promptProfiles: promptProfiles,
                        transcriptionMode: transcriptionMode,
                        logicMode: logicMode,
                        logicSettings: logicSettings,
                        refineSettings: refineSettings,
                        interactionSettings: interactionSettings,
                        autoFormatEnabled: autoFormatEnabled,
                        canRunAutoFormat: canRunAutoFormat,
                        transcriptionEngineID: selectedTranscriptionEngineIDForDiagnostics,
                        localEngineMode: transcriptionMode == .local ? selectedLocalEngineMode.rawValue : nil,
                        resolvedLocalBackend: localRouteResolution?.resolvedBackend.rawValue,
                        transport: localRouteResolution?.transport?.rawValue,
                        serverConnectionMode: localRouteResolution?.serverConnectionMode?.rawValue,
                        transcriptionLatencyMs: max(Int(Date().timeIntervalSince(transcriptionStartedAt) * 1000), 0),
                        localModelLifecycleState: recordedLocalModelLifecycleState,
                        helperState: localRouteResolution?.helperState?.rawValue,
                        prewarmState: localRouteResolution?.prewarmState?.rawValue,
                        failureStage: localRouteResolution?.failureStage?.rawValue,
                        effectiveAPIKey: effectiveApiKey,
                        selectedRemoteLogicModelID: selectedRemoteLogicModelID,
                        selectedLocalLogicModelID: selectedLocalLogicModelID,
                        forceInsertion: shouldInsertOnStop
                    )
                )

                deterministicResult = pipelineResult.deterministicResult
                latestLLMResult = pipelineResult.latestLLMResult
                formattedOutput = pipelineResult.formattedOutput
                pendingActionItemsJSON = pipelineResult.pendingActionItemsJSON
                pendingActionItemsRenderedText = pipelineResult.pendingActionItemsRenderedText
                lastInsertionResult = pipelineResult.insertionResult
                lastErrorSummary = pipelineResult.lastErrorSummary
                selectedTranscriptViewMode = .formatted
                reloadTranscriptHistory()
                if interactionSettings.showListeningIndicator {
                    showListeningIndicatorOutcome(for: pipelineResult.insertionResult)
                } else {
                    listeningIndicatorService.hideListening()
                }

                state = .done
                reloadDiagnosticSessions(limit: diagnosticsSessionLimit.rawValue)
            } catch {
                listeningIndicatorService.hideListening()
                let localRouteResolution = await managedLocalTranscriptionService?.latestRouteResolution()
                if transcriptionMode == .local, selectedLocalEngineMode == .appleSpeech {
                    refreshAppleSpeechRuntime()
                } else if transcriptionMode == .local, selectedLocalModel.isWhisperModel {
                    whisperModelInstallStates[selectedLocalModel] = .failed(message: error.localizedDescription)
                }
                lastSessionCompletionResult = .failed(
                    message: error.localizedDescription,
                    context: recordingSessionContext
                )
                if let recordingSessionContext {
                    appendDiagnosticSession(
                        DiagnosticSessionRecord(
                            sessionID: recordingSessionContext.sessionID,
                            startedAt: recordingSessionContext.startedAt,
                            durationMs: max(Int(Date().timeIntervalSince(recordingSessionContext.startedAt) * 1000), 0),
                            triggerSource: recordingSessionContext.triggerSource,
                            triggerMode: recordingSessionContext.triggerMode,
                            transcriptionEngine: selectedTranscriptionEngineIDForDiagnostics,
                            localEngineMode: transcriptionMode == .local ? selectedLocalEngineMode.rawValue : nil,
                            resolvedBackend: localRouteResolution?.resolvedBackend.rawValue,
                            transport: localRouteResolution?.transport?.rawValue,
                            serverConnectionMode: localRouteResolution?.serverConnectionMode?.rawValue,
                            modelID: resultModelIDForDiagnostics,
                            localModelLifecycleState: recordedLocalModelLifecycleState,
                            helperState: localRouteResolution?.helperState?.rawValue,
                            prewarmState: localRouteResolution?.prewarmState?.rawValue,
                            failureStage: localRouteResolution?.failureStage?.rawValue,
                            logicModelID: selectedLogicModelIDForDiagnostics,
                            reasoningEffort: logicSettings.reasoningEffort.rawValue,
                            formattingProfile: nil,
                            transcriptionLatencyMs: max(Int(Date().timeIntervalSince(transcriptionStartedAt) * 1000), 0),
                            llmLatencyMs: nil,
                            totalLatencyMs: max(Int(Date().timeIntervalSince(recordingSessionContext.startedAt) * 1000), 0),
                            tokensIn: nil,
                            cachedTokens: nil,
                            insertionOutcome: .failed,
                            fallbackReason: nil,
                            targetApp: recordingSessionContext.targetAppName,
                            targetBundleID: recordingSessionContext.targetBundleID,
                            silencePeak: recordingSessionContext.audioActivitySummary?.peakLevel,
                            silenceAverageRMS: recordingSessionContext.audioActivitySummary?.averagePower,
                            silenceVoicedRatio: recordingSessionContext.audioActivitySummary?.voicedRatio,
                            skippedForSilence: false,
                            failureMessage: error.localizedDescription
                        )
                    )
                    reloadDiagnosticSessions(limit: diagnosticsSessionLimit.rawValue)
                }
                if let err = error as? AudioRecorderError {
                    state = .error(err.localizedDescription)
                } else if let err = error as? OpenAITranscriptionError {
                    state = .error(err.localizedDescription)
                } else if let err = error as? LocalTranscriptionError {
                    state = .error(err.localizedDescription)
                } else {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    func saveApiKey() {
        let trimmed = sanitizedApiKey
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.savedApiKeyDefaultsKey)
        if isAnyRemoteModeEnabled {
            refreshRemoteModels()
        }
    }

    func clearStoredApiKey() {
        UserDefaults.standard.removeObject(forKey: Self.savedApiKeyDefaultsKey)
        if !sanitizedApiKey.isEmpty {
            apiKey = ""
        }
        if isAnyRemoteModeEnabled {
            refreshRemoteModels()
        }
    }

    func copyTranscript() {
        let text = selectedTranscriptViewMode == .formatted
            ? (formattedOutput?.clean_text ?? deterministicResult?.text ?? transcriptText)
            : transcriptText
        guard !text.isEmpty else { return }
        _ = insertionService.insert(text: text, autoPaste: false, target: nil, requiresFrozenTarget: false)
    }

    func copyTranscriptRecord(_ record: TranscriptRecord) {
        let text = preferredTranscriptText(for: record)
        guard !text.isEmpty else { return }
        _ = insertionService.insert(text: text, autoPaste: false, target: nil, requiresFrozenTarget: false)
    }

    func copyRawTranscriptRecord(_ record: TranscriptRecord) {
        let text = record.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = insertionService.insert(text: text, autoPaste: false, target: nil, requiresFrozenTarget: false)
    }

    func copyTranscriptFeedbackPacket(_ record: TranscriptRecord) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let payload = [
            "Transcript feedback",
            "Created: \(formatter.string(from: record.createdAt))",
            "App: \(record.activeAppName)",
            "Category: \(record.styleCategory.title)",
            "",
            "Formatted / final text:",
            preferredTranscriptText(for: record),
            "",
            "Raw transcript:",
            record.rawText
        ]
        .joined(separator: "\n")

        _ = insertionService.insert(text: payload, autoPaste: false, target: nil, requiresFrozenTarget: false)
    }

    func reloadTranscriptHistory(limit: Int = 200) {
        transcriptHistory = transcriptRecordStore.fetchRecentRecords(limit: limit)
    }

    func reloadDiagnosticSessions(limit: Int = 20) {
        diagnosticSessions = transcriptRecordStore.fetchRecentDiagnosticSessions(limit: limit)
        diagnosticSessionSummary = transcriptRecordStore.fetchDiagnosticSessionSummary(limit: limit)
    }

    func reloadDictionaryEntries() {
        dictionaryEntries = transcriptRecordStore.fetchDictionaryEntries().map(\.glossaryEntry)
    }

    func upsertDictionaryEntry(from: String, to: String) {
        transcriptRecordStore.upsertDictionaryEntry(from: from, to: to, note: nil)
        reloadDictionaryEntries()
    }

    func replaceDictionaryEntries(_ entries: [GlossaryEntry]) {
        transcriptRecordStore.replaceDictionaryEntries(entries)
        dictionaryEntries = entries
    }

    func preferredTranscriptText(for record: TranscriptRecord) -> String {
        let finalText = record.finalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !finalText.isEmpty {
            return finalText
        }

        let formatted = record.llmText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formatted.isEmpty {
            return formatted
        }

        let deterministic = record.deterministicText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deterministic.isEmpty {
            return deterministic
        }

        return record.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearTranscript() {
        transcript = nil
        formattedOutput = nil
        deterministicResult = nil
        latestLLMResult = nil
        pendingActionItemsJSON = nil
        pendingActionItemsRenderedText = nil
        lastErrorSummary = nil
        lastSessionCompletionResult = nil
        lastInsertionResult = nil
        selectedTranscriptViewMode = .raw
        if case .done = state {
            state = .idle
        }
    }

    func refreshPromptProfiles() {
        Task { [weak self] in
            guard let self else { return }
            await self.reloadPromptProfiles()
        }
    }

    func setPromptProfileEnabled(_ profileID: String, enabled: Bool) {
        Task { [weak self] in
            guard let self else { return }
            await self.promptProfileStore.setProfileEnabled(id: profileID, enabled: enabled)
            await self.reloadPromptProfiles()
        }
    }

    func runManualReformat(profileID: String) {
        guard let transcript else { return }

        Task {
            guard let profile = promptProfiles.first(where: { $0.id == profileID && $0.enabled }) else {
                lastErrorSummary = "Selected profile is unavailable or disabled."
                return
            }

            let pipelineResult = await postTranscriptionPipeline.runManualReformat(
                ManualReformatRequest(
                    transcript: transcript,
                    activeAppContextOverride: nil,
                    glossaryEntries: dictionaryEntries,
                    profile: profile,
                    logicMode: logicMode,
                    logicSettings: logicSettings,
                    refineSettings: refineSettings,
                    interactionSettings: interactionSettings,
                    effectiveAPIKey: effectiveApiKey,
                    selectedRemoteLogicModelID: selectedRemoteLogicModelID,
                    selectedLocalLogicModelID: selectedLocalLogicModelID
                )
            )

            deterministicResult = pipelineResult.deterministicResult
            latestLLMResult = pipelineResult.latestLLMResult
            formattedOutput = pipelineResult.formattedOutput
            pendingActionItemsJSON = pipelineResult.pendingActionItemsJSON
            pendingActionItemsRenderedText = pipelineResult.pendingActionItemsRenderedText
            lastErrorSummary = pipelineResult.lastErrorSummary
            selectedTranscriptViewMode = .formatted
        }
    }

    func confirmActionItemsPreviewInsertion() {
        guard let rendered = pendingActionItemsRenderedText, !rendered.isEmpty else { return }
        lastInsertionResult = insertionService.insert(
            text: rendered,
            autoPaste: interactionSettings.insertionMode == .autoPasteWhenPossible
                && interactionSettings.autoPasteAfterInsert,
            target: nil,
            requiresFrozenTarget: false
        )
        formattedOutput = makeFormattedOutput(from: rendered)
        selectedTranscriptViewMode = .formatted
        pendingActionItemsJSON = nil
        pendingActionItemsRenderedText = nil
    }

    func dismissActionItemsPreview() {
        pendingActionItemsJSON = nil
        pendingActionItemsRenderedText = nil
    }

    func beginHotkeyCapture() {
#if canImport(AppKit)
        guard !isCapturingHotkey else { return }
        globalHotkeyService.stopMonitoring()
        isCapturingHotkey = true
        hotkeyStatusMessage = "Press a key combination or a modifier key (Fn supported)."

        hotkeyCaptureLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if self.handleHotkeyCapture(event: event) {
                return nil
            }
            return event
        }
#else
        hotkeyStatusMessage = "Custom hotkey capture requires macOS."
#endif
    }

    func cancelHotkeyCapture() {
        guard isCapturingHotkey else { return }
        teardownHotkeyCapture()
        configureHotkeyMonitoring()
    }

    func resetHotkeyToDefault() {
        interactionSettings.hotkeyBinding = .defaultFunctionKey
        if interactionSettings.hotkeyEnabled && !hotkeyPermissionGranted {
            requestAccessibilityPermissionPrompt()
        }
    }

    func requestAccessibilityPermissionPrompt() {
        hotkeyPermissionGranted = globalHotkeyService.requestAccessibilityPermissionPrompt()
        hasRequestedAccessibilityPrompt = true

        if hotkeyPermissionGranted {
            configureHotkeyMonitoring()
        } else {
            hotkeyStatusState = .failed(message: "Accessibility permission is required for global hotkeys.")
            hotkeyStatusMessage = "Accessibility permission is required for global hotkeys."
        }
    }

    func useRecommendedHotkeyFallback() {
        if let fallback = activeHotkeyStartResult?.recommendedFallback ?? HotkeyBinding.recommendedFallbacks.first {
            interactionSettings.hotkeyBinding = fallback
        }
    }

    func testSelectedHotkey() {
        startHotkeyVerification(
            binding: interactionSettings.hotkeyBinding,
            fallbackMode: .disabled,
            label: "selected hotkey"
        )
    }

    func testRecommendedHotkeyFallback() {
        guard let fallback = activeHotkeyStartResult?.recommendedFallback ?? HotkeyBinding.recommendedFallbacks.first else {
            hotkeyTestMessage = "No recommended fallback is available."
            return
        }
        startHotkeyVerification(
            binding: fallback,
            fallbackMode: .disabled,
            label: "recommended fallback"
        )
    }

    private func configureHotkeyMonitoring() {
        globalHotkeyService.stopMonitoring()
        hotkeyTestTask?.cancel()
        isRunningHotkeyTest = false
        hotkeyPermissionGranted = globalHotkeyService.hasAccessibilityPermission()
        activeHotkeyStartResult = nil
        effectiveHotkeyBindingTitle = interactionSettings.hotkeyBinding.displayTitle
        recommendedHotkeyFallbackTitle = nil

        guard !isCapturingHotkey else {
            hotkeyStatusState = .inactive
            hotkeyStatusMessage = "Press a key combination or a modifier key (Fn supported)."
            return
        }

        guard interactionSettings.hotkeyEnabled else {
            hotkeyStatusState = .inactive
            hotkeyStatusMessage = "Hotkey monitoring is off."
            return
        }

        let validation = interactionSettings.hotkeyBinding.validationResult
        guard validation.isValid else {
            let message = validation.blockingIssues.first?.message ?? "Select a valid hotkey."
            hotkeyStatusState = .failed(message: message)
            hotkeyStatusMessage = message
            return
        }

        if !hotkeyPermissionGranted && !hasRequestedAccessibilityPrompt {
            hotkeyPermissionGranted = globalHotkeyService.requestAccessibilityPermissionPrompt()
            hasRequestedAccessibilityPrompt = true
        }

        guard hotkeyPermissionGranted else {
            let message = "Accessibility permission is required for global hotkeys."
            hotkeyStatusState = .failed(message: message)
            hotkeyStatusMessage = message
            return
        }

        let startResult = globalHotkeyService.startMonitoring(
            binding: interactionSettings.hotkeyBinding,
            fallbackMode: interactionSettings.functionKeyFallbackMode
        ) { [weak self] event in
            Task { @MainActor in
                self?.appendHotkeyRuntimeLog(event: event)
                self?.handleHotkeyEvent(event)
            }
        }
        activeHotkeyStartResult = startResult
        effectiveHotkeyBindingTitle = startResult.effectiveBinding.displayTitle
        recommendedHotkeyFallbackTitle = startResult.recommendedFallback?.displayTitle
        appendHotkeyRuntimeLog(event: nil, overrideResult: startResult)

        if !startResult.isActive {
            let message = startResult.message ?? "No global hotkey could be activated."
            hotkeyStatusState = .failed(message: message)
            hotkeyStatusMessage = message
        } else if startResult.fallbackWasUsed {
            let message = startResult.message ?? "Fallback shortcut is active."
            hotkeyStatusState = .fallback(
                original: startResult.originalBinding.displayTitle,
                effective: startResult.effectiveBinding.displayTitle,
                message: message
            )
            hotkeyStatusMessage = message
        } else if let warning = validation.warnings.first?.message {
            let message = "Hotkey active: \(startResult.effectiveBinding.displayTitle) • \(warning)"
            hotkeyStatusState = .active(bindingTitle: startResult.effectiveBinding.displayTitle, message: message)
            hotkeyStatusMessage = message
        } else {
            let message = startResult.message ?? "Hotkey active: \(startResult.effectiveBinding.displayTitle) • \(hotkeyBehaviorSummary)"
            hotkeyStatusState = .active(bindingTitle: startResult.effectiveBinding.displayTitle, message: message)
            hotkeyStatusMessage = message
        }
    }

    private func handleHotkeyEvent(_ event: GlobalHotkeyEvent) {
        switch interactionSettings.hotkeyTriggerMode {
        case .holdToTalk:
            switch event {
            case .keyDown:
                guard !hotkeyIsPressed else { return }
                hotkeyIsPressed = true
                if case .recording = state {
                    return
                }
                toggleRecordingFromHotkey()
            case .keyUp:
                guard hotkeyIsPressed else { return }
                hotkeyIsPressed = false
                if case .recording = state {
                    stop()
                }
            }
        case .tapToToggle:
            if event == .keyDown {
                toggleRecordingFromHotkey()
            }
        case .doubleTapLock:
            if event == .keyDown {
                handleDoubleTapLockMode()
            }
        }
    }

    private func toggleRecordingFromHotkey() {
        switch state {
        case .recording:
            stop()
        case .idle, .done, .error:
            if canStartForCurrentMode {
                start(fromHotkey: true)
            } else {
                lastErrorSummary = blockedStartMessage
            }
        case .transcribing, .formatting:
            break
        }
    }

    private func handleDoubleTapLockMode() {
        switch state {
        case .recording:
            stop()
        case .transcribing, .formatting:
            break
        case .idle, .done, .error:
            let now = Date()
            if let previousTap = pendingDoubleTapDate, now.timeIntervalSince(previousTap) <= 0.45 {
                pendingDoubleTapDate = nil
                if canStartForCurrentMode {
                    start(fromHotkey: true)
                } else {
                    lastErrorSummary = blockedStartMessage
                }
            } else {
                pendingDoubleTapDate = now
                lastErrorSummary = "Double-tap the hotkey to lock recording."
            }
        }
    }

    private var sessionOutcomeStatusMessage: String? {
        switch lastSessionCompletionResult {
        case .some(.skippedSilence(_)):
            return "Silence ignored"
        case .some(.failed(let message, _)):
            return message
        case .some(.transcribed(_)), .none:
            if let insertionResult = lastInsertionResult {
                switch insertionResult {
                case .pasted:
                    return "Inserted."
                case .copiedOnly, .copiedOnlyNeedsPermission, .failed:
                    return insertionResult.userMessage
                }
            }
            return nil
        }
    }

    private func showListeningIndicatorOutcome(for insertionResult: InsertionResult?) {
        guard interactionSettings.showListeningIndicator else {
            listeningIndicatorService.hideListening()
            return
        }

        guard let insertionResult else {
            listeningIndicatorService.showCompletedBriefly()
            return
        }

        switch insertionResult {
        case .pasted:
            listeningIndicatorService.showOutcome(.inserted)
        case .copiedOnly(let reason):
            listeningIndicatorService.showOutcome(.copiedOnly(reason.userMessage))
        case .copiedOnlyNeedsPermission:
            listeningIndicatorService.showOutcome(.copiedOnly(ClipboardFallbackReason.accessibilityPermissionRequired.userMessage))
        case .failed(let reason):
            listeningIndicatorService.showOutcome(.failed(InsertionResult.failed(reason: reason).userMessage))
        }
    }

    private var hotkeyBehaviorSummary: String {
        switch interactionSettings.hotkeyTriggerMode {
        case .holdToTalk:
            return "Hold to record, release to send."
        case .tapToToggle:
            return "Single tap to start or stop."
        case .doubleTapLock:
            return "Double tap to lock recording, single tap to stop."
        }
    }

#if canImport(AppKit)
    private func handleHotkeyCapture(event: NSEvent) -> Bool {
        guard isCapturingHotkey else { return false }
        guard let binding = HotkeyBinding.capture(from: event) else { return false }
        let validation = binding.validationResult
        guard validation.isValid else {
            hotkeyStatusMessage = validation.blockingIssues.first?.message ?? "Select a valid hotkey."
            return true
        }

        teardownHotkeyCapture()
        interactionSettings.hotkeyBinding = binding
        if let warning = validation.warnings.first?.message {
            hotkeyStatusMessage = warning
        }
        return true
    }
#endif

    private func teardownHotkeyCapture() {
#if canImport(AppKit)
        if let hotkeyCaptureLocalMonitor {
            NSEvent.removeMonitor(hotkeyCaptureLocalMonitor)
            self.hotkeyCaptureLocalMonitor = nil
        }
#endif
        isCapturingHotkey = false
    }

    private func startHotkeyVerification(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        label: String
    ) {
        guard hotkeyPermissionGranted else {
            hotkeyTestMessage = "Accessibility permission is required for global hotkeys."
            return
        }

        hotkeyTestTask?.cancel()
        isRunningHotkeyTest = true
        hotkeyTestMessage = nil
        globalHotkeyService.stopMonitoring()

        var observedResult: HotkeyStartResult?
        let result = globalHotkeyService.startMonitoring(binding: binding, fallbackMode: fallbackMode) { [weak self] event in
            Task { @MainActor in
                self?.appendHotkeyRuntimeLog(event: event, overrideResult: observedResult)
                self?.hotkeyTestMessage = "Detected \(event.rawValue) for \(observedResult?.effectiveBinding.displayTitle ?? binding.displayTitle)."
                self?.hotkeyTestTask?.cancel()
                self?.isRunningHotkeyTest = false
                self?.configureHotkeyMonitoring()
            }
        }
        observedResult = result
        appendHotkeyRuntimeLog(event: nil, overrideResult: result)

        guard result.isActive else {
            isRunningHotkeyTest = false
            hotkeyTestMessage = result.message ?? "No global hotkey could be activated."
            configureHotkeyMonitoring()
            return
        }

        hotkeyTestMessage = "Background the app and hold \(result.effectiveBinding.displayTitle) to test the \(label) in the next 6 seconds."
        hotkeyTestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.isRunningHotkeyTest = false
                self?.hotkeyTestMessage = "\(binding.displayTitle) was not detected during the test window. Recommended fallback: \(result.recommendedFallback?.displayTitle ?? "none")."
                self?.configureHotkeyMonitoring()
            }
        }
    }

    private func appendHotkeyRuntimeLog(
        event: GlobalHotkeyEvent?,
        overrideResult: HotkeyStartResult? = nil
    ) {
        let result = overrideResult ?? activeHotkeyStartResult
        let selectedTitle = result?.originalBinding.displayTitle ?? interactionSettings.hotkeyBinding.displayTitle
        let effectiveTitle = result?.effectiveBinding.displayTitle ?? selectedTitle
        let backend = result?.backend ?? .unavailable
        let fallbackWasUsed = result?.fallbackWasUsed ?? false
        let permissionGranted = result?.permissionGranted ?? hotkeyPermissionGranted

        hotkeyRuntimeLogs.insert(
            HotkeyRuntimeLog(
                timestamp: Date(),
                selectedBindingTitle: selectedTitle,
                effectiveBindingTitle: effectiveTitle,
                backend: backend,
                fallbackWasUsed: fallbackWasUsed,
                permissionGranted: permissionGranted,
                event: event
            ),
            at: 0
        )
        if hotkeyRuntimeLogs.count > 20 {
            hotkeyRuntimeLogs.removeLast(hotkeyRuntimeLogs.count - 20)
        }
    }

    private func refreshRemoteModelsTask(apiKey: String) async {
        remoteModelsLoadState = .loading
        do {
            let available = try await transcriptionCoordinator.fetchRemoteModelIDs(apiKey: apiKey)
            guard !Task.isCancelled else { return }
            availableModelIDs = available
            rebuildModelRows(forceRemoteOnly: true)
            ensureSelectionsExist(available: available)
            remoteModelsLoadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            rebuildModelRows(forceRemoteOnly: !availableModelIDs.isEmpty)
            remoteModelsLoadState = .error(error.localizedDescription)
        }
    }

    private func ensureSelectionsExist(available: Set<String>) {
        let remoteTransDefaultID = "gpt-4o-mini-transcribe"
        let logicDefaultID = "gpt-5-mini"

        if let selected = ModelRegistry.entry(for: selectedRemoteModelID), !selected.isEnabled || !available.contains(selected.id) {
            if available.contains(remoteTransDefaultID) {
                selectedRemoteModelID = remoteTransDefaultID
            } else if let first = available.first(where: { ModelRegistry.entry(for: $0)?.role == .transcription }) {
                selectedRemoteModelID = first
            }
        }

        if let selected = ModelRegistry.entry(for: selectedRemoteLogicModelID), !selected.isEnabled || !available.contains(selected.id) {
            if available.contains(logicDefaultID) {
                selectedRemoteLogicModelID = logicDefaultID
            } else if let first = remoteLogicModels.first?.entry.id {
                selectedRemoteLogicModelID = first
            }
        }
    }

    private func rebuildModelRows(forceRemoteOnly: Bool = false) {
        let transcriptions = modelRegistryRows(
            role: .transcription,
            mode: .remote,
            includeAdvanced: showAdvancedTranscriptionModels,
            forceAvailability: forceRemoteOnly
        )

        let logic = modelRegistryRows(
            role: .logic,
            mode: .remote,
            includeAdvanced: false,
            forceAvailability: forceRemoteOnly
        )
        let localLogic = modelRegistryRows(
            role: .logic,
            mode: .local,
            includeAdvanced: false,
            forceAvailability: false
        )

        remoteTranscriptionModels = transcriptions
        remoteLogicModels = logic
        localLogicModels = localLogic

        if let selected = transcriptions.first(where: { $0.entry.id == selectedRemoteModelID }) {
            _ = selected
        }
        if let selected = logic.first(where: { $0.entry.id == selectedRemoteLogicModelID }) {
            _ = selected
        }

        applyTranscriptionModelSelectionDefaults()
    }

    private func modelRegistryRows(
        role: ModelRole,
        mode: EngineMode,
        includeAdvanced: Bool,
        forceAvailability: Bool
    ) -> [ModelAvailabilityRow] {
        let entries = ModelRegistry.entries(for: role, mode: mode, includeAdvanced: includeAdvanced)
        return entries.map { entry in
            let isAvailable = if mode == .remote && forceAvailability {
                forceAvailability ? availableModelIDs.contains(entry.id) : false
            } else {
                true
            }
            return ModelAvailabilityRow(entry: entry, isAvailable: isAvailable)
        }
    }

    private func reloadPromptProfiles() async {
        promptProfiles = await promptProfileStore.profiles()
    }

    private func makeFormattedOutput(from text: String) -> FormattedOutput {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let isBulleted = lines.count > 1 && lines.allSatisfy { line in
            line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") || line.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }

        let bullets = isBulleted
            ? lines.map { line in
                line
                    .replacingOccurrences(of: #"^[\-\*•]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            : []

        return FormattedOutput(
            clean_text: text,
            format: isBulleted ? "bullets" : "paragraph",
            bullets: bullets,
            self_corrections: [],
            low_confidence_spans: [],
            notes: []
        )
    }

    private func applyTranscriptionModelSelectionDefaults() {
        if transcriptionMode == .local {
            transcribeUseStream = false
            transcribePrompt = ""
            transcribeUseTimestamps = false
            transcribeUseDiarization = false
            transcribeUseLogprobs = false
            return
        }

        if let selected = selectedTranscriptionModel {
            if !selected.supportsStreaming {
                transcribeUseStream = false
            }
            if !selected.supportsPrompt {
                transcribePrompt = ""
            }
            if !selected.supportsTimestamps {
                transcribeUseTimestamps = false
            }
            if !selected.supportsDiarization {
                transcribeUseDiarization = false
                transcribeKnownSpeakerNamesText = ""
                transcribeKnownSpeakerReferencesText = ""
                transcribeChunkingStrategy = ""
            }
            if !selected.supportsLogprobs {
                transcribeUseLogprobs = false
            }

            if !selected.allowedResponseFormats.contains(transcribeResponseFormat) {
                transcribeResponseFormat = selected.allowedResponseFormats.first ?? "json"
            }

            if shouldForceDiarizedSpeakerOutput && transcribeResponseFormat != Self.diarizedJSONFormat {
                transcribeResponseFormat = Self.diarizedJSONFormat
            }
            return
        }

        if !ModelRegistry.supportedAudioExtensions.isEmpty,
           let fallback = ModelRegistry.entry(for: "gpt-4o-mini-transcribe") {
            selectedRemoteModelID = fallback.id
            transcribeResponseFormat = fallback.allowedResponseFormats.first ?? "json"
        }
    }

    private func applyLogicModeDefaults() {
        if logicMode == .local {
            logicSettings.flagLowConfidenceWords = false
            checkLocalLogicRuntime()
        }
    }

    private func enforceLocalOnlyDefaults() {
        transcriptionMode = .local
        logicMode = .local
        selectedLocalEngineMode = .appleSpeech
        selectedLocalModel = .appleOnDevice
    }

    private func makeTranscriptionSessionRequest() -> TranscriptionSessionRequest? {
        switch transcriptionMode {
        case .remote:
            guard let model = selectedTranscriptionModel else {
                return nil
            }
            let options = makeTranscriptionRequestOptions(for: model)
            return TranscriptionSessionRequest(
                mode: .remote,
                localModel: selectedLocalModel,
                options: options,
                interactionSettings: interactionSettings,
                recordingSessionContext: activeRecordingSessionContext
            )
        case .local:
            let options = TranscriptionOptions(
                modelID: selectedLocalModel.rawValue,
                apiKey: nil,
                responseFormat: "text",
                includeLogprobs: false,
                prompt: nil,
                stream: false,
                timestampGranularities: [],
                diarizationEnabled: false,
                languageHint: nil,
                chunkingStrategy: nil,
                knownSpeakerNames: [],
                knownSpeakerReferences: [],
                localEngineMode: selectedLocalEngineMode,
                whisperKitServerConnectionMode: selectedWhisperServerConnectionMode,
                whisperKitServerBaseURL: whisperServerBaseURL
            )
            return TranscriptionSessionRequest(
                mode: .local,
                localModel: selectedLocalModel,
                options: options,
                interactionSettings: interactionSettings,
                recordingSessionContext: activeRecordingSessionContext
            )
        }
    }

    private func makeTranscriptionRequestOptions(for model: ModelRegistryEntry) -> TranscriptionRequestOptions {
        let audioFormat = transcribeResponseFormat
        let requestedResponseFormat = model.allowedResponseFormats.contains(audioFormat) ? audioFormat : model.allowedResponseFormats.first ?? "json"

        return TranscriptionRequestOptions(
            modelID: model.id,
            apiKey: effectiveApiKey,
            responseFormat: requestedResponseFormat,
            includeLogprobs: model.supportsLogprobs ? transcribeUseLogprobs : false,
            prompt: model.supportsPrompt ? transcribePrompt : nil,
            stream: model.supportsStreaming ? transcribeUseStream : false,
            timestampGranularities: (model.supportsTimestamps && transcribeUseTimestamps) ? ["segment"] : [],
            diarizationEnabled: model.supportsDiarization ? transcribeUseDiarization : false,
            languageHint: nil,
            chunkingStrategy: model.supportsDiarization && transcribeUseDiarization
                ? normalizedChunkingStrategy(for: transcribeChunkingStrategy) : nil,
            knownSpeakerNames: model.supportsDiarization && transcribeUseDiarization
                ? parseSpeakerNames(from: transcribeKnownSpeakerNamesText) : [],
            knownSpeakerReferences: model.supportsDiarization && transcribeUseDiarization
                ? parseSpeakerReferences(from: transcribeKnownSpeakerReferencesText) : []
        )
    }

    private func applySavedState() {
        var loadedInteractionSettings = false

        if let savedMode = UserDefaults.standard.string(forKey: Self.savedTranscriptionModeDefaultsKey),
           let mode = TranscriptionMode(rawValue: savedMode) {
            transcriptionMode = mode
        }

        if let savedSection = UserDefaults.standard.string(forKey: Self.savedSectionDefaultsKey),
           let section = AppSection(rawValue: savedSection) {
            selectedSection = section
        }

        if let savedLocalModel = UserDefaults.standard.string(forKey: Self.savedLocalModelDefaultsKey),
           let localModel = LocalTranscriptionModel(rawValue: savedLocalModel) {
            selectedLocalModel = localModel
        }
        if let savedLocalEngineMode = UserDefaults.standard.string(forKey: Self.savedLocalEngineModeDefaultsKey),
           let localEngineMode = LocalTranscriptionEngineMode.persistedValue(savedLocalEngineMode, selectedModel: selectedLocalModel) {
            selectedLocalEngineMode = localEngineMode
        }

        if let savedRemoteModel = UserDefaults.standard.string(forKey: Self.savedRemoteModelDefaultsKey),
           !savedRemoteModel.isEmpty {
            selectedRemoteModelID = savedRemoteModel
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacySavedModelDefaultsKey),
                  !legacy.isEmpty {
            selectedRemoteModelID = legacy
        }

        if let transcribeFormat = UserDefaults.standard.string(forKey: Self.savedTranscriptionResponseFormatKey) {
            transcribeResponseFormat = transcribeFormat
        }
        if let savedShowAdvanced = UserDefaults.standard.object(forKey: Self.savedShowAdvancedRemoteModelsDefaultsKey) as? Bool {
            showAdvancedTranscriptionModels = savedShowAdvanced
        }

        if let savedPrompt = UserDefaults.standard.string(forKey: Self.savedTranscriptionPromptKey) {
            transcribePrompt = savedPrompt
        }
        transcribeKnownSpeakerNamesText = UserDefaults.standard.string(forKey: Self.savedTranscriptionKnownSpeakerNamesKey) ?? ""
        transcribeKnownSpeakerReferencesText = UserDefaults.standard.string(forKey: Self.savedTranscriptionKnownSpeakerReferencesKey) ?? ""
        transcribeChunkingStrategy = UserDefaults.standard.string(forKey: Self.savedTranscriptionChunkingStrategyKey) ?? ""
        transcribeUseLogprobs = UserDefaults.standard.bool(forKey: Self.savedTranscriptionUseLogprobsKey)
        transcribeUseStream = UserDefaults.standard.bool(forKey: Self.savedTranscriptionUseStreamKey)
        transcribeUseTimestamps = UserDefaults.standard.bool(forKey: Self.savedTranscriptionUseTimestampsKey)
        transcribeUseDiarization = UserDefaults.standard.bool(forKey: Self.savedTranscriptionUseDiarizationKey)

        if let savedRemoteLogicMode = UserDefaults.standard.string(forKey: Self.savedLogicModeDefaultsKey),
           let mode = LogicMode(rawValue: savedRemoteLogicMode) {
            logicMode = mode
        }

        if let savedRemoteLogicModel = UserDefaults.standard.string(forKey: Self.savedRemoteLogicModelDefaultsKey),
           !savedRemoteLogicModel.isEmpty {
            selectedRemoteLogicModelID = savedRemoteLogicModel
        }
        if let savedLocalLogicModel = UserDefaults.standard.string(forKey: Self.savedLocalLogicModelDefaultsKey),
           !savedLocalLogicModel.isEmpty {
            selectedLocalLogicModelID = savedLocalLogicModel
        }

        if let savedAutoFormat = UserDefaults.standard.object(forKey: Self.savedAutoFormatDefaultsKey) as? Bool {
            autoFormatEnabled = savedAutoFormat
        }

        if let savedAppearanceMode = UserDefaults.standard.string(forKey: Self.savedAppearanceModeDefaultsKey),
           let mode = AppAppearanceMode(rawValue: savedAppearanceMode) {
            appearanceMode = mode
        }

        if let logicSettingsData = UserDefaults.standard.data(forKey: Self.savedLogicSettingsKey),
           let decoded = try? JSONDecoder().decode(LogicSettings.self, from: logicSettingsData) {
            logicSettings = decoded
        }

        if let refineSettingsData = UserDefaults.standard.data(forKey: Self.savedRefineSettingsKey),
           let decoded = try? JSONDecoder().decode(RefineSettings.self, from: refineSettingsData) {
            refineSettings = decoded
        }

        if let interactionSettingsData = UserDefaults.standard.data(forKey: Self.savedInteractionSettingsKey),
           let decoded = try? JSONDecoder().decode(InteractionSettings.self, from: interactionSettingsData) {
            interactionSettings = decoded
            loadedInteractionSettings = true
        }

        if !loadedInteractionSettings && refineSettings.autoPasteAfterInsert {
            interactionSettings.autoPasteAfterInsert = true
        }
    }

    private var blockedStartMessage: String {
        switch transcriptionMode {
        case .remote:
            if effectiveApiKey == nil {
                return "No OpenAI API key is configured. Add it in Settings."
            }
            if !isSelectedRemoteModelAvailable {
                return "Selected remote transcription model is not available. Refresh remote models first."
            }
            return "Select a remote transcription model in Settings."
        case .local:
            switch selectedLocalEngineMode {
            case .appleSpeech:
                switch microphoneAuthorizationStatus {
                case .denied, .restricted:
                    return AudioRecorderError.microphonePermissionDenied.localizedDescription
                case .authorized, .notDetermined:
                    break
                @unknown default:
                    return "Microphone permission is unavailable."
                }

                switch speechAuthorizationStatus {
                case .denied:
                    return LocalTranscriptionError.speechPermissionDenied.localizedDescription
                case .restricted:
                    return LocalTranscriptionError.speechPermissionRestricted.localizedDescription
                case .authorized, .notDetermined:
                    break
                @unknown default:
                    return "Speech recognition permission is unavailable."
                }

                return appleSpeechRuntimeStatus.message
            case .whisperKit:
                guard whisperRuntimeStatus.isAvailable else {
                    return whisperRuntimeStatus.message
                }

                switch localWhisperInstallState(for: selectedLocalModel) {
                case .notDownloaded:
                    return "\(selectedLocalModel.title) is not downloaded yet."
                case .downloading:
                    return "Downloading \(selectedLocalModel.title)…"
                case .downloaded:
                    return "\(selectedLocalModel.title) is downloaded and ready to install."
                case .installing:
                    return "Installing \(selectedLocalModel.title)…"
                case .ready:
                    return "WhisperKit is ready."
                case .failed(let message):
                    return message
                }
            case .legacyWhisper:
                guard legacyWhisperRuntimeStatus.isAvailable else {
                    return legacyWhisperRuntimeStatus.message
                }
                switch legacyWhisperInstallState(for: selectedLocalModel) {
                case .notDownloaded:
                    return "\(selectedLocalModel.title) is not installed for legacy Whisper."
                case .downloading:
                    return "\(selectedLocalModel.title) is preparing for legacy Whisper."
                case .downloaded:
                    return "\(selectedLocalModel.title) is staged and needs legacy installation."
                case .installing:
                    return "Installing \(selectedLocalModel.title) for legacy Whisper…"
                case .ready:
                    return "Legacy Whisper is ready."
                case .failed(let message):
                    return message
                }
            }
        }
    }

    private var idleStatusMessage: String {
        switch transcriptionMode {
        case .remote:
            if effectiveApiKey == nil {
                return "Set an OpenAI API key in Settings."
            }
            if selectedRemoteModelID.isEmpty || !isSelectedRemoteModelAvailable {
                return "Select a remote transcription model in Settings."
            }
            return "Ready to record with remote transcription."
        case .local:
            switch selectedLocalEngineMode {
            case .appleSpeech:
                if appleSpeechRuntimeStatus.isReady {
                    return "Ready to record with Apple Dictation."
                }
                return blockedStartMessage
            case .whisperKit:
                guard whisperRuntimeStatus.isAvailable else {
                    return whisperRuntimeStatus.message
                }
                switch localWhisperInstallState(for: selectedLocalModel) {
                case .notDownloaded:
                    return "\(selectedLocalModel.title) is not downloaded yet."
                case .downloading:
                    return "Downloading \(selectedLocalModel.title)…"
                case .downloaded:
                    return "\(selectedLocalModel.title) is downloaded and ready to install."
                case .installing:
                    return "Installing \(selectedLocalModel.title)…"
                case .ready:
                    return "Ready to record with \(selectedLocalModel.title)."
                case .failed(let message):
                    return message
                }
            case .legacyWhisper:
                guard legacyWhisperRuntimeStatus.isAvailable else {
                    return legacyWhisperRuntimeStatus.message
                }
                switch legacyWhisperInstallState(for: selectedLocalModel) {
                case .ready:
                    return "Ready to record with legacy Whisper."
                case .failed(let message):
                    return message
                case .notDownloaded:
                    return "\(selectedLocalModel.title) is not installed for legacy Whisper."
                case .downloading:
                    return "\(selectedLocalModel.title) is preparing for legacy Whisper."
                case .downloaded:
                    return "\(selectedLocalModel.title) is staged and needs legacy installation."
                case .installing:
                    return "Installing \(selectedLocalModel.title) for legacy Whisper…"
                }
            }
        }
    }

    private var sanitizedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var environmentApiKey: String? {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var storedApiKey: String {
        UserDefaults.standard.string(forKey: Self.savedApiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func persistLogicSettings() {
        guard let data = try? JSONEncoder().encode(logicSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedLogicSettingsKey)
    }

    private func persistRefineSettings() {
        guard let data = try? JSONEncoder().encode(refineSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedRefineSettingsKey)
    }

    private func migrateLegacyGlossaryIfNeeded() {
        let persistedEntries = transcriptRecordStore.fetchDictionaryEntries()
        if !persistedEntries.isEmpty {
            if !refineSettings.glossary.isEmpty {
                refineSettings.glossary = []
            }
            return
        }

        let legacyEntries = refineSettings.glossary
        guard !legacyEntries.isEmpty else { return }
        transcriptRecordStore.replaceDictionaryEntries(legacyEntries)
        refineSettings.glossary = []
    }

    private func persistInteractionSettings() {
        guard let data = try? JSONEncoder().encode(interactionSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedInteractionSettingsKey)
    }

    private var resultModelIDForDiagnostics: String {
        switch transcriptionMode {
        case .remote:
            return selectedRemoteModelID
        case .local:
            return selectedLocalModel.rawValue
        }
    }

    private var selectedTranscriptionEngineIDForDiagnostics: String {
        switch transcriptionMode {
        case .remote:
            return "openai-batch-sse"
        case .local:
            return currentLocalTranscriptionEngineID
        }
    }

    private var selectedLogicModelIDForDiagnostics: String {
        switch logicMode {
        case .remote:
            return selectedRemoteLogicModelID
        case .local:
            return selectedLocalLogicModelID
        }
    }

    private func appendDiagnosticSession(_ record: DiagnosticSessionRecord) {
        transcriptRecordStore.appendDiagnosticSession(record)
    }

    private func localWhisperInstallState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        whisperModelInstallStates[model] ?? .notDownloaded
    }

    private func legacyWhisperInstallState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        legacyWhisperInstallStates[model] ?? .notDownloaded
    }

    private func activeWhisperLifecycleState(for model: LocalTranscriptionModel) -> WhisperModelInstallState {
        switch selectedLocalEngineMode {
        case .appleSpeech, .whisperKit:
            return localWhisperInstallState(for: model)
        case .legacyWhisper:
            return legacyWhisperInstallState(for: model)
        }
    }

    private var currentLocalTranscriptionEngineID: String {
        switch selectedLocalEngineMode {
        case .appleSpeech:
            return LocalTranscriptionBackend.appleSpeech.engineID
        case .whisperKit:
            return LocalTranscriptionBackend.whisperKitSDK.engineID
        case .legacyWhisper:
            return LocalTranscriptionBackend.whisperCpp.engineID
        }
    }

    func localModelBadgeText(_ model: LocalTranscriptionModel) -> String {
        if model.isAppleModel {
            switch appleSpeechRuntimeStatus.lifecycleState {
            case .ready:
                return "Ready"
            case .installRequired:
                return "Install"
            case .installing:
                return "Installing"
            case .failed:
                return appleSpeechRuntimeStatus.canInstallAssets ? "Retry" : "Issue"
            case .unsupportedLocale, .unavailable:
                return "Unavailable"
            }
        }

        let state = activeWhisperLifecycleState(for: model)
        let runtimeSupported = selectedLocalEngineMode == .legacyWhisper
            ? legacyWhisperRuntimeStatus.isSupported
            : whisperRuntimeStatus.isSupported
        guard runtimeSupported else {
            return "Unavailable"
        }

        switch state {
        case .notDownloaded:
            return selectedLocalEngineMode == .legacyWhisper ? "Unavailable" : "Download"
        case .downloading:
            return selectedLocalEngineMode == .legacyWhisper ? "Unavailable" : "Downloading"
        case .downloaded:
            return selectedLocalEngineMode == .legacyWhisper ? "Unavailable" : "Install"
        case .installing:
            return selectedLocalEngineMode == .legacyWhisper ? "Unavailable" : "Installing"
        case .ready:
            return selectedLocalModel == model ? "Ready" : "Installed"
        case .failed:
            return selectedLocalEngineMode == .legacyWhisper ? "Unavailable" : "Retry"
        }
    }

    func localModelNotes(_ model: LocalTranscriptionModel) -> String {
        if model.isAppleModel {
            return localTranscriptionRuntimeStatusMessage
        }

        let state = activeWhisperLifecycleState(for: model)
        let runtimeSupported = selectedLocalEngineMode == .legacyWhisper
            ? legacyWhisperRuntimeStatus.isSupported
            : whisperRuntimeStatus.isSupported
        guard runtimeSupported else {
            return "Apple Silicon required."
        }

        switch state {
        case .notDownloaded:
            if selectedLocalEngineMode == .legacyWhisper {
                return "Legacy whisper.cpp model files are not installed for this model."
            }
            return model.recommendedForFirstDownload
                ? "Recommended first download."
                : model.detail + (model == .whisperMedium || model == .whisperLargeV3 ? " Heavier model." : "")
        case .downloading:
            return selectedLocalEngineMode == .legacyWhisper
                ? "Legacy whisper.cpp setup is incomplete for this model."
                : "Model download in progress."
        case .downloaded:
            return selectedLocalEngineMode == .legacyWhisper
                ? "Legacy whisper.cpp setup is incomplete for this model."
                : "Download complete. Install to make it available for transcription."
        case .installing:
            return selectedLocalEngineMode == .legacyWhisper
                ? "Legacy whisper.cpp setup is incomplete for this model."
                : "Finalizing local model setup."
        case .ready:
            if selectedLocalEngineMode == .legacyWhisper {
                return "Installed for offline transcription with whisper.cpp."
            }
            return "Installed for offline transcription."
        case .failed(let message):
            return message
        }
    }

    func localModelPrimaryActionTitle(_ model: LocalTranscriptionModel) -> String? {
        if model.isAppleModel {
            return appleSpeechPrimaryActionTitle
        }

        guard model.isWhisperModel else { return nil }
        guard selectedLocalEngineMode == .whisperKit else { return nil }
        guard whisperRuntimeStatus.isAvailable else { return nil }

        switch localWhisperInstallState(for: model) {
        case .notDownloaded:
            return "Download"
        case .downloaded:
            return "Install"
        case .failed:
            return "Retry"
        case .downloading, .installing, .ready:
            return nil
        }
    }

    func canRunLocalModelPrimaryAction(_ model: LocalTranscriptionModel) -> Bool {
        if model.isAppleModel {
            return canInstallAppleSpeechAssets
        }

        guard model.isWhisperModel else { return false }
        guard selectedLocalEngineMode == .whisperKit else { return false }
        guard whisperRuntimeStatus.isAvailable else { return false }
        return !localWhisperInstallState(for: model).isBusy && localModelPrimaryActionTitle(model) != nil
    }

    func canRemoveLocalModel(_ model: LocalTranscriptionModel) -> Bool {
        guard model.isWhisperModel else { return false }
        guard selectedLocalEngineMode == .whisperKit else { return false }
        switch localWhisperInstallState(for: model) {
        case .downloaded, .ready, .failed:
            return true
        case .notDownloaded, .downloading, .installing:
            return false
        }
    }

    func localModelProgressValue(_ model: LocalTranscriptionModel) -> Double? {
        if model.isAppleModel {
            return appleSpeechInstallProgressValue
        }
        guard selectedLocalEngineMode == .whisperKit else { return nil }
        switch localWhisperInstallState(for: model) {
        case .downloading(let progress):
            return progress
        case .installing:
            return nil
        case .notDownloaded, .downloaded, .ready, .failed:
            return nil
        }
    }

    func localWhisperInstallStateDescription(_ model: LocalTranscriptionModel) -> LocalWhisperInstallStateDescription {
        if model.isAppleModel {
            if appleSpeechRuntimeStatus.isInstallingAssets {
                return .progress(appleSpeechRuntimeStatus.message)
            }
            return .none
        }
        guard selectedLocalEngineMode == .whisperKit else {
            return .none
        }
        switch localWhisperInstallState(for: model) {
        case .downloading:
            return .progress("Downloading \(model.title)…")
        case .installing:
            return .progress("Installing \(model.title)…")
        case .notDownloaded, .downloaded, .ready, .failed:
            return .none
        }
    }

    func isLocalModelSelectable(_ model: LocalTranscriptionModel) -> Bool {
        if model.isAppleModel {
            return true
        }
        switch selectedLocalEngineMode {
        case .appleSpeech, .whisperKit:
            return whisperRuntimeStatus.isSupported
        case .legacyWhisper:
            return legacyWhisperRuntimeStatus.isSupported
        }
    }

    private var effectiveApiKey: String? {
        if !sanitizedApiKey.isEmpty {
            return sanitizedApiKey
        }
        if let env = environmentApiKey, !env.isEmpty {
            return env
        }
        if !storedApiKey.isEmpty {
            return storedApiKey
        }
        return nil
    }

    private func parseSpeakerNames(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { line in
                line
                    .components(separatedBy: ",")
                    .map { item in item.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty }
    }

    private func parseSpeakerReferences(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines)
            .map { item in item.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedChunkingStrategy(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}
