import AVFoundation
import Speech
import XCTest
@testable import VerbatimSwiftMVP

@MainActor
final class TranscriptionViewModelHotkeySessionTests: XCTestCase {
    func testLegacyGlossaryMigratesIntoDatabaseBackedDictionary() async throws {
        let defaultsKey = "VerbatimSwiftMVP.RefineSettingsV1"
        let legacySettings = RefineSettings(
            glossary: [
                GlossaryEntry(from: "adu", to: "ADU"),
                GlossaryEntry(from: "site scape", to: "Sitescape"),
            ]
        )
        UserDefaults.standard.set(try JSONEncoder().encode(legacySettings), forKey: defaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-db-\(UUID().uuidString)", isDirectory: true)
        let database = TranscriptRecordStore(baseDirectoryURL: tempRoot)
        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Messages",
                    bundleID: "com.apple.MobileSMS",
                    processIdentifier: 1,
                    styleCategory: .personal,
                    windowTitle: "Chat",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let pipeline = PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: ViewModelFakeDeterministicFormatter(),
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: activeContextService,
            transcriptRecordStore: database,
            insertionService: ViewModelFakeInsertionService(),
            llmFormatterService: ViewModelFakeLLMFormatterService()
        )

        let sut = TranscriptionViewModel(
            transcriptionCoordinator: TranscriptionCoordinator(
                recorder: ViewModelFakeAudioRecorder(
                    artifact: AudioRecordingArtifact(
                        audioFileURL: temporaryAudioURL(),
                        frameStream: makeFrameStream(frames: [])
                    )
                ),
                remoteEngine: ViewModelFakeRemoteEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                localEngine: ViewModelFakeLocalEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                modelCatalogService: ViewModelFakeModelCatalog()
            ),
            activeAppContextService: activeContextService,
            promptProfileStore: PromptProfileStore(),
            transcriptRecordStore: database,
            insertionService: ViewModelFakeInsertionService(),
            postTranscriptionPipeline: pipeline,
            globalHotkeyService: ViewModelFakeGlobalHotkeyService(),
            listeningIndicatorService: ViewModelFakeListeningIndicatorService(),
            soundCueService: ViewModelFakeSoundCueService()
        )

        XCTAssertEqual(sut.dictionaryEntries.map(\.to), ["ADU", "Sitescape"])
        XCTAssertTrue(sut.refineSettings.glossary.isEmpty)
        XCTAssertEqual(database.fetchDictionaryEntries().count, 2)
    }

    func testSilentHotkeySessionDoesNotPersistHistoryEntry() async throws {
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let indicatorService = ViewModelFakeListeningIndicatorService()
        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Messages",
                    bundleID: "com.apple.MobileSMS",
                    processIdentifier: 1,
                    styleCategory: .personal,
                    windowTitle: "Chat",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let transcript = Transcript(
            rawText: "ignored",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "apple-on-device",
            responseFormat: "text"
        )
        let coordinator = TranscriptionCoordinator(
            recorder: ViewModelFakeAudioRecorder(
                artifact: AudioRecordingArtifact(
                    audioFileURL: temporaryAudioURL(),
                    frameStream: makeFrameStream(frames: Array(repeating: makeFrame(amplitude: 0, sampleCount: 1600), count: 4))
                )
            ),
            remoteEngine: ViewModelFakeRemoteEngine(transcript: transcript),
            localEngine: ViewModelFakeLocalEngine(transcript: transcript),
            modelCatalogService: ViewModelFakeModelCatalog()
        )
        let pipeline = makePipeline(
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService
        )
        let sut = makeViewModel(
            coordinator: coordinator,
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: pipeline,
            indicatorService: indicatorService
        )

        sut.transcriptionMode = .local
        sut.autoFormatEnabled = false
        sut.start(fromHotkey: true)
        try await waitUntil { sut.state == .recording }

        sut.stop()
        try await waitUntil { sut.state == .done }

        XCTAssertNil(sut.transcript)
        XCTAssertEqual(recordStore.records.count, 0)
        XCTAssertEqual(activeContextService.callCount, 1)
        XCTAssertEqual(sut.statusMessage, "Silence ignored")
        XCTAssertEqual(indicatorService.lastOutcome, .noSpeechDetected)
        XCTAssertEqual(recordStore.diagnosticSessions.count, 1)
        XCTAssertTrue(recordStore.diagnosticSessions[0].skippedForSilence)
        XCTAssertEqual(recordStore.diagnosticSessions[0].logicModelID, sut.selectedLocalLogicModelID)
        XCTAssertEqual(recordStore.diagnosticSessions[0].reasoningEffort, sut.logicSettings.reasoningEffort.rawValue)
    }

