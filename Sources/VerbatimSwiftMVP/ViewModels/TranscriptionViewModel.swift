import Foundation
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

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var transcript: Transcript? = nil
    @Published private(set) var formattedOutput: FormattedOutput? = nil
    @Published private(set) var deterministicResult: DeterministicResult? = nil
    @Published private(set) var latestLLMResult: LLMResult? = nil
    @Published private(set) var promptProfiles: [PromptProfile] = []
    @Published private(set) var transcriptHistory: [TranscriptRecord] = []
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
    @Published private(set) var isCapturingHotkey: Bool = false

    @Published var selectedSection: AppSection = .home {
        didSet {
            UserDefaults.standard.set(selectedSection.rawValue, forKey: Self.savedSectionDefaultsKey)
        }
    }

    @Published var transcriptionMode: TranscriptionMode = .remote {
        didSet {
            UserDefaults.standard.set(transcriptionMode.rawValue, forKey: Self.savedTranscriptionModeDefaultsKey)
            applyTranscriptionModelSelectionDefaults()
            if transcriptionMode == .remote {
                refreshRemoteModels()
            }
        }
    }

    @Published var selectedLocalModel: LocalTranscriptionModel = .appleOnDevice {
        didSet {
            UserDefaults.standard.set(selectedLocalModel.rawValue, forKey: Self.savedLocalModelDefaultsKey)
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
    @Published private(set) var remoteLogicModels: [ModelAvailabilityRow] = []
    @Published private(set) var localLogicModels: [ModelAvailabilityRow] = []
    @Published private(set) var localLogicRuntimeLoadState: LocalLogicRuntimeLoadState = .idle
    @Published private(set) var localLogicAvailableModels: [String] = []

    @Published var logicMode: LogicMode = .remote {
        didSet {
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

    @Published private(set) var availableModelIDs: Set<String> = []

    private let transcriptionCoordinator: TranscriptionCoordinator
    private let localLogicService: OllamaLocalLogicService
    private let promptProfileStore: PromptProfileStore
    private let transcriptRecordStore: TranscriptRecordStoreProtocol
    private let postTranscriptionPipeline: PostTranscriptionPipeline
    private let activeAppContextService: ActiveAppContextServiceProtocol
    private let insertionService: InsertionServiceProtocol
    private let globalHotkeyService: GlobalHotkeyServiceProtocol
    private let listeningIndicatorService: ListeningIndicatorServiceProtocol
    private let soundCueService: SoundCueServiceProtocol
    private var remoteModelTask: Task<Void, Never>?
    private var localLogicRuntimeTask: Task<Void, Never>?
    private var hotkeyIsPressed = false
    private var pendingDoubleTapDate: Date?
    private var hasRequestedAccessibilityPrompt = false
    private var shouldForceInsertionForCurrentRecording = false
    private var recordingAppContextOverride: ActiveAppContext?
    private var insertionTargetForCurrentRecording: InsertionTarget?
#if canImport(AppKit)
    private var hotkeyCaptureLocalMonitor: Any?
#endif

    private static let savedApiKeyDefaultsKey = "VerbatimSwiftMVP.OpenAIAPIKey"
    private static let savedTranscriptionModeDefaultsKey = "VerbatimSwiftMVP.TranscriptionMode"
    private static let savedRemoteModelDefaultsKey = "VerbatimSwiftMVP.RemoteModelID"
    private static let savedLocalModelDefaultsKey = "VerbatimSwiftMVP.LocalModelID"
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
        localTranscriptionService: LocalTranscriptionServiceProtocol = AppleLocalTranscriptionService(),
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
                localEngine: localTranscriptionService,
                modelCatalogService: resolvedModelCatalogService
            )
        self.localLogicService = localLogicService
        self.promptProfileStore = promptProfileStore
        self.transcriptRecordStore = transcriptRecordStore
        self.activeAppContextService = activeAppContextService
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
        reloadTranscriptHistory()
        rebuildModelRows()
        applyTranscriptionModelSelectionDefaults()
        applyLogicModeDefaults()

        if isAnyRemoteModeEnabled && effectiveApiKey != nil {
            refreshRemoteModels()
        }
        if logicMode == .local {
            checkLocalLogicRuntime()
        }
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
            if let summary = lastErrorSummary, !summary.isEmpty {
                return "Raw transcript ready. Formatting warning: \(summary)"
            }
            return "Transcript ready."
        case .error(let message):
            return "Error: \(message)"
        }
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

    var canStartForCurrentMode: Bool {
        switch transcriptionMode {
        case .remote:
            return effectiveApiKey != nil && selectedTranscriptionModel != nil && isSelectedRemoteModelAvailable
        case .local:
            return selectedLocalModel.isImplemented
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
        if logicMode == .remote {
            guard let logicModel = selectedLogicModel else { return false }
            return logicModel.isEnabled && availableModelIDs.contains(logicModel.id)
        }
        if logicMode == .local {
            guard let logicModel = selectedLogicModel else { return false }
            return logicModel.isEnabled
        }
        return false
    }

    var canConfigureReasoningEffort: Bool {
        guard let modelID = selectedLogicModel?.id else { return false }
        switch logicMode {
        case .remote:
            return modelID.hasPrefix("gpt-5")
        case .local:
            return modelID.hasPrefix("gpt-oss")
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
        if fromHotkey {
            let activeContext = activeAppContextService.currentContext()
            recordingAppContextOverride = activeContext
            insertionTargetForCurrentRecording = activeContext.insertionTarget
        } else {
            recordingAppContextOverride = nil
            insertionTargetForCurrentRecording = nil
        }

        Task {
            do {
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
        let activeAppContextOverride = recordingAppContextOverride
        let insertionTarget = insertionTargetForCurrentRecording
        shouldForceInsertionForCurrentRecording = false
        recordingAppContextOverride = nil
        insertionTargetForCurrentRecording = nil
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
                    case .transcript(_, let snapshot):
                        transcript = snapshot.currentTranscript
                        if let authoritative = snapshot.finalTranscript {
                            finalTranscript = authoritative
                        }
                    }
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
                        activeAppContextOverride: activeAppContextOverride,
                        insertionTarget: insertionTarget,
                        promptProfiles: promptProfiles,
                        logicMode: logicMode,
                        logicSettings: logicSettings,
                        refineSettings: refineSettings,
                        interactionSettings: interactionSettings,
                        autoFormatEnabled: autoFormatEnabled,
                        canRunAutoFormat: canRunAutoFormat,
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
                lastErrorSummary = pipelineResult.lastErrorSummary
                selectedTranscriptViewMode = .formatted
                reloadTranscriptHistory()
                if interactionSettings.showListeningIndicator {
                    listeningIndicatorService.showCompletedBriefly()
                } else {
                    listeningIndicatorService.hideListening()
                }

                state = .done
            } catch {
                listeningIndicatorService.hideListening()
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
        try? insertionService.insert(text: text, autoPaste: false, target: nil)
    }

    func copyTranscriptRecord(_ record: TranscriptRecord) {
        let text = preferredTranscriptText(for: record)
        guard !text.isEmpty else { return }
        try? insertionService.insert(text: text, autoPaste: false, target: nil)
    }

    func copyRawTranscriptRecord(_ record: TranscriptRecord) {
        let text = record.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? insertionService.insert(text: text, autoPaste: false, target: nil)
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

        try? insertionService.insert(text: payload, autoPaste: false, target: nil)
    }

    func reloadTranscriptHistory(limit: Int = 200) {
        transcriptHistory = transcriptRecordStore.fetchRecentRecords(limit: limit)
    }

    func preferredTranscriptText(for record: TranscriptRecord) -> String {
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
        try? insertionService.insert(text: rendered, autoPaste: interactionSettings.autoPasteAfterInsert, target: nil)
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
            hotkeyStatusMessage = "Accessibility access is required for Fn / Globe hotkeys. macOS should open the permission prompt."
        }
    }

    private func configureHotkeyMonitoring() {
        globalHotkeyService.stopMonitoring()
        hotkeyPermissionGranted = globalHotkeyService.hasAccessibilityPermission()

        guard !isCapturingHotkey else {
            hotkeyStatusMessage = "Press a key combination or a modifier key (Fn supported)."
            return
        }

        guard interactionSettings.hotkeyEnabled else {
            hotkeyStatusMessage = "Hotkey monitoring is off."
            return
        }

        guard interactionSettings.hotkeyBinding.isValidGlobalHotkey else {
            hotkeyStatusMessage = "Select a hotkey with at least one modifier, or use Fn by itself."
            return
        }

        if !hotkeyPermissionGranted && !hasRequestedAccessibilityPrompt {
            hotkeyPermissionGranted = globalHotkeyService.requestAccessibilityPermissionPrompt()
            hasRequestedAccessibilityPrompt = true
        }

        guard hotkeyPermissionGranted else {
            hotkeyStatusMessage = "Enable Accessibility access to use Fn / Globe hotkeys."
            return
        }

        let config = GlobalHotkeyConfig(
            keyCode: interactionSettings.hotkeyBinding.keyCode,
            modifierFlagsRawValue: interactionSettings.hotkeyBinding.modifierFlagsRawValue,
            modifierKeyRawValue: interactionSettings.hotkeyBinding.modifierKeyRawValue
        )

        globalHotkeyService.startMonitoring(config: config) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyEvent(event)
            }
        }

        hotkeyStatusMessage = "Hotkey active: \(interactionSettings.hotkeyBinding.displayTitle) • \(hotkeyBehaviorSummary)"
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
        guard binding.isValidGlobalHotkey else {
            hotkeyStatusMessage = "Use at least one modifier, or use Fn by itself."
            return true
        }

        teardownHotkeyCapture()
        interactionSettings.hotkeyBinding = binding
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
                options: options
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
                knownSpeakerReferences: []
            )
            return TranscriptionSessionRequest(
                mode: .local,
                localModel: selectedLocalModel,
                options: options
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
            return "\(selectedLocalModel.title) is coming soon. Choose Apple On-Device."
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
            if !selectedLocalModel.isImplemented {
                return "\(selectedLocalModel.title) is coming soon."
            }
            return "Ready to record with local transcription."
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

    private func persistInteractionSettings() {
        guard let data = try? JSONEncoder().encode(interactionSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedInteractionSettingsKey)
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
