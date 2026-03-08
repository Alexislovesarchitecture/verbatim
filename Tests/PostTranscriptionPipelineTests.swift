import XCTest
@testable import VerbatimSwiftMVP

@MainActor
final class PostTranscriptionPipelineTests: XCTestCase {
    func testProcessCompletedTranscriptFormatsInsertsAndPersists() async {
        let recordStore = FakeRecordStore()
        let insertionService = FakeInsertionService()
        let llmService = FakeLLMFormatterService(
            result: LLMResult(
                text: "Hello there!",
                json: nil,
                status: .success,
                validationStatus: .notApplicable,
                tokens: 12,
                cachedTokens: 0,
                latencyMs: 42,
                profileID: "cleanup",
                profileVersion: 1,
                modelID: "gpt-5-mini",
                fromCache: false
            )
        )
        let pipeline = PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: FakeDeterministicFormatter(),
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: FakeActiveAppContextService(styleCategory: .work),
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            llmFormatterService: llmService
        )

        let result = await pipeline.processCompletedTranscript(
            PostTranscriptionPipelineRequest(
                transcript: Transcript(
                    rawText: "hello there",
                    segments: [],
                    tokenLogprobs: nil,
                    lowConfidenceSpans: [],
                    modelID: "gpt-4o-mini-transcribe",
                    responseFormat: "json"
                ),
                recordingSessionContext: nil,
                activeAppContextOverride: nil,
                glossaryEntries: [],
                promptProfiles: [makeProfile(id: "cleanup")],
                transcriptionMode: .remote,
                logicMode: .remote,
                logicSettings: LogicSettings(),
                refineSettings: RefineSettings(workEnabled: true, emailEnabled: false, personalEnabled: false, otherEnabled: false, previewBeforeInsert: false),
                interactionSettings: InteractionSettings(),
                autoFormatEnabled: true,
                canRunAutoFormat: true,
                transcriptionEngineID: "openai-batch-sse",
                transcriptionLatencyMs: 80,
                effectiveAPIKey: "test-key",
                selectedRemoteLogicModelID: "gpt-5-mini",
                selectedLocalLogicModelID: "gpt-oss-20b",
                forceInsertion: false
            )
        )

