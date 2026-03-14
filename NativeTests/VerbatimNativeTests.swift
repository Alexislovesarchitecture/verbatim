import XCTest
import Carbon
@testable import Verbatim

final class VerbatimNativeTests: XCTestCase {
    func testSettingsStorePersistsSelection() {
        let suiteName = "verbatim-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults)
        var settings = store.settings
        settings.selectedProvider = .parakeet
        settings.selectedWhisperModelID = "turbo"
        settings.lastAppTab = .dictionary
        settings.lastSettingsTab = .privacyPermissions
        store.replace(settings)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.selectedProvider, .parakeet)
        XCTAssertEqual(reloaded.settings.selectedWhisperModelID, "turbo")
        XCTAssertEqual(reloaded.settings.lastAppTab, .dictionary)
        XCTAssertEqual(reloaded.settings.lastSettingsTab, .privacyPermissions)
    }

    func testSettingsStoreMigratesLegacyDefaults() {
        let suiteName = "verbatim-legacy-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("legacy_whisper", forKey: "VerbatimSwiftMVP.LocalEngineMode")
        defaults.set("whisper-small", forKey: "VerbatimSwiftMVP.LocalModelID")
        defaults.set(true, forKey: "VerbatimSwiftMVP.SetupCompleted")

        let legacyInteraction = """
        {
          "showListeningIndicator": false,
          "autoPasteAfterInsert": false,
          "hotkeyBinding": {
            "keyCode": 49,
            "modifierFlagsRawValue": 524288,
            "keyDisplay": "Space",
            "modifierKeyRawValue": null
          }
        }
        """.data(using: .utf8)!
        defaults.set(legacyInteraction, forKey: "VerbatimSwiftMVP.InteractionSettingsV1")

        let store = SettingsStore(defaults: defaults)
        let settings = store.settings

        XCTAssertEqual(settings.selectedProvider, .whisper)
        XCTAssertEqual(settings.selectedWhisperModelID, "small")
        XCTAssertTrue(settings.onboardingCompleted)
        XCTAssertFalse(settings.showOverlay)
        XCTAssertEqual(settings.pasteMode, .clipboardOnly)
        XCTAssertEqual(settings.hotkey.keyCode, 49)
        XCTAssertEqual(settings.hotkey.modifiers, UInt32(optionKey))
        XCTAssertNotNil(defaults.data(forKey: "Verbatim.NativeSettings"))
    }

    func testPathsMigrateLegacyApplicationSupportRoot() throws {
        let fileManager = FileManager.default
        let appSupport = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyRoot = appSupport.appendingPathComponent("VerbatimSwiftMVP", isDirectory: true)
        try fileManager.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let marker = legacyRoot.appendingPathComponent("marker.txt")
        try Data("legacy".utf8).write(to: marker)

        let paths = VerbatimPaths(fileManager: fileManager, appSupportDirectory: appSupport)
        try paths.ensureDirectoriesExist()

        XCTAssertTrue(fileManager.fileExists(atPath: paths.rootURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: paths.rootURL.appendingPathComponent("marker.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyRoot.path))
    }

    func testHistoryStoreRoundTripAndDictionary() {
        let paths = temporaryPaths()
        let store = HistoryStore(paths: paths)
        _ = store.save(
            provider: .whisper,
            language: .init(identifier: "en-US"),
            originalText: "hello",
            finalText: "hello",
            error: nil
        )
        store.upsertDictionary(entry: DictionaryEntry(phrase: "OpenWhispr", hint: "open whisper"))

        XCTAssertEqual(store.fetchHistory(limit: 10).count, 1)
        XCTAssertEqual(store.fetchDictionary().first?.phrase, "OpenWhispr")
    }

    func testRuntimeBinaryInstallerStagesFlatResources() throws {
        let fileManager = FileManager.default
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()
        let resourceRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: resourceRoot, withIntermediateDirectories: true)

        let whisperBinary = resourceRoot.appendingPathComponent("whisper-server-darwin-arm64")
        let dylib = resourceRoot.appendingPathComponent("libggml.0.dylib")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: whisperBinary)
        try Data("dylib".utf8).write(to: dylib)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisperBinary.path)

        try RuntimeBinaryInstaller.installIfNeeded(paths: paths, resourceBaseURL: resourceRoot)

        let stagedBinary = paths.runtimeRoot.appendingPathComponent("whisper-server-darwin-arm64")
        let stagedDylib = paths.runtimeRoot.appendingPathComponent("libggml.0.dylib")
        XCTAssertTrue(fileManager.fileExists(atPath: stagedBinary.path))
        XCTAssertTrue(fileManager.fileExists(atPath: stagedDylib.path))
        let permissions = try fileManager.attributesOfItem(atPath: stagedBinary.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o755)
    }

    func testRuntimeBinaryInstallerStagesBinariesSubfolder() throws {
        let fileManager = FileManager.default
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()
        let resourceRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binariesRoot = resourceRoot.appendingPathComponent("Binaries", isDirectory: true)
        try fileManager.createDirectory(at: binariesRoot, withIntermediateDirectories: true)

        let whisperBinary = binariesRoot.appendingPathComponent("whisper-server-darwin-arm64")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: whisperBinary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisperBinary.path)

        try RuntimeBinaryInstaller.installIfNeeded(paths: paths, resourceBaseURL: resourceRoot)

        let stagedBinary = paths.runtimeRoot.appendingPathComponent("whisper-server-darwin-arm64")
        XCTAssertTrue(fileManager.fileExists(atPath: stagedBinary.path))
    }

    func testWhisperRuntimeManagerBecomesReadyWithStagedBinary() async throws {
        let fileManager = FileManager.default
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()

        let binary = paths.runtimeRoot.appendingPathComponent("whisper-server-darwin-arm64")
        let script = """
        #!/bin/sh
        PORT=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--port" ]; then
            shift
            PORT="$1"
          fi
          shift
        done
        exec /usr/bin/python3 -m http.server "$PORT" --bind 127.0.0.1
        """
        try Data(script.utf8).write(to: binary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let modelURL = paths.whisperModelsRoot.appendingPathComponent("dummy-model.bin")
        try Data("model".utf8).write(to: modelURL)

        let logStore = VerbatimLogStore(paths: paths)
        let manager = WhisperRuntimeManager(paths: paths, logStore: logStore)

        let url = try await manager.ensureRunning(modelURL: modelURL)
        XCTAssertTrue(url.absoluteString.hasPrefix("http://127.0.0.1:"))

        let snapshot = await manager.snapshot()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertTrue(snapshot.binaryPresent)
        XCTAssertNotNil(snapshot.endpoint)

        try await manager.stop()
        let stoppedSnapshot = await manager.snapshot()
        XCTAssertEqual(stoppedSnapshot.state, .stopped)
    }

    func testWhisperProviderReadinessRequiresDownloadWhenModelMissing() async throws {
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()
        let logStore = VerbatimLogStore(paths: paths)
        let settingsStore = FakeSettingsStore()
        var settings = AppSettings()
        settings.selectedProvider = .whisper
        settings.selectedWhisperModelID = "base"
        settingsStore.replace(settings)

        let modelManager = WhisperModelManager(
            descriptors: ModelManifestRepository.load(),
            paths: paths,
            logStore: logStore
        )
        let runtimeManager = WhisperRuntimeManager(paths: paths, logStore: logStore)
        let provider = WhisperProvider(
            settingsStore: settingsStore,
            modelManager: modelManager,
            runtimeManager: runtimeManager
        )

        let readiness = await provider.readiness(for: .auto)
        XCTAssertEqual(readiness.kind, .missingModel)
        XCTAssertEqual(readiness.actionTitle, "Download")
    }

    func testWhisperProviderReadinessReportsMissingBinaryWhenModelInstalled() async throws {
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()
        let logStore = VerbatimLogStore(paths: paths)
        let settingsStore = FakeSettingsStore()
        var settings = AppSettings()
        settings.selectedProvider = .whisper
        settings.selectedWhisperModelID = "base"
        settingsStore.replace(settings)

        let modelManager = WhisperModelManager(
            descriptors: ModelManifestRepository.load(),
            paths: paths,
            logStore: logStore
        )
        let runtimeManager = WhisperRuntimeManager(paths: paths, logStore: logStore)
        let provider = WhisperProvider(
            settingsStore: settingsStore,
            modelManager: modelManager,
            runtimeManager: runtimeManager
        )

        let modelURL = await modelManager.installedURL(for: "base")
        try Data("model".utf8).write(to: modelURL)

        let readiness = await provider.readiness(for: .auto)
        XCTAssertEqual(readiness.kind, .binaryMissing)
        XCTAssertNil(readiness.actionTitle)
    }

    func testParakeetProviderReadinessRequiresDownloadWhenModelMissing() async throws {
        let paths = temporaryPaths()
        try paths.ensureDirectoriesExist()
        let logStore = VerbatimLogStore(paths: paths)
        let settingsStore = FakeSettingsStore()
        var settings = AppSettings()
        settings.selectedProvider = .parakeet
        settings.selectedParakeetModelID = "parakeet-tdt-0.6b-v3"
        settingsStore.replace(settings)

        let modelManager = ParakeetModelManager(
            descriptors: ModelManifestRepository.load(),
            paths: paths,
            logStore: logStore
        )
        let runtimeManager = ParakeetRuntimeManager(paths: paths, logStore: logStore)
        let provider = ParakeetProvider(
            settingsStore: settingsStore,
            modelManager: modelManager,
            runtimeManager: runtimeManager
        )

        let readiness = await provider.readiness(for: .auto)
        XCTAssertEqual(readiness.kind, .missingModel)
        XCTAssertEqual(readiness.actionTitle, "Download")
    }

    @MainActor
    func testCoordinatorUsesSelectedProviderAndClipboardFallback() async throws {
        let store = FakeSettingsStore()
        store.replace(AppSettings(selectedProvider: .parakeet, preferredLanguageID: "en", selectedWhisperModelID: "base", selectedParakeetModelID: "parakeet-tdt-0.6b-v3"))
        let history = FakeHistoryStore()
        let coordinator = TranscriptionCoordinator(
            recordingManager: FakeRecordingManager(),
            normalizer: FakeNormalizer(),
            pasteService: FakePasteService(),
            historyStore: history,
            settingsStore: store,
            providers: [
                .parakeet: FakeProvider(id: .parakeet, text: "hello world")
            ]
        )

        try await coordinator.startRecording(provider: .parakeet)
        let outcome = try await coordinator.stopRecordingAndTranscribe(
            provider: .parakeet,
            language: .init(identifier: "en"),
            dictionaryEntries: [],
            accessibilityGranted: false
        )

        XCTAssertEqual(outcome.result.provider, .parakeet)
        XCTAssertEqual(outcome.pasteResult, .copiedOnly("Copied to clipboard. Enable Accessibility for auto-paste."))
        XCTAssertEqual(history.savedItems.first?.provider, .parakeet)
    }

    @MainActor
    func testKeyboardShortcutTitleFormats() {
        let shortcut = KeyboardShortcut(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
        XCTAssertEqual(shortcut.displayTitle, "⌥⌘Space")
    }

    func testHistorySectionBuilderGroupsAndFiltersHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        let today = now.addingTimeInterval(-300)
        let earlierToday = now.addingTimeInterval(-3_600)
        let yesterday = now.addingTimeInterval(-86_400)
        let older = now.addingTimeInterval(-172_800)

        let items = [
            HistoryItem(id: 1, timestamp: earlierToday, provider: ProviderID.whisper.rawValue, language: "en-US", originalText: "today earlier", finalPastedText: "today earlier", error: nil),
            HistoryItem(id: 2, timestamp: today, provider: ProviderID.whisper.rawValue, language: "en-US", originalText: "today latest", finalPastedText: "today latest", error: nil),
            HistoryItem(id: 3, timestamp: yesterday, provider: ProviderID.appleSpeech.rawValue, language: "en-US", originalText: "yesterday", finalPastedText: "yesterday", error: nil),
            HistoryItem(id: 4, timestamp: older, provider: ProviderID.parakeet.rawValue, language: "en-US", originalText: "older source", finalPastedText: "older final", error: nil),
        ]

        let sections = HistorySectionBuilder.build(items: items, searchText: "", calendar: calendar, now: now)

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", older.formatted(date: .abbreviated, time: .omitted)])
        XCTAssertEqual(sections.first?.items.map(\.id), [2, 1])

        let filtered = HistorySectionBuilder.build(items: items, searchText: "older final", calendar: calendar, now: now)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.items.map(\.id), [4])
    }

    private func temporaryPaths() -> VerbatimPaths {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let fm = FileManager.default
        return VerbatimPaths(fileManager: fm, rootURL: tempRoot)
    }
}