    func testHotkeySessionUsesFrozenContextEvenAfterAppSwitch() async throws {
        let firstContext = ActiveAppContext(
            appName: "Messages",
            bundleID: "com.apple.MobileSMS",
            processIdentifier: 9,
            styleCategory: .personal,
            windowTitle: "Chat",
            focusedElementRole: "AXTextArea"
        )
        let secondContext = ActiveAppContext(
            appName: "Mail",
            bundleID: "com.apple.mail",
            processIdentifier: 12,
            styleCategory: .email,
            windowTitle: "Draft",
            focusedElementRole: "AXTextArea"
        )
        let activeContextService = SequencedActiveAppContextService(contexts: [firstContext, secondContext])
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let transcript = Transcript(
            rawText: "hello there",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "apple-on-device",
            responseFormat: "text"
        )
        let coordinator = TranscriptionCoordinator(
            recorder: ViewModelFakeAudioRecorder(
                artifact: AudioRecordingArtifact(
                    audioFileURL: temporaryAudioURL(),
                    frameStream: makeFrameStream(frames: Array(repeating: makeFrame(amplitude: 9_000, sampleCount: 1600), count: 3))
                )
            ),
            remoteEngine: ViewModelFakeRemoteEngine(transcript: transcript),
            localEngine: ViewModelFakeLocalEngine(transcript: transcript),
            modelCatalogService: ViewModelFakeModelCatalog()
        )
        let pipeline = makePipeline(
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService
        )
        let sut = makeViewModel(
            coordinator: coordinator,
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: pipeline,
            indicatorService: ViewModelFakeListeningIndicatorService()
        )

        sut.transcriptionMode = .local
        sut.autoFormatEnabled = false
        sut.start(fromHotkey: true)
        try await waitUntil { sut.state == .recording }

        sut.stop()
        try await waitUntil { sut.state == .done }

        XCTAssertEqual(activeContextService.callCount, 1)
        XCTAssertEqual(recordStore.records.first?.styleCategory, .personal)
        XCTAssertEqual(recordStore.records.first?.bundleID, "com.apple.MobileSMS")
        XCTAssertEqual(insertionService.lastTarget?.bundleID, "com.apple.MobileSMS")
        XCTAssertEqual(recordStore.diagnosticSessions.first?.logicModelID, sut.selectedLocalLogicModelID)
        XCTAssertEqual(recordStore.diagnosticSessions.first?.reasoningEffort, sut.logicSettings.reasoningEffort.rawValue)
        XCTAssertEqual(sut.statusMessage, "Inserted.")
    }

