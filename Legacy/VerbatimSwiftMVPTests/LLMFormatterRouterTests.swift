import XCTest
@testable import VerbatimSwiftMVP

@available(macOS 26.0, *)
final class LLMFormatterRouterTests: XCTestCase {
    @MainActor
    func testRouterUsesCacheOnSecondCall() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-router-\(UUID().uuidString)", isDirectory: true)
        let store = TranscriptRecordStore(baseDirectoryURL: tempRoot)
        let remote = MockRemoteService()
        let local = MockLocalService()
        let router = LLMFormatterRouter(remoteService: remote, localService: local, recordStore: store)

        let profile = PromptProfile(
            id: "cleanup",
            version: 1,
            name: "Cleanup",
            styleCategory: nil,
            enabled: true,
            outputMode: .text,
            instructionPrefix: "x",
            schema: nil,
            options: nil
        )
        let context = ContextPack(
            activeAppName: "Mail",
            bundleID: "com.apple.mail",
            styleCategory: .email,
            stylePreset: .formal,
            styleSummary: "Caps: full. Punctuation: full. Format: email. Structure: greeting, body, sign-off.",
            windowTitle: "Inbox",
            focusedElementRole: "AXTextArea",
            punctuationMode: "sentence",
            fillerRemovalEnabled: true,
            autoDetectLists: false,
            outputFormat: .auto,
            selfCorrectionMode: .keepFinal,
            flagLowConfidenceWords: false,
            reasoningEffort: .modelDefault,
            glossary: [],
            sessionMemory: []
        )

        let first = try await router.refine(
            deterministicText: "hello",
            contextPack: context,
            profile: profile,
            mode: .remote,
            modelID: "gpt-5-mini",
            apiKey: "key"
        )

        let second = try await router.refine(
            deterministicText: "hello",
            contextPack: context,
            profile: profile,
            mode: .remote,
            modelID: "gpt-5-mini",
            apiKey: "key"
        )

        let callCount = await remote.recordedCalls()
        XCTAssertFalse(first.fromCache)
        XCTAssertTrue(second.fromCache)
        XCTAssertEqual(callCount, 1)
    }
}

@available(macOS 26.0, *)
private actor MockRemoteService: OpenAIRemoteRefineServiceProtocol {
    private var calls = 0

    func recordedCalls() -> Int {
        calls
    }

    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        apiKey: String?,
        modelID: String
    ) async throws -> LLMResult {
        calls += 1
        return LLMResult(
            text: deterministicText + ".",
            json: nil,
            status: .success,
            validationStatus: .notApplicable,
            tokens: 1,
            cachedTokens: 0,
            latencyMs: 10,
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            fromCache: false
        )
    }
}

@available(macOS 26.0, *)
private final class MockLocalService: LocalLLMRefineServiceProtocol {
    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        modelID: String
    ) async throws -> LLMResult {
        LLMResult(
            text: deterministicText,
            json: nil,
            status: .success,
            validationStatus: .notApplicable,
            tokens: 0,
            cachedTokens: 0,
            latencyMs: 0,
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: modelID,
            fromCache: false
        )
    }
}
