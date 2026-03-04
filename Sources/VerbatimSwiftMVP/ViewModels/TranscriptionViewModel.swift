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

@MainActor
@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class TranscriptionViewModel: ObservableObject {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var transcript: Transcript? = nil
    @Published private(set) var formattedOutput: FormattedOutput? = nil
    @Published var selectedTranscriptViewMode: TranscriptViewMode = .raw
    @Published var apiKey: String = ""

    @Published var selectedSection: AppSection = .workspace {
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

    @Published var lastErrorSummary: String?

    @Published private(set) var availableModelIDs: Set<String> = []

    private let recorder = AudioRecorderService()
    private let transcriptionService: TranscriptionServiceProtocol
    private let localTranscriptionService: LocalTranscriptionServiceProtocol
    private let logicService: LogicServiceProtocol
    private let localLogicService: OllamaLocalLogicService
    private let modelCatalogService: OpenAIModelCatalogService
    private var remoteModelTask: Task<Void, Never>?
    private var localLogicRuntimeTask: Task<Void, Never>?

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
    private static let savedLogicSettingsKey = "VerbatimSwiftMVP.LogicSettingsV1"
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
        logicService: LogicServiceProtocol = OpenAILogicService(),
        localLogicService: OllamaLocalLogicService = OllamaLocalLogicService(),
        modelCatalogService: OpenAIModelCatalogService = OpenAIModelCatalogService()
    ) {
        self.transcriptionService = transcriptionService
        self.localTranscriptionService = localTranscriptionService
        self.logicService = logicService
        self.localLogicService = localLogicService
        self.modelCatalogService = modelCatalogService

        apiKey = UserDefaults.standard.string(forKey: Self.savedApiKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applySavedState()
        rebuildModelRows()
        applyTranscriptionModelSelectionDefaults()
        applyLogicModeDefaults()

        if isAnyRemoteModeEnabled && effectiveApiKey != nil {
            refreshRemoteModels()
        }
        if logicMode == .local {
            checkLocalLogicRuntime()
        }
    }

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
        guard logicMode == .remote, let modelID = selectedLogicModel?.id else { return false }
        return modelID.hasPrefix("gpt-5")
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

    func start() {
        guard canStartForCurrentMode else {
            state = .error(blockedStartMessage)
            return
        }
        if case .recording = state { return }
        if isBusy {
            return
        }

        Task {
            state = .recording
            do {
                try await recorder.startRecording()
            } catch {
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

        Task {
            state = .transcribing
            lastErrorSummary = nil
            var outputURL: URL?

            do {
                outputURL = try await recorder.stopRecording()
                guard let audioURL = outputURL else {
                    state = .error("No recording file to transcribe.")
                    return
                }

                let result: Transcript
                switch transcriptionMode {
                case .remote:
                    guard let selectedTranscriptionModel else {
                        state = .error("Select a remote transcription model.")
                        return
                    }
                    let options = makeTranscriptionRequestOptions(for: selectedTranscriptionModel)
                    result = try await transcriptionService.transcribe(audioFileURL: audioURL, apiKey: effectiveApiKey, options: options)
                case .local:
                    result = try await localTranscriptionService.transcribeLocally(audioFileURL: audioURL, model: selectedLocalModel)
                }

                transcript = result
                formattedOutput = nil

                if autoFormatEnabled && canRunAutoFormat, let transcript = transcript {
                    state = .formatting
                    do {
                        if logicMode == .remote {
                            let formatted = try await logicService.format(
                                transcript: transcript,
                                apiKey: effectiveApiKey,
                                modelID: selectedRemoteLogicModelID,
                                settings: logicSettings
                            )
                            formattedOutput = formatted
                            selectedTranscriptViewMode = .formatted
                        } else {
                            let formatted = try await localLogicService.format(
                                transcript: transcript,
                                modelID: selectedLocalLogicModelID,
                                settings: logicSettings
                            )
                            formattedOutput = formatted
                            selectedTranscriptViewMode = .formatted
                        }
                        state = .done
                    } catch {
                        if let logicError = error as? OpenAILogicError {
                            lastErrorSummary = logicError.localizedDescription
                        } else if let localLogicError = error as? LocalLogicError {
                            lastErrorSummary = localLogicError.localizedDescription
                        } else {
                            lastErrorSummary = error.localizedDescription
                        }
                        state = .done
                    }
                } else {
                    state = .done
                }
            } catch {
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

            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
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
        let text = selectedTranscriptViewMode == .formatted ? (formattedOutput?.clean_text ?? transcriptText) : transcriptText
        guard !text.isEmpty else { return }

#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = text
#endif
    }

    func clearTranscript() {
        transcript = nil
        formattedOutput = nil
        lastErrorSummary = nil
        selectedTranscriptViewMode = .raw
        if case .done = state {
            state = .idle
        }
    }

    private func refreshRemoteModelsTask(apiKey: String) async {
        remoteModelsLoadState = .loading
        do {
            let available = try await modelCatalogService.fetchRemoteModelIDs(apiKey: apiKey)
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

    private func makeTranscriptionRequestOptions(for model: ModelRegistryEntry) -> TranscriptionRequestOptions {
        let audioFormat = transcribeResponseFormat
        let requestedResponseFormat = model.allowedResponseFormats.contains(audioFormat) ? audioFormat : model.allowedResponseFormats.first ?? "json"

        return TranscriptionRequestOptions(
            modelID: model.id,
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

        if let logicSettingsData = UserDefaults.standard.data(forKey: Self.savedLogicSettingsKey),
           let decoded = try? JSONDecoder().decode(LogicSettings.self, from: logicSettingsData) {
            logicSettings = decoded
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