    func testFunctionHotkeyFallbackShowsEffectiveBinding() {
        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Messages",
                    bundleID: "com.apple.MobileSMS",
                    processIdentifier: 9,
                    styleCategory: .personal,
                    windowTitle: "Chat",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let hotkeyService = ViewModelFakeGlobalHotkeyService(
            startResult: HotkeyStartResult(
                backend: .fallback,
                effectiveBinding: .controlOptionSpace,
                originalBinding: .defaultFunctionKey,
                fallbackWasUsed: true,
                message: "Function key could not be used globally. Using Control + Option + Space instead.",
                recommendedFallback: .controlOptionSpace,
                permissionGranted: true,
                isActive: true
            )
        )
        let sut = makeViewModel(
            coordinator: TranscriptionCoordinator(
                recorder: ViewModelFakeAudioRecorder(
                    artifact: AudioRecordingArtifact(
                        audioFileURL: temporaryAudioURL(),
                        frameStream: makeFrameStream(frames: [])
                    )
                ),
                remoteEngine: ViewModelFakeRemoteEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                localEngine: ViewModelFakeLocalEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                modelCatalogService: ViewModelFakeModelCatalog()
            ),
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: makePipeline(
                recordStore: recordStore,
                insertionService: insertionService,
                activeAppContextService: activeContextService
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            globalHotkeyService: hotkeyService
        )

        sut.interactionSettings.hotkeyEnabled = true

        XCTAssertEqual(sut.effectiveHotkeyBindingTitle, HotkeyBinding.controlOptionSpace.displayTitle)
        XCTAssertTrue(sut.hasEffectiveHotkeyOverride)
        XCTAssertTrue(sut.hotkeyStatusMessage.contains("Using Control + Option + Space instead"))
    }

    func testViewModelDefaultsToAppleLocalOnlyEvenWhenRemoteStateWasPersisted() {
        UserDefaults.standard.set(TranscriptionMode.remote.rawValue, forKey: "VerbatimSwiftMVP.TranscriptionMode")
        UserDefaults.standard.set(LogicMode.remote.rawValue, forKey: "VerbatimSwiftMVP.LogicMode")
        UserDefaults.standard.set(LocalTranscriptionModel.whisperBase.rawValue, forKey: "VerbatimSwiftMVP.LocalModelID")
        UserDefaults.standard.set(LocalTranscriptionEngineMode.legacyWhisper.rawValue, forKey: "VerbatimSwiftMVP.LocalEngineMode")
        defer {
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.TranscriptionMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LogicMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LocalModelID")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LocalEngineMode")
        }

        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Messages",
                    bundleID: "com.apple.MobileSMS",
                    processIdentifier: 9,
                    styleCategory: .personal,
                    windowTitle: "Chat",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let sut = makeViewModel(
            coordinator: TranscriptionCoordinator(
                recorder: ViewModelFakeAudioRecorder(
                    artifact: AudioRecordingArtifact(
                        audioFileURL: temporaryAudioURL(),
                        frameStream: makeFrameStream(frames: [])
                    )
                ),
                remoteEngine: ViewModelFakeRemoteEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                localEngine: ViewModelFakeLocalEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                modelCatalogService: ViewModelFakeModelCatalog()
            ),
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: makePipeline(
                recordStore: recordStore,
                insertionService: insertionService,
                activeAppContextService: activeContextService
            ),
            indicatorService: ViewModelFakeListeningIndicatorService()
        )

        XCTAssertEqual(sut.transcriptionMode, .local)
        XCTAssertEqual(sut.logicMode, .local)
        XCTAssertEqual(sut.selectedLocalEngineMode, .appleSpeech)
        XCTAssertEqual(sut.selectedLocalModel, .appleOnDevice)
    }

