import XCTest
@testable import VerbatimSwiftMVP

final class ContextPackBuilderTests: XCTestCase {
    func testContextPackIncludesOnlyRelevantGlossaryAndSessionLimit() {
        let sut = ContextPackBuilder()
        var logicSettings = LogicSettings()
        logicSettings.removeFillerWords = true
        logicSettings.autoDetectLists = true

        var refine = RefineSettings()
        refine.sessionMemory = ["Project Delta", "Attendee: Alexis", "Focus: Permits", "Extra line"]
        refine.glossary = [
            GlossaryEntry(from: "adu", to: "ADU"),
            GlossaryEntry(from: "nonmatch", to: "X")
        ]

        let context = sut.build(
            activeContext: ActiveAppContext(
                appName: "Mail",
                bundleID: "com.apple.mail",
                styleCategory: .email,
                windowTitle: "Inbox",
                focusedElementRole: "AXTextArea"
            ),
            logicSettings: logicSettings,
            refineSettings: refine,
            deterministicText: "adu permit response"
        )

        XCTAssertEqual(context.styleCategory, .email)
        XCTAssertEqual(context.glossary.count, 1)
        XCTAssertEqual(context.glossary.first?.to, "ADU")
        XCTAssertEqual(context.sessionMemory.count, 3)
        XCTAssertEqual(context.outputFormat, .auto)
        XCTAssertEqual(context.selfCorrectionMode, .keepFinal)
        XCTAssertTrue(context.flagLowConfidenceWords)
        XCTAssertEqual(context.reasoningEffort, .modelDefault)
    }
}
