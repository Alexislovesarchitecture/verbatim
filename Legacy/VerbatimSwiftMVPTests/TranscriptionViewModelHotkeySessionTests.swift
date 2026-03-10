import AVFoundation
import Speech
import XCTest
@testable import VerbatimSwiftMVP

@MainActor
final class TranscriptionViewModelHotkeySessionTests: XCTestCase {
    private let setupCompletedDefaultsKey = "VerbatimSwiftMVP.SetupCompleted"
    private let setupStepDefaultsKey = "VerbatimSwiftMVP.SetupStep"

    override func tearDown() {
        clearSetupPersistence()
        super.tearDown()
    }

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
        XCTAssertEqual(recordStore.diagnosticSessions.count, 0)
        XCTAssertEqual(insertionService.insertCallCount, 0)
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
        XCTAssertEqual(recordStore.records.count, 0)
        XCTAssertEqual(recordStore.diagnosticSessions.count, 0)
        XCTAssertNil(insertionService.lastTarget)
        XCTAssertEqual(insertionService.lastInsertedText, "hello there")
        XCTAssertEqual(sut.statusMessage, "Copied to clipboard. Paste manually.")
    }

    func testFunctionHotkeyFallbackShowsEffectiveBinding() {
        UserDefaults.standard.set(true, forKey: setupCompletedDefaultsKey)
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

    func testViewModelDefaultsToManagedHelperLocalOnlyEvenWhenRemoteStateWasPersisted() {
        UserDefaults.standard.set(TranscriptionMode.remote.rawValue, forKey: "VerbatimSwiftMVP.TranscriptionMode")
        UserDefaults.standard.set(LogicMode.remote.rawValue, forKey: "VerbatimSwiftMVP.LogicMode")
        UserDefaults.standard.set(LocalTranscriptionModel.appleOnDevice.rawValue, forKey: "VerbatimSwiftMVP.LocalModelID")
        UserDefaults.standard.set(LocalTranscriptionEngineMode.appleSpeech.rawValue, forKey: "VerbatimSwiftMVP.LocalEngineMode")
        UserDefaults.standard.set(WhisperKitServerConnectionMode.externalServer.rawValue, forKey: "VerbatimSwiftMVP.WhisperServerConnectionMode")
        UserDefaults.standard.set("http://127.0.0.1:9999", forKey: "VerbatimSwiftMVP.WhisperServerBaseURL")
        defer {
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.TranscriptionMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LogicMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LocalModelID")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.LocalEngineMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.WhisperServerConnectionMode")
            UserDefaults.standard.removeObject(forKey: "VerbatimSwiftMVP.WhisperServerBaseURL")
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
            indicatorService: ViewModelFakeListeningIndicatorService(),
            forceAppleLocalMode: false
        )

        XCTAssertEqual(sut.transcriptionMode, .local)
        XCTAssertEqual(sut.logicMode, .local)
        XCTAssertEqual(sut.selectedLocalEngineMode, .appleSpeech)
        XCTAssertEqual(sut.selectedLocalModel, .appleOnDevice)
        XCTAssertEqual(sut.selectedWhisperServerConnectionMode, .managedHelper)
        XCTAssertEqual(sut.whisperServerBaseURL, "http://127.0.0.1:9999")
    }

    func testSetupRestoresPersistedIncompleteStep() {
        UserDefaults.standard.set(false, forKey: setupCompletedDefaultsKey)
        UserDefaults.standard.set(AppSetupStep.permissions.rawValue, forKey: setupStepDefaultsKey)

        let sut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "whisper-base", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            forceAppleLocalMode: false
        )

        XCTAssertFalse(sut.isSetupCompleted)
        XCTAssertEqual(sut.setupStep, .permissions)
        XCTAssertTrue(sut.shouldShowSetupWizard)
    }

    func testCompleteSetupPersistsCompletionAndClearsSavedStep() {
        let hotkeyService = ViewModelFakeGlobalHotkeyService()
        let sut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "whisper-base", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            globalHotkeyService: hotkeyService,
            forceAppleLocalMode: false
        )

        sut.setupStep = .activation
        sut.completeSetup()

        XCTAssertTrue(sut.isSetupCompleted)
        XCTAssertFalse(sut.shouldShowSetupWizard)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: setupCompletedDefaultsKey), true)
        XCTAssertNil(UserDefaults.standard.string(forKey: setupStepDefaultsKey))
        XCTAssertGreaterThanOrEqual(hotkeyService.startMonitoringCallCount, 1)
    }

    func testLocalWhisperModelListIncludesAllUserFacingSizes() {
        XCTAssertEqual(
            LocalTranscriptionModel.userFacingCases,
            [.whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeV3]
        )
    }

    func testLocalEngineModesExposeOnlyAppleSpeechAndWhisper() {
        XCTAssertEqual(
            LocalTranscriptionEngineMode.userFacingCases,
            [.appleSpeech, .whisperKit]
        )
    }

    func testSetupOnlyExposesTapAndHoldHotkeyModes() {
        XCTAssertEqual(HotkeyTriggerMode.setupCases, [.tapToToggle, .holdToTalk])
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

    func testPrepareApplicationPermissionsRefreshesStateWithoutPromptingTCCDialogs() async throws {
        let permissionProvider = ViewModelRequestingAppleSpeechPermissionProvider()
        let hotkeyService = ViewModelFakeGlobalHotkeyService(permissionGranted: false)
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
            globalHotkeyService: hotkeyService,
            appleSpeechPermissionProvider: permissionProvider
        )

        sut.prepareApplicationPermissions()
        sut.prepareApplicationPermissions()
        try await Task.sleep(nanoseconds: 100_000_000)

        let requestCounts = permissionProvider.requestCounts()
        XCTAssertEqual(requestCounts.microphone, 0)
        XCTAssertEqual(requestCounts.speech, 0)
        XCTAssertEqual(hotkeyService.requestAccessibilityPromptCallCount, 0)
        XCTAssertFalse(sut.setupMicrophonePermissionGranted)
        XCTAssertFalse(sut.canContinueFromSetupPermissions)
    }

    func testSetupPermissionGateDoesNotRequireScreenRecording() {
        let hotkeyService = ViewModelFakeGlobalHotkeyService(permissionGranted: true)
        let screenRecordingProvider = ViewModelFakeScreenRecordingPermissionProvider(hasPermission: false)
        let sut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "whisper-base", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            globalHotkeyService: hotkeyService,
            screenRecordingPermissionProvider: screenRecordingProvider,
            forceAppleLocalMode: false
        )

        XCTAssertTrue(sut.setupMicrophonePermissionGranted)
        XCTAssertTrue(sut.canContinueFromSetupPermissions)
        XCTAssertEqual(sut.setupPermissionRows.map(\.kind), [.microphone, .accessibility])
    }

    func testSetupTranscriptionGateSupportsReadyAppleSpeechRuntime() async throws {
        let runtimeManager = ViewModelFakeAppleSpeechRuntimeManager(
            status: .ready(locale: Locale(identifier: "en_US"))
        )
        let sut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "apple-on-device", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            appleSpeechRuntimeManager: runtimeManager
        )

        sut.selectLocalEngineMode(.appleSpeech)
        sut.refreshAppleSpeechRuntime()

        try await waitUntil { sut.canContinueFromSetupTranscription }
        XCTAssertEqual(sut.selectedLocalModel, .appleOnDevice)
    }

    func testSetupTranscriptionGateRequiresReadyWhisperModel() async throws {
        let unavailableSut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "whisper-base", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            forceAppleLocalMode: false
        )

        XCTAssertFalse(unavailableSut.canContinueFromSetupTranscription)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-setup-ready-\(UUID().uuidString)", isDirectory: true)
        let whisperKitModelManager = WhisperKitModelManager(
            baseDirectoryURL: tempRoot,
            runtimeStatusProvider: {
                WhisperRuntimeStatus(isSupported: true, message: "WhisperKit ready.")
            }
        )
        try installReadyWhisperKitModel(at: tempRoot, model: .whisperBase)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let readySut = makeViewModel(
            coordinator: makeCoordinator(with: .empty(modelID: "whisper-base", responseFormat: "text")),
            recordStore: ViewModelFakeRecordStore(),
            insertionService: ViewModelFakeInsertionService(),
            activeAppContextService: makeActiveContextService(),
            pipeline: makePipeline(
                recordStore: ViewModelFakeRecordStore(),
                insertionService: ViewModelFakeInsertionService(),
                activeAppContextService: makeActiveContextService()
            ),
            indicatorService: ViewModelFakeListeningIndicatorService(),
            whisperKitModelManager: whisperKitModelManager,
            forceAppleLocalMode: false
        )

        try await waitUntil { readySut.canContinueFromSetupTranscription }
        XCTAssertEqual(readySut.selectedWhisperServerConnectionMode, .managedHelper)
    }

    func testSetupPreviewDoesNotInsertPersistHistoryOrDiagnostics() async throws {
        let recordStore = ViewModelFakeRecordStore()
        let insertionService = ViewModelFakeInsertionService()
        let activeContextService = makeActiveContextService()
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-setup-preview-\(UUID().uuidString)", isDirectory: true)
        let whisperKitModelManager = WhisperKitModelManager(
            baseDirectoryURL: tempRoot,
            runtimeStatusProvider: {
                WhisperRuntimeStatus(isSupported: true, message: "WhisperKit ready.")
            }
        )
        try installReadyWhisperKitModel(at: tempRoot, model: .whisperBase)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let transcript = Transcript(
            rawText: "preview transcript",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "whisper-base",
            responseFormat: "text"
        )
        let coordinator = makeCoordinator(
            with: transcript,
            frames: Array(repeating: makeFrame(amplitude: 8_000, sampleCount: 1600), count: 3)
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
            indicatorService: ViewModelFakeListeningIndicatorService(),
            whisperKitModelManager: whisperKitModelManager,
            forceAppleLocalMode: false
        )

        sut.autoFormatEnabled = false
        try await waitUntil { sut.canStartForCurrentMode }
        sut.start(fromHotkey: true, disposition: .setupPreview)
        try await waitUntil { sut.state == .recording }

        sut.stop()
        try await waitUntil { sut.state == .done }

        XCTAssertEqual(recordStore.records.count, 0)
        XCTAssertEqual(recordStore.diagnosticSessions.count, 0)
        XCTAssertEqual(insertionService.insertCallCount, 0)
        XCTAssertEqual(sut.setupActivationTestTranscript, "preview transcript")
        XCTAssertEqual(sut.setupActivationTestMessage, "Hotkey test transcript ready.")
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
        XCTAssertEqual(recordStore.records.count, 0)
        XCTAssertEqual(recordStore.diagnosticSessions.count, 0)
        XCTAssertEqual(insertionService.lastInsertedText, "hello local logic")
        XCTAssertEqual(sut.statusMessage, "Copied to clipboard. Paste manually.")
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

    private func makeCoordinator(
        with transcript: Transcript,
        frames: [AudioPCM16Frame] = []
    ) -> TranscriptionCoordinator {
        TranscriptionCoordinator(
            recorder: ViewModelFakeAudioRecorder(
                artifact: AudioRecordingArtifact(
                    audioFileURL: temporaryAudioURL(),
                    frameStream: makeFrameStream(frames: frames)
                )
            ),
            remoteEngine: ViewModelFakeRemoteEngine(transcript: transcript),
            localEngine: ViewModelFakeLocalEngine(transcript: transcript),
            modelCatalogService: ViewModelFakeModelCatalog()
        )
    }

    private func makeActiveContextService() -> SequencedActiveAppContextService {
        SequencedActiveAppContextService(
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
    }

    private func makeViewModel(
        coordinator: TranscriptionCoordinator,
        recordStore: ViewModelFakeRecordStore,
        insertionService: ViewModelFakeInsertionService,
        activeAppContextService: SequencedActiveAppContextService,
        pipeline: PostTranscriptionPipeline,
        indicatorService: ViewModelFakeListeningIndicatorService,
        globalHotkeyService: GlobalHotkeyServiceProtocol = ViewModelFakeGlobalHotkeyService(),
        whisperKitModelManager: WhisperKitModelManager? = nil,
        appleSpeechRuntimeManager: AppleSpeechRuntimeManaging = ViewModelFakeAppleSpeechRuntimeManager(),
        appleSpeechPermissionProvider: AppleSpeechPermissionProviding = ViewModelFakeAppleSpeechPermissionProvider(),
        screenRecordingPermissionProvider: ScreenRecordingPermissionProviding = ViewModelFakeScreenRecordingPermissionProvider(),
        missingPrivacyUsageDescription: @escaping @Sendable (AppPrivacyUsageDescription) -> String? = { _ in nil },
        forceAppleLocalMode: Bool = true
    ) -> TranscriptionViewModel {
        let sut = TranscriptionViewModel(
            whisperKitModelManager: whisperKitModelManager,
            appleSpeechRuntimeManager: appleSpeechRuntimeManager,
            appleSpeechPermissionProvider: appleSpeechPermissionProvider,
            screenRecordingPermissionProvider: screenRecordingPermissionProvider,
            missingPrivacyUsageDescription: missingPrivacyUsageDescription,
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
        if forceAppleLocalMode {
            sut.selectLocalEngineMode(.appleSpeech)
        }
        return sut
    }

    private func clearSetupPersistence() {
        UserDefaults.standard.removeObject(forKey: setupCompletedDefaultsKey)
        UserDefaults.standard.removeObject(forKey: setupStepDefaultsKey)
    }

    private func installReadyWhisperKitModel(at baseDirectoryURL: URL, model: LocalTranscriptionModel) throws {
        let modelDirectory = LocalRuntimePaths(baseDirectoryURL: baseDirectoryURL)
            .whisperKitRoot
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai_whisper-\(model.whisperKitModelName ?? model.rawValue)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data("encoder".utf8).write(to: modelDirectory.appendingPathComponent("AudioEncoder.mlmodelc"))
        try Data("decoder".utf8).write(to: modelDirectory.appendingPathComponent("TextDecoder.mlmodelc"))
        try Data("mel".utf8).write(to: modelDirectory.appendingPathComponent("MelSpectrogram.mlmodelc"))
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
    private(set) var lastInsertedText: String?
    private(set) var insertCallCount = 0

    func insert(text: String, autoPaste: Bool, target: InsertionTarget?, requiresFrozenTarget: Bool) -> InsertionResult {
        insertCallCount += 1
        lastInsertedText = text
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
    private let permissionGranted: Bool
    private(set) var startMonitoringCallCount = 0
    private(set) var stopMonitoringCallCount = 0
    private(set) var requestAccessibilityPromptCallCount = 0
    private var handler: ((GlobalHotkeyEvent) -> Void)?

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
        ),
        permissionGranted: Bool = true
    ) {
        self.startResult = startResult
        self.permissionGranted = permissionGranted
    }

    func startMonitoring(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        handler: @escaping (GlobalHotkeyEvent) -> Void
    ) -> HotkeyStartResult {
        startMonitoringCallCount += 1
        self.handler = handler
        return HotkeyStartResult(
            backend: startResult.backend,
            effectiveBinding: startResult.effectiveBinding,
            originalBinding: binding,
            fallbackWasUsed: startResult.fallbackWasUsed,
            message: startResult.message,
            recommendedFallback: startResult.recommendedFallback,
            permissionGranted: permissionGranted,
            isActive: startResult.isActive
        )
    }
    func stopMonitoring() {
        stopMonitoringCallCount += 1
        handler = nil
    }
    func hasAccessibilityPermission() -> Bool { permissionGranted }
    func requestAccessibilityPermissionPrompt() -> Bool {
        requestAccessibilityPromptCallCount += 1
        return permissionGranted
    }

    func emit(_ event: GlobalHotkeyEvent) {
        handler?(event)
    }
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
    func requestMicrophoneAccess() async -> Bool { true }
    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { .authorized }
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus { .authorized }
}

private struct ViewModelFakeScreenRecordingPermissionProvider: ScreenRecordingPermissionProviding {
    var hasPermissionValue: Bool = false
    var requestPermissionValue: Bool? = nil

    init(hasPermission: Bool = false, requestPermission: Bool? = nil) {
        self.hasPermissionValue = hasPermission
        self.requestPermissionValue = requestPermission
    }

    func hasPermission() -> Bool {
        hasPermissionValue
    }

    func requestPermission() -> Bool {
        requestPermissionValue ?? hasPermissionValue
    }
}

private final class ViewModelRequestingAppleSpeechPermissionProvider: AppleSpeechPermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var microphoneStatus: AVAuthorizationStatus = .notDetermined
    private var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    private var microphoneRequestCount = 0
    private var speechRequestCount = 0

    func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        lock.withLock { microphoneStatus }
    }

    func requestMicrophoneAccess() async -> Bool {
        lock.withLock {
            microphoneRequestCount += 1
            microphoneStatus = .authorized
        }
        return true
    }

    func speechAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        lock.withLock { speechStatus }
    }

    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        lock.withLock {
            speechRequestCount += 1
            speechStatus = .authorized
        }
        return .authorized
    }

    func requestCounts() -> (microphone: Int, speech: Int) {
        lock.withLock {
            (microphoneRequestCount, speechRequestCount)
        }
    }
}