    func testAppleSpeechInstallStateSurfacesPrimaryActionAndProgress() async throws {
        let runtimeManager = ViewModelFakeAppleSpeechRuntimeManager(
            status: .installRequired(locale: Locale(identifier: "en_US")),
            installResult: .ready(locale: Locale(identifier: "en_US"))
        )
        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Messages",
                    bundleID: "com.apple.MobileSMS",
                    processIdentifier: 9,
                    styleCategory: .personal,
                    windowTitle: "Chat",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let sut = makeViewModel(
            coordinator: TranscriptionCoordinator(
                recorder: ViewModelFakeAudioRecorder(
                    artifact: AudioRecordingArtifact(
                        audioFileURL: temporaryAudioURL(),
                        frameStream: makeFrameStream(frames: [])
                    )
                ),
                remoteEngine: ViewModelFakeRemoteEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                localEngine: ViewModelFakeLocalEngine(
                    transcript: Transcript.empty(modelID: "apple-on-device", responseFormat: "text")
                ),
                modelCatalogService: ViewModelFakeModelCatalog()
            ),
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: makePipeline(
                recordStore: recordStore,
                insertionService: insertionService,
                activeAppContextService: activeContextService
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            appleSpeechRuntimeManager: runtimeManager
        )

        sut.refreshAppleSpeechRuntime()
        try await waitUntil { sut.appleSpeechPrimaryActionTitle == "Install" }
        XCTAssertEqual(sut.localModelBadgeText(.appleOnDevice), "Install")
        XCTAssertFalse(sut.canStartForCurrentMode)

        sut.installAppleSpeechAssets()
        try await waitUntil { sut.appleSpeechRuntimeStatus.isReady }

        let progress = await runtimeManager.reportedProgressValues
        XCTAssertFalse(progress.isEmpty)
        XCTAssertNil(sut.appleSpeechPrimaryActionTitle)
        XCTAssertEqual(sut.localModelBadgeText(.appleOnDevice), "Ready")
        XCTAssertTrue(sut.canStartForCurrentMode)
    }

    func testLocalTranscriptionStillSucceedsWhenLocalLogicRuntimeIsUnavailable() async throws {
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let activeContextService = SequencedActiveAppContextService(
            contexts: [
                ActiveAppContext(
                    appName: "Notes",
                    bundleID: "com.apple.Notes",
                    processIdentifier: 21,
                    styleCategory: .other,
                    windowTitle: "Scratch",
                    focusedElementRole: "AXTextArea"
                )
            ]
        )
        let transcript = Transcript(
            rawText: "hello local logic",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "apple-on-device",
            responseFormat: "text"
        )
        let coordinator = TranscriptionCoordinator(
            recorder: ViewModelFakeAudioRecorder(
                artifact: AudioRecordingArtifact(
                    audioFileURL: temporaryAudioURL(),
                    frameStream: makeFrameStream(frames: Array(repeating: makeFrame(amplitude: 9_000, sampleCount: 1600), count: 3))
                )
            ),
            remoteEngine: ViewModelFakeRemoteEngine(transcript: transcript),
            localEngine: ViewModelFakeLocalEngine(transcript: transcript),
            modelCatalogService: ViewModelFakeModelCatalog()
        )
        let pipeline = makePipeline(
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService
        )
        let sut = makeViewModel(
            coordinator: coordinator,
            recordStore: recordStore,
            insertionService: insertionService,
            activeAppContextService: activeContextService,
            pipeline: pipeline,
            indicatorService: ViewModelFakeListeningIndicatorService()
        )

        sut.autoFormatEnabled = true
        sut.start(fromHotkey: false)
        try await waitUntil { sut.state == .recording }

        sut.stop()
        try await waitUntil { sut.state == .done }

        XCTAssertEqual(sut.transcript?.rawText, "hello local logic")
        XCTAssertEqual(recordStore.records.first?.rawText, "hello local logic")
    }

    private func makePipeline(
        recordStore: ViewModelFakeRecordStore,
        insertionService: ViewModelFakeInsertionService,
        activeAppContextService: SequencedActiveAppContextService
    ) -> PostTranscriptionPipeline {
        PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: ViewModelFakeDeterministicFormatter(),
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: activeAppContextService,
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            llmFormatterService: ViewModelFakeLLMFormatterService()
        )
    }

    private func makeViewModel(
        coordinator: TranscriptionCoordinator,
        recordStore: ViewModelFakeRecordStore,
        insertionService: ViewModelFakeInsertionService,
        activeAppContextService: SequencedActiveAppContextService,
        pipeline: PostTranscriptionPipeline,
        indicatorService: ViewModelFakeListeningIndicatorService,
        globalHotkeyService: GlobalHotkeyServiceProtocol = ViewModelFakeGlobalHotkeyService(),
        appleSpeechRuntimeManager: AppleSpeechRuntimeManaging = ViewModelFakeAppleSpeechRuntimeManager()
    ) -> TranscriptionViewModel {
        let sut = TranscriptionViewModel(
            appleSpeechRuntimeManager: appleSpeechRuntimeManager,
            appleSpeechPermissionProvider: ViewModelFakeAppleSpeechPermissionProvider(),
            transcriptionCoordinator: coordinator,
            activeAppContextService: activeAppContextService,
            promptProfileStore: PromptProfileStore(),
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            postTranscriptionPipeline: pipeline,
            globalHotkeyService: globalHotkeyService,
            listeningIndicatorService: indicatorService,
            soundCueService: ViewModelFakeSoundCueService()
        )
        sut.refineSettings = RefineSettings(
            workEnabled: false,
            emailEnabled: false,
            personalEnabled: false,
            otherEnabled: false,
            previewBeforeInsert: false
        )
        return sut
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }

    private func makeFrameStream(frames: [AudioPCM16Frame]) -> AsyncStream<AudioPCM16Frame> {
        AsyncStream { continuation in
            for frame in frames {
                continuation.yield(frame)
            }
            continuation.finish()
        }
    }

