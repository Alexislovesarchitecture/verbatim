import XCTest
@testable import VerbatimSwiftMVP

final class OllamaLocalLogicServiceTests: XCTestCase {
    func testOllamaThinkArgumentMapsSupportedValues() {
        XCTAssertNil(OllamaLocalLogicService.ollamaThinkArgument(for: .modelDefault))
        XCTAssertEqual(OllamaLocalLogicService.ollamaThinkArgument(for: .minimal), "low")
        XCTAssertEqual(OllamaLocalLogicService.ollamaThinkArgument(for: .low), "low")
        XCTAssertEqual(OllamaLocalLogicService.ollamaThinkArgument(for: .medium), "medium")
        XCTAssertEqual(OllamaLocalLogicService.ollamaThinkArgument(for: .high), "high")
        XCTAssertEqual(OllamaLocalLogicService.ollamaThinkArgument(for: .off), "false")
    }

    func testSanitizedVisibleTextDropsThinkingSections() {
        let raw = """
        Thinking...
        This is the hidden trace.
        ...done thinking.

        Testing 1 2 3 which is 5 words.
        """

        XCTAssertEqual(
            OllamaLocalLogicService.sanitizedVisibleText(raw),
            "Testing 1 2 3 which is 5 words."
        )
    }

    func testSanitizedVisibleTextDropsThinkTags() {
        let raw = "<think>internal reasoning</think>\nFinal text only."
        XCTAssertEqual(OllamaLocalLogicService.sanitizedVisibleText(raw), "Final text only.")
    }
}
