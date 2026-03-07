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
                promptProfiles: [makeProfile(id: "cleanup")],
                logicMode: .remote,
                logicSettings: LogicSettings(),
                refineSettings: RefineSettings(workEnabled: true, emailEnabled: false, personalEnabled: false, otherEnabled: false, previewBeforeInsert: false),
                interactionSettings: InteractionSettings(),
                autoFormatEnabled: true,
                canRunAutoFormat: true,
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

private final class FakeLLMFormatterService: LLMFormatterServiceProtocol {
    let result: LLMResult

    init(result: LLMResult) {
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
        result
    }
}

private final class FakeRecordStore: TranscriptRecordStoreProtocol {
    private(set) var records: [TranscriptRecord] = []

    func fetchCachedResult(for key: LLMCacheKey) -> LLMResult? { nil }
    func saveCachedResult(_ result: LLMResult, for key: LLMCacheKey) {}
    func appendRecord(_ record: TranscriptRecord) { records.append(record) }
    func makeCacheKey(profile: PromptProfile, modelID: String, contextPack: ContextPack, deterministicText: String) -> LLMCacheKey {
        LLMCacheKey(
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            contextSignatureHash: "context",
            transcriptHash: "transcript"
        )
    }
}

private final class FakeInsertionService: InsertionServiceProtocol {
    private(set) var insertedTexts: [String] = []

    func insert(text: String, autoPaste: Bool) throws {
        insertedTexts.append(text)
    }
}

private struct FakeActiveAppContextService: ActiveAppContextServiceProtocol {
    let styleCategory: StyleCategory

    func currentContext() -> ActiveAppContext {
        ActiveAppContext(
            appName: "Mail",
            bundleID: "com.apple.mail",
            styleCategory: styleCategory,
            windowTitle: "Inbox",
            focusedElementRole: "AXTextArea"
        )
    }
}