        XCTAssertEqual(result.formattedOutput?.clean_text, "Hello there!")
        XCTAssertEqual(result.latestLLMResult?.modelID, "gpt-5-mini")
        XCTAssertEqual(insertionService.insertedTexts, ["Hello there!"])
        XCTAssertEqual(recordStore.records.count, 1)
        XCTAssertEqual(llmService.lastProfileID, "auto_style_work_formal")
    }

    func testRunManualReformatReturnsActionItemsPreview() async {
        let recordStore = FakeRecordStore()
        let insertionService = FakeInsertionService()
        let llmService = FakeLLMFormatterService(
            result: LLMResult(
                text: nil,
                json: #"{"items":[{"task":"Follow up","owner":"Alexis","due_date":"2026-03-06"}]}"#,
                status: .success,
                validationStatus: .valid,
                tokens: 15,
                cachedTokens: 0,
                latencyMs: 55,
                profileID: "action_items",
                profileVersion: 1,
                modelID: "gpt-5-mini",
                fromCache: false
            )
        )
        let pipeline = PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: FakeDeterministicFormatter(),
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: FakeActiveAppContextService(styleCategory: .work),
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            llmFormatterService: llmService
        )

        let result = await pipeline.runManualReformat(
            ManualReformatRequest(
                transcript: Transcript(
                    rawText: "follow up with client",
                    segments: [],
                    tokenLogprobs: nil,
                    lowConfidenceSpans: [],
                    modelID: "gpt-4o-mini-transcribe",
                    responseFormat: "json"
                ),
                activeAppContextOverride: nil,
                glossaryEntries: [],
                profile: makeProfile(id: "action_items", outputMode: .jsonSchema),
                logicMode: .remote,
                logicSettings: LogicSettings(),
                refineSettings: RefineSettings(workEnabled: true, emailEnabled: false, personalEnabled: false, otherEnabled: false, previewBeforeInsert: true),
                interactionSettings: InteractionSettings(),
                effectiveAPIKey: "test-key",
                selectedRemoteLogicModelID: "gpt-5-mini",
                selectedLocalLogicModelID: "gpt-oss-20b"
            )
        )

        XCTAssertNil(result.formattedOutput)
        XCTAssertEqual(result.pendingActionItemsJSON, #"{"items":[{"task":"Follow up","owner":"Alexis","due_date":"2026-03-06"}]}"#)
        XCTAssertEqual(result.pendingActionItemsRenderedText, "1. Follow up (owner: Alexis, due: 2026-03-06)")
        XCTAssertTrue(insertionService.insertedTexts.isEmpty)
        XCTAssertEqual(recordStore.records.count, 1)
    }

    func testProcessCompletedTranscriptResolvesIntentBeforeDeterministicFormatting() async {
        let recordStore = FakeRecordStore()
        let insertionService = FakeInsertionService()
        let deterministicFormatter = CapturingDeterministicFormatter()
        let pipeline = PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: deterministicFormatter,
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: FakeActiveAppContextService(styleCategory: .work),
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            llmFormatterService: FakeLLMFormatterService(result: nil)
        )

        let result = await pipeline.processCompletedTranscript(
            PostTranscriptionPipelineRequest(
                transcript: Transcript(
                    rawText: "send that to John, I mean Jane",
                    segments: [],
                    tokenLogprobs: nil,
                    lowConfidenceSpans: [],
                    modelID: "gpt-4o-mini-transcribe",
                    responseFormat: "json"
                ),
                recordingSessionContext: nil,
                activeAppContextOverride: nil,
                glossaryEntries: [],
                promptProfiles: [makeProfile(id: "cleanup")],
                transcriptionMode: .remote,
                logicMode: .remote,
                logicSettings: LogicSettings(),
                refineSettings: RefineSettings(workEnabled: false, emailEnabled: false, personalEnabled: false, otherEnabled: false, previewBeforeInsert: true),
                interactionSettings: InteractionSettings(),
                autoFormatEnabled: false,
                canRunAutoFormat: false,
                transcriptionEngineID: "openai-batch-sse",
                transcriptionLatencyMs: 40,
                effectiveAPIKey: nil,
                selectedRemoteLogicModelID: "gpt-5-mini",
                selectedLocalLogicModelID: "gpt-oss-20b",
                forceInsertion: false
            )
        )

        XCTAssertEqual(deterministicFormatter.lastInputText, "send that to Jane")
        XCTAssertEqual(result.deterministicResult.text, "Send That To Jane.")
        XCTAssertTrue(result.formattedOutput?.self_corrections.contains { $0.contains("I mean") || $0.contains("i mean") } ?? false)
    }

    func testProcessCompletedTranscriptUsesCapturedInsertionTarget() async {
        let recordStore = FakeRecordStore()
        let insertionService = FakeInsertionService()
        let capturedContext = ActiveAppContext(
            appName: "Messages",
            bundleID: "com.apple.MobileSMS",
            processIdentifier: 999,
            styleCategory: .personal,
            windowTitle: "Chat",
            focusedElementRole: "AXTextArea"
        )
        let pipeline = PostTranscriptionPipeline(
            transcriptIntentResolver: TranscriptIntentResolver(),
            deterministicFormatter: FakeDeterministicFormatter(),
            contextPackBuilder: ContextPackBuilder(),
            activeAppContextService: FakeActiveAppContextService(styleCategory: .work),
            transcriptRecordStore: recordStore,
            insertionService: insertionService,
            llmFormatterService: FakeLLMFormatterService(result: nil)
        )

        _ = await pipeline.processCompletedTranscript(
            PostTranscriptionPipelineRequest(
                transcript: Transcript(
                    rawText: "hello there",
                    segments: [],
                    tokenLogprobs: nil,
                    lowConfidenceSpans: [],
                    modelID: "gpt-4o-mini-transcribe",
                    responseFormat: "json"
                ),
                recordingSessionContext: RecordingSessionContext(
                    activeAppContext: capturedContext,
                    insertionTarget: capturedContext.insertionTarget,
                    stylePreset: .casual,
                    triggerSource: .hotkey,
                    triggerMode: .holdToTalk
                ),
                activeAppContextOverride: capturedContext,
                glossaryEntries: [],
                promptProfiles: [makeProfile(id: "cleanup")],
                transcriptionMode: .remote,
                logicMode: .remote,
                logicSettings: LogicSettings(),
                refineSettings: RefineSettings(workEnabled: false, emailEnabled: false, personalEnabled: true, otherEnabled: false, previewBeforeInsert: false),
                interactionSettings: InteractionSettings(),
                autoFormatEnabled: false,
                canRunAutoFormat: false,
                transcriptionEngineID: LocalTranscriptionBackend.whisperCpp.engineID,
                transcriptionLatencyMs: 60,
                effectiveAPIKey: nil,
                selectedRemoteLogicModelID: "gpt-5-mini",
                selectedLocalLogicModelID: "gpt-oss-20b",
                forceInsertion: true
            )
        )

        XCTAssertEqual(insertionService.lastTarget?.bundleID, "com.apple.MobileSMS")
        XCTAssertEqual(insertionService.lastTarget?.processIdentifier, 999)
        XCTAssertEqual(recordStore.diagnosticSessions.first?.modelID, "gpt-4o-mini-transcribe")
        XCTAssertEqual(recordStore.diagnosticSessions.first?.logicModelID, "gpt-5-mini")
        XCTAssertEqual(recordStore.diagnosticSessions.first?.reasoningEffort, LogicSettings().reasoningEffort.rawValue)
    }

    private func makeProfile(id: String, outputMode: PromptOutputMode = .text) -> PromptProfile {
        PromptProfile(
            id: id,
            version: 1,
            name: id,
            styleCategory: nil,
            enabled: true,
            outputMode: outputMode,
            instructionPrefix: "Test",
            schema: nil,
            options: nil
        )
    }
}