private final class FakeSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    private var current = AppSettings()

    var settings: AppSettings { current }

    func replace(_ settings: AppSettings) {
        current = settings
    }
}

private final class FakeHistoryStore: HistoryStoreProtocol, @unchecked Sendable {
    private(set) var savedItems: [(provider: ProviderID, text: String)] = []

    func fetchHistory(limit: Int) -> [HistoryItem] { [] }

    func save(provider: ProviderID, language: LanguageSelection, originalText: String, finalText: String, error: String?) -> HistoryItem {
        savedItems.append((provider, finalText))
        return HistoryItem(id: 1, timestamp: .now, provider: provider.rawValue, language: language.identifier, originalText: originalText, finalPastedText: finalText, error: error)
    }

    func deleteHistory(id: Int64) {}
    func clearHistory() {}
    func fetchDictionary() -> [DictionaryEntry] { [] }
    func upsertDictionary(entry: DictionaryEntry) {}
    func deleteDictionary(id: UUID) {}
    func resetAll() {}
}

private final class FakeRecordingManager: RecordingManagerProtocol, @unchecked Sendable {
    func startRecording() async throws {}

    func stopRecording() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake.wav")
        try Data().write(to: url)
        return url
    }

    func cancel() {}
}

private struct FakeNormalizer: AudioNormalizationServiceProtocol {
    func normalizeAudioFile(at sourceURL: URL) async throws -> URL { sourceURL }
}

