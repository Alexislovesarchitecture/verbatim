#if canImport(Combine)
import Combine
#endif
import Foundation
import OSLog
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            settingsStore.replace(settings)
            let providerConfigurationChanged =
                oldValue.selectedProvider != settings.selectedProvider ||
                oldValue.preferredLanguageID != settings.preferredLanguageID ||
                oldValue.selectedWhisperModelID != settings.selectedWhisperModelID ||
                oldValue.selectedParakeetModelID != settings.selectedParakeetModelID

            if providerConfigurationChanged {
                let whisperChanged = oldValue.selectedWhisperModelID != settings.selectedWhisperModelID
                let parakeetChanged = oldValue.selectedParakeetModelID != settings.selectedParakeetModelID
                let providerChanged = oldValue.selectedProvider != settings.selectedProvider
                Task {
                    if whisperChanged || providerChanged {
                        try? await whisperRuntimeManager.stop()
                    }
                    if parakeetChanged || providerChanged {
                        try? await parakeetRuntimeManager.stop()
                    }
                    await refreshProviderState()
                }
            }
            if oldValue.hotkey != settings.hotkey {
                configureHotkey()
            }
            if oldValue.menuBarEnabled != settings.menuBarEnabled {
                statusItemController.setVisible(settings.menuBarEnabled)
            }
            if oldValue.showOverlay != settings.showOverlay {
                if settings.showOverlay {
                    overlayController.update(overlayStatus)
                } else {
                    overlayController.update(.idle)
                }
            }
            updateStatusArtifacts()
        }
    }
    @Published var selectedAppTab: AppTab
    @Published var selectedSettingsTab: SettingsTab
    @Published var showSettingsPanel = false
    @Published var showSupportPanel = false
    @Published var homeSearchText = ""
    @Published var overlayStatus: OverlayStatus = .idle
    @Published var historyItems: [HistoryItem] = []
    @Published var dictionaryEntries: [DictionaryEntry] = []
    @Published var whisperModelStatuses: [ModelStatus] = []
    @Published var parakeetModelStatuses: [ModelStatus] = []
    @Published var providerAvailability: [ProviderID: ProviderAvailability] = [:]
    @Published var providerReadiness: [ProviderID: ProviderReadiness] = [:]
    @Published var providerDiagnostics: [ProviderDiagnosticStatus] = []
    @Published var appleInstalledLanguages: [LanguageSelection] = []
    @Published var isPreparing = false
    @Published var isCapturingHotkey = false
    @Published var transientMessage: String?

    let permissionsManager: PermissionsManager
    let paths: VerbatimPaths

    private let settingsStore: SettingsStoreProtocol
    private let historyStore: HistoryStoreProtocol
    private let overlayController: OverlayWindowController
    private let statusItemController: StatusItemController
    private let hotkeyManager: HotkeyManager
    private let logStore: VerbatimLogStore
    private let whisperModelManager: WhisperModelManager
    private let parakeetModelManager: ParakeetModelManager
    private let whisperRuntimeManager: WhisperRuntimeManager
    private let parakeetRuntimeManager: ParakeetRuntimeManager
    private let appleProvider: AppleSpeechProvider
    private let whisperProvider: WhisperProvider
    private let parakeetProvider: ParakeetProvider
    private let coordinator: TranscriptionCoordinator

    init() {
        let paths = VerbatimPaths()
        self.paths = paths
        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings
        self.selectedAppTab = settingsStore.settings.lastAppTab
        self.selectedSettingsTab = settingsStore.settings.lastSettingsTab
        let historyStore = HistoryStore(paths: paths)
        self.historyStore = historyStore
        self.permissionsManager = PermissionsManager()
        self.overlayController = OverlayWindowController()
        self.statusItemController = StatusItemController()
        self.hotkeyManager = HotkeyManager()
        let logStore = VerbatimLogStore(paths: paths)
        self.logStore = logStore

        let descriptors = ModelManifestRepository.load()
        self.whisperModelManager = WhisperModelManager(descriptors: descriptors, paths: paths, logStore: logStore)
        self.parakeetModelManager = ParakeetModelManager(descriptors: descriptors, paths: paths, logStore: logStore)
        self.whisperRuntimeManager = WhisperRuntimeManager(paths: paths, logStore: logStore)
        self.parakeetRuntimeManager = ParakeetRuntimeManager(paths: paths, logStore: logStore)
        self.appleProvider = AppleSpeechProvider()
        self.whisperProvider = WhisperProvider(
            settingsStore: settingsStore,
            modelManager: whisperModelManager,
            runtimeManager: self.whisperRuntimeManager
        )
        self.parakeetProvider = ParakeetProvider(
            settingsStore: settingsStore,
            modelManager: parakeetModelManager,
            runtimeManager: self.parakeetRuntimeManager
        )
        self.coordinator = TranscriptionCoordinator(
            recordingManager: RecordingManager(),
            normalizer: AudioNormalizationService(),
            pasteService: PasteService(),
            historyStore: historyStore,
            settingsStore: settingsStore,
            providers: [
                .appleSpeech: appleProvider,
                .whisper: whisperProvider,
                .parakeet: parakeetProvider,
            ],
            logStore: logStore
        )

        statusItemController.onOpen = { [weak self] in
            self?.openMainWindow()
        }
        statusItemController.onToggle = { [weak self] in
            Task { await self?.toggleRecording() }
        }
        statusItemController.setVisible(settings.menuBarEnabled)

        Task { [weak self] in
            await self?.prepare()
        }
    }

    func prepare() async {
        guard isPreparing == false else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            try RuntimeBinaryInstaller.installIfNeeded(paths: paths)
            diagnosticsLogger.info("Runtime staging preflight completed")
            logStore.append("Runtime staging preflight completed", category: .diagnostics)
        } catch {
            diagnosticsLogger.error("Runtime staging preflight failed: \(error.localizedDescription, privacy: .public)")
            logStore.append("Runtime staging preflight failed: \(error.localizedDescription)", category: .diagnostics)
            transientMessage = error.localizedDescription
        }

        await whisperModelManager.importFromElectronCacheIfNeeded()
        await parakeetModelManager.importFromElectronCacheIfNeeded()
        reloadLocalState()
        await refreshProviderState()
        diagnosticsLogger.info("Startup provider preflight completed")
        logStore.append("Startup provider preflight completed", category: .diagnostics)
        configureHotkey()
        updateStatusArtifacts()
    }

    func toggleRecording() async {
        switch overlayStatus {
        case .recording:
            await stopRecordingAndTranscribe()
        case .processing:
            break
        case .idle, .success, .error:
            await startRecording()
        }
    }

    func startRecording() async {
        let granted: Bool
        if permissionsManager.microphoneAuthorized {
            granted = true
        } else {
            granted = await permissionsManager.requestMicrophone()
        }
        guard granted else {
            applyOverlayStatus(.error("Microphone required"))
            transientMessage = "Microphone access is required before dictation can start."
            return
        }

        do {
            try await coordinator.startRecording()
            applyOverlayStatus(.recording)
        } catch {
            applyOverlayStatus(.error(error.localizedDescription))
            transientMessage = error.localizedDescription
        }
    }

    func stopRecordingAndTranscribe() async {
        applyOverlayStatus(.processing)
        do {
            let outcome = try await coordinator.stopRecordingAndTranscribe(
                dictionaryEntries: dictionaryEntries,
                accessibilityGranted: permissionsManager.accessibilityAuthorized
            )
            historyItems.insert(outcome.historyItem, at: 0)
            let message = outcome.pasteResult == .pasted ? "Transcription pasted" : outcome.pasteResult.message
            applyOverlayStatus(.success(message))
            transientMessage = message
        } catch {
            applyOverlayStatus(.error("Transcription failed"))
            transientMessage = error.localizedDescription
            reloadLocalState()
        }
    }

    func requestMicrophone() async {
        _ = await permissionsManager.requestMicrophone()
    }

    func promptAccessibility() {
        permissionsManager.requestAccessibilityPrompt()
    }

    func installAppleAssets() async {
        do {
            try await appleProvider.installAssets(for: settings.preferredLanguage)
            logStore.append("Installed Apple Speech assets for \(settings.preferredLanguage.identifier)", category: .downloads)
            await refreshProviderState()
        } catch {
            logStore.append("Failed Apple Speech asset install: \(error.localizedDescription)", category: .downloads)
            transientMessage = error.localizedDescription
        }
    }

    func downloadWhisperModel(_ id: String) async {
        do {
            try await whisperModelManager.download(modelID: id)
        } catch {
            transientMessage = error.localizedDescription
        }
        reloadLocalState()
        await refreshProviderState()
    }

    func deleteWhisperModel(_ id: String) async {
        do {
            try await whisperModelManager.delete(modelID: id)
        } catch {
            transientMessage = error.localizedDescription
        }
        reloadLocalState()
        await refreshProviderState()
    }

    func downloadParakeetModel(_ id: String) async {
        do {
            try await parakeetModelManager.download(modelID: id)
        } catch {
            transientMessage = error.localizedDescription
        }
        reloadLocalState()
        await refreshProviderState()
    }

    func deleteParakeetModel(_ id: String) async {
        do {
            try await parakeetModelManager.delete(modelID: id)
        } catch {
            transientMessage = error.localizedDescription
        }
        reloadLocalState()
        await refreshProviderState()
    }

    func addDictionaryEntry(phrase: String, hint: String) {
        guard phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let entry = DictionaryEntry(phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines), hint: hint.trimmingCharacters(in: .whitespacesAndNewlines))
        historyStore.upsertDictionary(entry: entry)
        dictionaryEntries = historyStore.fetchDictionary()
    }

    func removeDictionaryEntry(_ id: UUID) {
        historyStore.deleteDictionary(id: id)
        dictionaryEntries = historyStore.fetchDictionary()
    }

    func deleteHistoryItem(_ id: Int64) {
        historyStore.deleteHistory(id: id)
        historyItems.removeAll { $0.id == id }
    }

    func clearHistory() {
        historyStore.clearHistory()
        historyItems = []
    }

    func copyHistoryText(_ item: HistoryItem) {
        NSPasteboard.general.clearContents()
        let text = item.finalPastedText.isEmpty ? item.originalText : item.finalPastedText
        _ = NSPasteboard.general.setString(text, forType: .string)
        transientMessage = "Copied transcription to clipboard."
    }

    func resetOnboarding() {
        settings.onboardingCompleted = false
        dismissPresentedPanels()
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
        selectAppTab(.home)
        dismissPresentedPanels()
    }

    func revealAppSupport() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.rootURL])
    }

    func revealLogs() {
        try? paths.ensureDirectoriesExist()
        let logURLs = (try? FileManager.default.contentsOfDirectory(
            at: paths.logsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        NSWorkspace.shared.activateFileViewerSelecting(logURLs.isEmpty ? [paths.logsRoot] : logURLs)
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        _ = NSPasteboard.general.setString(diagnosticsReport(), forType: .string)
        transientMessage = "Copied diagnostics to clipboard."
    }

    func resetAppData() {
        historyStore.resetAll()
        historyItems = []
        dictionaryEntries = []
        providerDiagnostics = []
        settings = AppSettings()
        selectedAppTab = settings.lastAppTab
        selectedSettingsTab = settings.lastSettingsTab
        homeSearchText = ""
        dismissPresentedPanels()
        applyOverlayStatus(.idle)
        Task {
            try? await whisperRuntimeManager.stop()
            try? await parakeetRuntimeManager.stop()
            await refreshProviderState()
        }
    }

    func updateShortcut(_ shortcut: KeyboardShortcut) {
        settings.hotkey = shortcut
        isCapturingHotkey = false
    }

    func beginHotkeyCapture() {
        isCapturingHotkey = true
    }

    func cancelHotkeyCapture() {
        isCapturingHotkey = false
    }

    func selectAppTab(_ tab: AppTab) {
        selectedAppTab = tab
        settings.lastAppTab = tab
    }

    func openSettings(tab: SettingsTab = .preferences) {
        showSupportPanel = false
        showSettingsPanel = true
        setSelectedSettingsTab(tab)
    }

    func closeSettings() {
        showSettingsPanel = false
    }

    func openSupport() {
        showSettingsPanel = false
        showSupportPanel = true
    }

    func closeSupport() {
        showSupportPanel = false
    }

    func toggleSupport() {
        if showSupportPanel {
            closeSupport()
        } else {
            openSupport()
        }
    }

    func setSelectedSettingsTab(_ tab: SettingsTab) {
        selectedSettingsTab = tab
        settings.lastSettingsTab = tab
    }

    func dismissPresentedPanels() {
        showSettingsPanel = false
        showSupportPanel = false
    }

    func recheckDiagnostics() async {
        diagnosticsLogger.info("Manual diagnostics re-check requested")
        logStore.append("Manual diagnostics re-check requested", category: .diagnostics)
        do {
            try RuntimeBinaryInstaller.installIfNeeded(paths: paths)
        } catch {
            transientMessage = error.localizedDescription
        }
        await refreshProviderState()
    }

    func restartRuntime(for provider: ProviderID) async {
        do {
            switch provider {
            case .whisper:
                let modelURL = await whisperModelManager.installedURL(for: settings.selectedWhisperModelID)
                guard FileManager.default.fileExists(atPath: modelURL.path) else {
                    throw VerbatimTranscriptionError.missingModel("The selected Whisper model is not installed.")
                }
                _ = try await whisperRuntimeManager.restart(modelURL: modelURL)
            case .parakeet:
                let modelURL = await parakeetModelManager.installedURL(for: settings.selectedParakeetModelID)
                guard FileManager.default.fileExists(atPath: modelURL.path) else {
                    throw VerbatimTranscriptionError.missingModel("The selected Parakeet model is not installed.")
                }
                _ = try await parakeetRuntimeManager.restart(modelID: settings.selectedParakeetModelID, modelDirectory: modelURL)
            case .appleSpeech:
                await refreshProviderState()
                return
            }
            transientMessage = "Restarted \(provider.title) runtime."
        } catch {
            transientMessage = error.localizedDescription
        }
        await refreshProviderState()
    }

    var currentLanguageOptions: [LanguageSelection] {
        switch settings.selectedProvider {
        case .whisper:
            return [.auto, .init(identifier: "en-US"), .init(identifier: "es-ES"), .init(identifier: "fr-FR"), .init(identifier: "de-DE"), .init(identifier: "ja-JP")]
        case .parakeet:
            let ids = Set(parakeetModelStatuses.first(where: { $0.descriptor.id == settings.selectedParakeetModelID })?.descriptor.supportedLanguageIDs ?? [])
            return [.auto] + ids.sorted().map(LanguageSelection.init(identifier:))
        case .appleSpeech:
            return appleInstalledLanguages.isEmpty ? [.init(identifier: "en-US"), .init(identifier: "es-ES"), .init(identifier: "fr-FR")] : appleInstalledLanguages
        }
    }

    func providerStatus(for provider: ProviderID) -> ProviderReadiness {
        providerReadiness[provider] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil)
    }

    func availability(for provider: ProviderID) -> ProviderAvailability {
        providerAvailability[provider] ?? ProviderAvailability(isAvailable: false, reason: "Checking…")
    }

    func providerDiagnostic(for provider: ProviderID) -> ProviderDiagnosticStatus? {
        providerDiagnostics.first(where: { $0.provider == provider })
    }

    var supportDiagnosticsSummary: String {
        diagnosticProviderOrder.compactMap { provider in
            guard let diagnostic = providerDiagnostic(for: provider) else { return nil }
            let runtimeState = diagnostic.runtimeSnapshot?.state.rawValue.capitalized ?? "System Managed"
            let readiness = diagnostic.readiness.kind == .ready ? "Ready" : diagnostic.readiness.message
            return "\(provider.title): \(runtimeState) • \(readiness)"
        }
        .joined(separator: "\n")
    }

    var filteredHistorySections: [HistoryDaySection] {
        HistorySectionBuilder.build(items: historyItems, searchText: homeSearchText)
    }

    private func reloadLocalState() {
        historyItems = historyStore.fetchHistory(limit: 200)
        dictionaryEntries = historyStore.fetchDictionary()
        Task {
            whisperModelStatuses = await whisperModelManager.statuses()
            parakeetModelStatuses = await parakeetModelManager.statuses()
        }
    }

    private func refreshProviderState() async {
        let providers: [ProviderID: any TranscriptionProvider] = [
            .appleSpeech: appleProvider,
            .whisper: whisperProvider,
            .parakeet: parakeetProvider,
        ]
        var availability: [ProviderID: ProviderAvailability] = [:]
        var readiness: [ProviderID: ProviderReadiness] = [:]

        for (providerID, provider) in providers {
            availability[providerID] = await provider.availability()
            readiness[providerID] = await provider.readiness(for: settings.preferredLanguage)
        }
        let installedLanguages = await appleProvider.installedLanguages()
        appleInstalledLanguages = installedLanguages
        providerAvailability = availability
        providerReadiness = readiness
        await refreshDiagnostics(
            availability: availability,
            readiness: readiness,
            appleLanguages: installedLanguages
        )
    }

    private func configureHotkey() {
        hotkeyManager.register(shortcut: settings.hotkey) { [weak self] in
            Task { await self?.toggleRecording() }
        }
    }

    private func applyOverlayStatus(_ status: OverlayStatus) {
        overlayStatus = status
        if settings.showOverlay {
            overlayController.update(status)
        }
        updateStatusArtifacts()
    }

    private func updateStatusArtifacts() {
        statusItemController.update(state: overlayStatus, providerName: settings.selectedProvider.title)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var diagnosticProviderOrder: [ProviderID] {
        [.whisper, .parakeet, .appleSpeech]
    }

    private func refreshDiagnostics(
        availability: [ProviderID: ProviderAvailability],
        readiness: [ProviderID: ProviderReadiness],
        appleLanguages: [LanguageSelection]
    ) async {
        let whisperStatuses = await whisperModelManager.statuses()
        let parakeetStatuses = await parakeetModelManager.statuses()
        let whisperSnapshot = await whisperRuntimeManager.snapshot()
        let parakeetSnapshot = await parakeetRuntimeManager.snapshot()

        let selectedWhisper = whisperStatuses.first(where: { $0.id == settings.selectedWhisperModelID })
        let selectedParakeet = parakeetStatuses.first(where: { $0.id == settings.selectedParakeetModelID })
        let whisperLastError = whisperSnapshot.lastError
            ?? (readiness[.whisper]?.isReady == true ? nil : readiness[.whisper]?.message)
            ?? (availability[.whisper]?.isAvailable == true ? nil : availability[.whisper]?.reason)
        let parakeetLastError = parakeetSnapshot.lastError
            ?? (readiness[.parakeet]?.isReady == true ? nil : readiness[.parakeet]?.message)
            ?? (availability[.parakeet]?.isAvailable == true ? nil : availability[.parakeet]?.reason)
        let appleLastError = (readiness[.appleSpeech]?.isReady == true ? nil : readiness[.appleSpeech]?.message)
            ?? (availability[.appleSpeech]?.isAvailable == true ? nil : availability[.appleSpeech]?.reason)

        providerDiagnostics = [
            ProviderDiagnosticStatus(
                provider: .whisper,
                availability: availability[.whisper] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.whisper] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: selectedWhisper?.descriptor.name ?? settings.selectedWhisperModelID,
                selectionInstalled: selectedWhisper?.state == .ready,
                selectionSource: await whisperModelManager.installSource(for: settings.selectedWhisperModelID),
                runtimeSnapshot: whisperSnapshot,
                lastCheck: whisperSnapshot.lastCheck ?? .now,
                lastError: whisperLastError
            ),
            ProviderDiagnosticStatus(
                provider: .parakeet,
                availability: availability[.parakeet] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.parakeet] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: selectedParakeet?.descriptor.name ?? settings.selectedParakeetModelID,
                selectionInstalled: selectedParakeet?.state == .ready,
                selectionSource: await parakeetModelManager.installSource(for: settings.selectedParakeetModelID),
                runtimeSnapshot: parakeetSnapshot,
                lastCheck: parakeetSnapshot.lastCheck ?? .now,
                lastError: parakeetLastError
            ),
            ProviderDiagnosticStatus(
                provider: .appleSpeech,
                availability: availability[.appleSpeech] ?? ProviderAvailability(isAvailable: false, reason: "Checking…"),
                readiness: readiness[.appleSpeech] ?? ProviderReadiness(kind: .unavailable, message: "Checking…", actionTitle: nil),
                selectionDescription: settings.preferredLanguage.title,
                selectionInstalled: settings.preferredLanguage.isAuto == false && appleLanguages.contains(settings.preferredLanguage),
                selectionSource: nil,
                runtimeSnapshot: nil,
                lastCheck: .now,
                lastError: appleLastError
            ),
        ]
        diagnosticsLogger.info("Refreshed provider diagnostics")
        logStore.append("Refreshed provider diagnostics", category: .diagnostics)
    }

    private func diagnosticsReport() -> String {
        var lines: [String] = [
            "Verbatim Diagnostics",
            "Generated: \(Date.now.formatted(date: .abbreviated, time: .standard))",
            "Storage: \(paths.rootURL.path)",
            "Logs: \(paths.logsRoot.path)",
            ""
        ]

        for diagnostic in providerDiagnostics {
            lines.append("\(diagnostic.provider.title)")
            lines.append("Availability: \(diagnostic.availability.isAvailable ? "Available" : "Unavailable")")
            if let reason = diagnostic.availability.reason, reason.isEmpty == false {
                lines.append("Availability reason: \(reason)")
            }
            lines.append("Selection: \(diagnostic.selectionDescription)")
            lines.append("Installed: \(diagnostic.selectionInstalled ? "Yes" : "No")")
            if let source = diagnostic.selectionSource {
                lines.append("Install source: \(source.title)")
            }
            lines.append("Readiness: \(diagnostic.readiness.message)")
            if let snapshot = diagnostic.runtimeSnapshot {
                lines.append("Runtime binary: \(snapshot.binaryPresent ? "Present" : "Missing")")
                lines.append("Runtime state: \(snapshot.state.rawValue)")
                if let endpoint = snapshot.endpoint {
                    lines.append("Runtime endpoint: \(endpoint)")
                }
                lines.append("Runtime log: \(snapshot.logFileName)")
            }
            if let error = diagnostic.lastError, error.isEmpty == false {
                lines.append("Last error: \(error)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