private struct FakeDeterministicFormatter: DeterministicFormatterServiceProtocol {
    func format(text: String, settings: LogicSettings, glossary: [GlossaryEntry]) -> DeterministicResult {
        DeterministicResult(
            text: text.capitalized + ".",
            punctuationAdjusted: true,
            removedFillers: [],
            appliedGlossary: []
        )
    }
}

private final class CapturingDeterministicFormatter: DeterministicFormatterServiceProtocol {
    private(set) var lastInputText: String?

    func format(text: String, settings: LogicSettings, glossary: [GlossaryEntry]) -> DeterministicResult {
        lastInputText = text
        return DeterministicResult(
            text: text.capitalized + ".",
            punctuationAdjusted: true,
            removedFillers: [],
            appliedGlossary: []
        )
    }
}

private final class FakeLLMFormatterService: LLMFormatterServiceProtocol {
    let result: LLMResult?
    private(set) var lastProfileID: String?

    init(result: LLMResult?) {
        self.result = result
    }

    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        mode: LogicMode,
        modelID: String,
        apiKey: String?
    ) async throws -> LLMResult {
        lastProfileID = profile.id
        guard let result else {
            throw CancellationError()
        }
        return result
    }
}

private final class FakeRecordStore: TranscriptRecordStoreProtocol {
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
            profileID: profile.id,
            profileVersion: profile.version,
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

private final class FakeInsertionService: InsertionServiceProtocol {
    private(set) var insertedTexts: [String] = []
    private(set) var lastTarget: InsertionTarget?
    private(set) var lastRequiresFrozenTarget = false

    func insert(text: String, autoPaste: Bool, target: InsertionTarget?, requiresFrozenTarget: Bool) -> InsertionResult {
        insertedTexts.append(text)
        lastTarget = target
        lastRequiresFrozenTarget = requiresFrozenTarget
        return autoPaste ? .pasted : .copiedOnly(reason: .autoPasteDisabled)
    }
}

private struct FakeActiveAppContextService: ActiveAppContextServiceProtocol {
    let styleCategory: StyleCategory

    func currentContext() -> ActiveAppContext {
        ActiveAppContext(
            appName: "Mail",
            bundleID: "com.apple.mail",
            processIdentifier: 123,
            styleCategory: styleCategory,
            windowTitle: "Inbox",
            focusedElementRole: "AXTextArea"
        )
    }
}