private final class FakePasteService: PasteServiceProtocol, @unchecked Sendable {
    func captureTarget() -> PasteTarget? { PasteTarget(appName: "Notes", bundleIdentifier: "com.apple.Notes", processIdentifier: 99) }

    func paste(text: String, to target: PasteTarget?, pasteMode: PasteMode, accessibilityGranted: Bool) -> PasteResult {
        _ = text
        _ = target
        _ = pasteMode
        return accessibilityGranted ? .pasted : .copiedOnly("Copied to clipboard. Enable Accessibility for auto-paste.")
    }
}

private actor FakeProvider: TranscriptionProvider {
    let id: ProviderID
    let text: String

    init(id: ProviderID, text: String) {
        self.id = id
        self.text = text
    }

    func availability() async -> ProviderAvailability {
        ProviderAvailability(isAvailable: true, reason: nil)
    }

    func readiness(for language: LanguageSelection) async -> ProviderReadiness {
        _ = language
        return .ready
    }

    func transcribe(audioFileURL: URL, language: LanguageSelection, dictionaryHints: [DictionaryEntry]) async throws -> TranscriptionResult {
        _ = audioFileURL
        _ = dictionaryHints
        return TranscriptionResult(originalText: text, finalText: text, provider: id, language: language)
    }
}