    private func makeFrame(amplitude: Int16, sampleCount: Int) -> AudioPCM16Frame {
        let samples = Array(repeating: amplitude, count: sampleCount)
        let data = samples.withUnsafeBytes { Data($0) }
        return AudioPCM16Frame(
            sequenceNumber: 1,
            sampleRate: 16_000,
            channelCount: 1,
            samples: data
        )
    }

    private func temporaryAudioURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-viewmodel-\(UUID().uuidString).wav")
        try? Data().write(to: url)
        return url
    }
}

private final class ViewModelFakeAudioRecorder: AudioRecorderServiceProtocol {
    let artifact: AudioRecordingArtifact

    init(artifact: AudioRecordingArtifact) {
        self.artifact = artifact
    }

    func startRecording() async throws -> AsyncStream<AudioPCM16Frame> {
        artifact.frameStream
    }

    func stopRecording() async throws -> AudioRecordingArtifact? {
        artifact
    }

    func discardRecordingArtifact(_ artifact: AudioRecordingArtifact?) {}
}

private final class ViewModelFakeRemoteEngine: TranscriptionServiceProtocol {
    let engineID = "fake-remote"
    let capabilities = EngineCapabilities.none
    private let transcript: Transcript

    init(transcript: Transcript) {
        self.transcript = transcript
    }

    func transcribe(audioFileURL: URL, apiKey: String?, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }
}

private final class ViewModelFakeLocalEngine: LocalTranscriptionServiceProtocol {
    let engineID = "fake-local"
    let capabilities = EngineCapabilities.none
    private let transcript: Transcript

    init(transcript: Transcript) {
        self.transcript = transcript
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        transcript
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        transcript
    }
}

private struct ViewModelFakeModelCatalog: ModelCatalogServiceProtocol {
    func fetchRemoteModelIDs(apiKey: String?) async throws -> Set<String> {
        ["gpt-4o-mini-transcribe"]
    }
}

private final class SequencedActiveAppContextService: ActiveAppContextServiceProtocol {
    private let contexts: [ActiveAppContext]
    private(set) var callCount = 0

    init(contexts: [ActiveAppContext]) {
        self.contexts = contexts
    }

    func currentContext() -> ActiveAppContext {
        defer { callCount += 1 }
        let index = min(callCount, max(0, contexts.count - 1))
        return contexts[index]
    }
}

private final class ViewModelFakeInsertionService: InsertionServiceProtocol {
    private(set) var lastTarget: InsertionTarget?

    func insert(text: String, autoPaste: Bool, target: InsertionTarget?, requiresFrozenTarget: Bool) -> InsertionResult {
        lastTarget = target
        return autoPaste ? .pasted : .copiedOnly(reason: .autoPasteDisabled)
    }
}

private final class ViewModelFakeRecordStore: TranscriptRecordStoreProtocol {
    private(set) var records: [TranscriptRecord] = []
    private(set) var diagnosticSessions: [DiagnosticSessionRecord] = []

    func fetchCachedResult(for key: LLMCacheKey) -> LLMResult? { nil }
    func saveCachedResult(_ result: LLMResult, for key: LLMCacheKey) {}
    func appendRecord(_ record: TranscriptRecord) { records.append(record) }
    func fetchRecentRecords(limit: Int) -> [TranscriptRecord] { Array(records.prefix(limit)) }
    func appendDiagnosticSession(_ record: DiagnosticSessionRecord) { diagnosticSessions.append(record) }
    func fetchRecentDiagnosticSessions(limit: Int) -> [DiagnosticSessionRecord] { Array(diagnosticSessions.prefix(limit)) }
    func fetchDiagnosticSessionSummary(limit: Int) -> DiagnosticSessionSummary { .empty }
    func makeCacheKey(profile: PromptProfile, modelID: String, contextPack: ContextPack, deterministicText: String) -> LLMCacheKey {
        LLMCacheKey(
            profileID: "profile",
            profileVersion: 1,
            modelID: modelID,
            contextSignatureHash: "context",
            transcriptHash: "transcript"
        )
    }
    func fetchDictionaryEntries() -> [DictionaryEntryRecord] { [] }
    func replaceDictionaryEntries(_ entries: [GlossaryEntry]) {}
    func upsertDictionaryEntry(from: String, to: String, note: String?) {}
    func fetchFolders() -> [FolderRecord] { [] }
    func fetchNotes(limit: Int) -> [NoteRecord] { [] }
    func fetchActions(limit: Int) -> [ActionRecord] { [] }
}

