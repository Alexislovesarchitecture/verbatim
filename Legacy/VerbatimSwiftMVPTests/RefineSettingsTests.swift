import XCTest
@testable import VerbatimSwiftMVP

final class RefineSettingsTests: XCTestCase {
    func testLegacyRefineSettingsDecodeFallsBackToDefaultPresets() throws {
        let json = """
        {
          "workEnabled": true,
          "emailEnabled": false,
          "personalEnabled": true,
          "otherEnabled": false,
          "previewBeforeInsert": true,
          "autoPasteAfterInsert": false,
          "sessionMemory": ["Project Delta"],
          "glossary": []
        }
        """

        let decoded = try JSONDecoder().decode(RefineSettings.self, from: Data(json.utf8))

        XCTAssertTrue(decoded.workEnabled)
        XCTAssertTrue(decoded.personalEnabled)
        XCTAssertEqual(decoded.preset(for: .work), .formal)
        XCTAssertEqual(decoded.preset(for: .email), .formal)
        XCTAssertEqual(decoded.preset(for: .personal), .casual)
        XCTAssertEqual(decoded.preset(for: .other), .casual)
        XCTAssertEqual(decoded.emailSignatureName, "")
    }
}
