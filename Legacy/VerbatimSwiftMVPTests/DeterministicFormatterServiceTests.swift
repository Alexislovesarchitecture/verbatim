import XCTest
@testable import VerbatimSwiftMVP

@available(macOS 26.0, *)
final class DeterministicFormatterServiceTests: XCTestCase {
    func testDeterministicFormattingRemovesFillerAndAppliesGlossary() {
        let sut = DeterministicFormatterService()
        var settings = LogicSettings()
        settings.removeFillerWords = true

        let glossary = [GlossaryEntry(from: "open ai", to: "OpenAI")]
        let result = sut.format(text: "um open ai can you draft a note", settings: settings, glossary: glossary)

        XCTAssertEqual(result.appliedGlossary.count, 1)
        XCTAssertTrue(result.removedFillers.contains { $0.lowercased().contains("um") })
        XCTAssertTrue(result.text.contains("OpenAI"))
        XCTAssertTrue(result.text.hasSuffix("."))
    }

    func testDeterministicFormattingPreservesFillersWhenDisabled() {
        let sut = DeterministicFormatterService()
        var settings = LogicSettings()
        settings.removeFillerWords = false

        let result = sut.format(text: "uh this should keep filler", settings: settings, glossary: [])

        XCTAssertTrue(result.removedFillers.isEmpty)
        XCTAssertTrue(result.text.lowercased().contains("uh"))
    }

    func testDeterministicFormattingPreservesIMeanForResolverStage() {
        let sut = DeterministicFormatterService()
        var settings = LogicSettings()
        settings.removeFillerWords = true

        let result = sut.format(text: "send that to John i mean Jane", settings: settings, glossary: [])

        XCTAssertFalse(result.removedFillers.contains { $0.lowercased().contains("i mean") })
        XCTAssertTrue(result.text.lowercased().contains("i mean"))
    }
}