private struct ViewModelFakeDeterministicFormatter: DeterministicFormatterServiceProtocol {
    func format(text: String, settings: LogicSettings, glossary: [GlossaryEntry]) -> DeterministicResult {
        DeterministicResult(text: text, punctuationAdjusted: false, removedFillers: [], appliedGlossary: [])
    }
}

private final class ViewModelFakeLLMFormatterService: LLMFormatterServiceProtocol {
    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        mode: LogicMode,
        modelID: String,
        apiKey: String?
    ) async throws -> LLMResult {
        throw CancellationError()
    }
}

private final class ViewModelFakeGlobalHotkeyService: GlobalHotkeyServiceProtocol {
    private let startResult: HotkeyStartResult

    init(
        startResult: HotkeyStartResult = HotkeyStartResult(
            backend: .eventMonitor,
            effectiveBinding: .defaultFunctionKey,
            originalBinding: .defaultFunctionKey,
            fallbackWasUsed: false,
            message: "Hotkey active: Fn",
            recommendedFallback: HotkeyBinding.recommendedFallbacks.first,
            permissionGranted: true,
            isActive: true
        )
    ) {
        self.startResult = startResult
    }

    func startMonitoring(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        handler: @escaping (GlobalHotkeyEvent) -> Void
    ) -> HotkeyStartResult {
        HotkeyStartResult(
            backend: startResult.backend,
            effectiveBinding: startResult.effectiveBinding,
            originalBinding: binding,
            fallbackWasUsed: startResult.fallbackWasUsed,
            message: startResult.message,
            recommendedFallback: startResult.recommendedFallback,
            permissionGranted: startResult.permissionGranted,
            isActive: startResult.isActive
        )
    }
    func stopMonitoring() {}
    func hasAccessibilityPermission() -> Bool { true }
    func requestAccessibilityPermissionPrompt() -> Bool { true }
}

private final class ViewModelFakeSoundCueService: SoundCueServiceProtocol {
    func playStartCue() {}
    func playStopCue() {}
}

private final class ViewModelFakeListeningIndicatorService: ListeningIndicatorServiceProtocol {
    private(set) var lastOutcome: ListeningIndicatorOutcome?

    func showListening() {}
    func showProcessing() {}
    func showCompletedBriefly() {
        lastOutcome = .inserted
    }
    func showOutcome(_ outcome: ListeningIndicatorOutcome) {
        lastOutcome = outcome
    }
    func hideListening() {}
}

private actor ViewModelFakeAppleSpeechRuntimeManager: AppleSpeechRuntimeManaging {
    private var currentStatus: AppleSpeechRuntimeStatus
    private let installResult: AppleSpeechRuntimeStatus
    private(set) var reportedProgressValues: [Double?] = []

    init(
        status: AppleSpeechRuntimeStatus = .ready(locale: Locale(identifier: "en_US")),
        installResult: AppleSpeechRuntimeStatus = .ready(locale: Locale(identifier: "en_US"))
    ) {
        self.currentStatus = status
        self.installResult = installResult
    }

    func status(for preferredLocale: Locale) async -> AppleSpeechRuntimeStatus {
        currentStatus
    }

    func installAssets(
        for preferredLocale: Locale,
        progress: (@Sendable (Double?) async -> Void)?
    ) async throws -> AppleSpeechRuntimeStatus {
        reportedProgressValues.append(0.25)
        await progress?(0.25)
        currentStatus = installResult
        reportedProgressValues.append(1)
        await progress?(1)
        return installResult
    }

    func transcribe(audioFileURL: URL, preferredLocale: Locale) async throws -> AppleSpeechRecognitionSnapshot {
        AppleSpeechRecognitionSnapshot(
            text: "hello",
            segments: [.init(start: 0, end: 1, text: "hello")]
        )
    }
}

private struct ViewModelFakeAppleSpeechPermissionProvider: AppleSpeechPermissionProviding {
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus { .authorized }
    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { .authorized }
}
