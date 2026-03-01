import XCTest
import Foundation
@testable import Verbatim

final class FormattingPipelineTests: XCTestCase {
    func testDictionaryReplacementsAreAppliedInOrder() {
        let pipeline = FormattingPipeline()
        let style = StyleProfile(category: .personal, tone: .casual)

        let entries = [
            DictionaryEntry(scope: .personal, kind: .term, input: "Eulogio"),
            DictionaryEntry(scope: .personal, kind: .replacement, input: "whispr", output: "Wispr"),
            DictionaryEntry(scope: .personal, kind: .expansion, input: "btw", output: "by the way")
        ]

        let result = pipeline.apply(
            rawText: "talk to Eulogio and send this via whispr btw please",
            styleProfile: style,
            dictionaryEntries: entries,
            snippetEntries: [],
            applyDictionaryReplacements: true,
            applySnippets: false,
            snippetGlobalExactMatch: false,
            removeFillers: false,
            interpretVoiceCommands: false
        )

        XCTAssertTrue(result.contains("Wispr"))
        XCTAssertTrue(result.contains("by the way"))
        XCTAssertTrue(result.hasSuffix("."))
    }

    func testSnippetExpansionRules() {
        let pipeline = FormattingPipeline()
        let style = StyleProfile(category: .personal, tone: .casual)
        let snippets = [
            SnippetEntry(scope: .personal, trigger: "btw", content: "by the way"),
            SnippetEntry(scope: .personal, trigger: "sig", content: "signature", requireExactMatch: true)
        ]

        let phraseMatch = pipeline.apply(
            rawText: "I am available btw today",
            styleProfile: style,
            dictionaryEntries: [],
            snippetEntries: snippets,
            applyDictionaryReplacements: false,
            applySnippets: true,
            snippetGlobalExactMatch: false,
            removeFillers: false,
            interpretVoiceCommands: false
        )
        XCTAssertTrue(phraseMatch.contains("by the way"))

        let exactMatch = pipeline.apply(
            rawText: "sig",
            styleProfile: style,
            dictionaryEntries: [],
            snippetEntries: snippets,
            applyDictionaryReplacements: false,
            applySnippets: true,
            snippetGlobalExactMatch: true,
            removeFillers: false,
            interpretVoiceCommands: false
        )
        XCTAssertEqual(exactMatch, "signature.")
    }

    func testTonePunctuationAndFillers() {
        let pipeline = FormattingPipeline()
        let style = StyleProfile(
            category: .personal,
            tone: .formal,
            removeFillers: true,
            interpretVoiceCommands: true
        )
        let output = pipeline.apply(
            rawText: "um, this is, uh",
            styleProfile: style,
            dictionaryEntries: [],
            snippetEntries: [],
            applyDictionaryReplacements: false,
            applySnippets: false,
            snippetGlobalExactMatch: false,
            removeFillers: true,
            interpretVoiceCommands: true
        )

        XCTAssertFalse(output.lowercased().contains("um"))
        XCTAssertFalse(output.lowercased().contains("uh"))
    }
}
