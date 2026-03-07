import XCTest
@testable import VerbatimSwiftMVP

final class TranscriptRecordStoreTests: XCTestCase {
    func testCacheRoundTrip() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("verbatim-tests-\(UUID().uuidString)", isDirectory: true)
        let sut = TranscriptRecordStore(baseDirectoryURL: tempRoot)

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
            windowTitle: "Inbox",
            focusedElementRole: "AXTextArea",
            punctuationMode: "sentence",
            fillerRemovalEnabled: true,
            autoDetectLists: false,
            glossary: [],
            sessionMemory: []
        )

        let key = sut.makeCacheKey(profile: profile, modelID: "gpt-5-mini", contextPack: context, deterministicText: "hello")
        let original = LLMResult(
            text: "hello.",
            json: nil,
            status: .success,
            validationStatus: .notApplicable,
            tokens: 11,
            cachedTokens: 9,
            latencyMs: 120,
            profileID: profile.id,
            profileVersion: profile.version,
            modelID: "gpt-5-mini",
            fromCache: false
        )

        sut.saveCachedResult(original, for: key)
        let cached = sut.fetchCachedResult(for: key)

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.text, "hello.")
        XCTAssertEqual(cached?.tokens, 11)
        XCTAssertEqual(cached?.cachedTokens, 9)
        XCTAssertEqual(cached?.fromCache, true)
    }
}
