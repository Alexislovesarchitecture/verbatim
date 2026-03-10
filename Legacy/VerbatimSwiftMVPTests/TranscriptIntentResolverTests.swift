import XCTest
@testable import VerbatimSwiftMVP

@available(macOS 26.0, *)
final class TranscriptIntentResolverTests: XCTestCase {
    private let sut = TranscriptIntentResolver()

    func testExplicitSpelledWordCollapseReplacesPreviousWord() {
        let result = sut.resolve(
            transcript: makeTranscript("my last name is fatty, that's B A T T Y"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .personal)
        )

        XCTAssertEqual(result.text, "my last name is batty")
        XCTAssertTrue(result.corrections.contains { $0.kind == .spelledWordCollapse })
    }

    func testBareLetterSequenceStaysLiteralWhenAmbiguous() {
        let result = sut.resolve(
            transcript: makeTranscript("B A T T Y"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .other)
        )

        XCTAssertEqual(result.text, "B A T T Y")
        XCTAssertTrue(result.notes.contains { $0.contains("ambiguous") })
    }

    func testLiteralCuePreservesSpelledLetters() {
        let result = sut.resolve(
            transcript: makeTranscript("type B A T T Y exactly"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .personal)
        )

        XCTAssertEqual(result.text, "type B A T T Y exactly")
        XCTAssertTrue(result.corrections.contains { $0.kind == .literalSpellingPreserved })
    }

    func testActuallyReplacesNearestPhrase() {
        let result = sut.resolve(
            transcript: makeTranscript("let's meet tomorrow, actually Tuesday"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "let's meet Tuesday")
        XCTAssertTrue(result.corrections.contains { $0.cue == "actually" })
    }

    func testIMeanReplacesSingleTargetToken() {
        let result = sut.resolve(
            transcript: makeTranscript("send that to John, I mean Jane"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "send that to Jane")
        XCTAssertTrue(result.corrections.contains { $0.kind == .localReplacement })
    }

    func testScratchThatRestartsLocalClause() {
        let result = sut.resolve(
            transcript: makeTranscript("the budget is five thousand, scratch that, six thousand"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "the budget is six thousand")
        XCTAssertTrue(result.corrections.contains { $0.kind == .restart })
    }

    func testKeepAllPreservesOriginalAndCorrection() {
        let result = sut.resolve(
            transcript: makeTranscript("let's meet tomorrow, actually Tuesday"),
            selfCorrectionMode: .keepAll,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "let's meet tomorrow, actually Tuesday")
    }

    func testAnnotateKeepsCleanFinalAndMarksDisposition() {
        let result = sut.resolve(
            transcript: makeTranscript("send that to John, I mean Jane"),
            selfCorrectionMode: .annotate,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "send that to Jane")
        XCTAssertTrue(result.corrections.contains { $0.disposition == .annotated })
    }

    func testGlossarySupportsProperNounCollapse() {
        let result = sut.resolve(
            transcript: makeTranscript("send this to yulogio, spelled E U L O G I O"),
            selfCorrectionMode: .keepFinal,
            glossary: [GlossaryEntry(from: "yulogio", to: "Eulogio")],
            activeContext: makeContext(styleCategory: .personal)
        )

        XCTAssertEqual(result.text, "send this to Eulogio")
    }

    func testGlossaryDoesNotForceCollapseWithoutCue() {
        let result = sut.resolve(
            transcript: makeTranscript("sitescape and S I T E S C A P E"),
            selfCorrectionMode: .keepFinal,
            glossary: [GlossaryEntry(from: "site scape", to: "Sitescape")],
            activeContext: makeContext(styleCategory: .other)
        )

        XCTAssertEqual(result.text, "sitescape and S I T E S C A P E")
    }

    func testPreambleClauseIsIgnoredBeforeCorrection() {
        let result = sut.resolve(
            transcript: makeTranscript("I can do Monday. no, actually Wednesday afternoon"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "I can do Wednesday afternoon")
    }

    func testStackedRewriteInstructionsUseFollowingReplacementClause() {
        let result = sut.resolve(
            transcript: makeTranscript("Howdy, tomorrow I'm going to the movies. Actually, rewrite that. Today I'm going to the movies"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .personal)
        )

        XCTAssertEqual(result.text, "Howdy, Today I'm going to the movies")
        XCTAssertTrue(result.corrections.contains { $0.cue == "actually" })
    }

    func testDeleteThatRemovesPreviousClauseWhenNoReplacementProvided() {
        let result = sut.resolve(
            transcript: makeTranscript("Let's meet tomorrow, delete that"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "")
        XCTAssertTrue(result.corrections.contains { $0.cue == "delete that" })
    }

    func testFormattingInstructionIsDroppedFromOutput() {
        let result = sut.resolve(
            transcript: makeTranscript("Can you summarize this, make that a list"),
            selfCorrectionMode: .keepFinal,
            glossary: [],
            activeContext: makeContext(styleCategory: .work)
        )

        XCTAssertEqual(result.text, "Can you summarize this")
        XCTAssertTrue(result.notes.contains { $0.contains("formatting instruction") })
    }

    private func makeTranscript(_ text: String) -> Transcript {
        Transcript(
            rawText: text,
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: "gpt-4o-mini-transcribe",
            responseFormat: "json"
        )
    }

    private func makeContext(styleCategory: StyleCategory) -> ActiveAppContext {
        ActiveAppContext(
            appName: "Messages",
            bundleID: "com.apple.messages",
            processIdentifier: 456,
            styleCategory: styleCategory,
            windowTitle: nil,
            focusedElementRole: nil
        )
    }
}
