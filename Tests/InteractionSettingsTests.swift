import XCTest
@testable import VerbatimSwiftMVP

final class InteractionSettingsTests: XCTestCase {
    func testInteractionSettingsDefaults() {
        let settings = InteractionSettings()
        XCTAssertFalse(settings.hotkeyEnabled)
        XCTAssertEqual(settings.hotkeyTriggerMode, .holdToTalk)
        XCTAssertEqual(settings.hotkeyBinding.keyCode, HotkeyBinding.functionKeyCode)
        XCTAssertEqual(settings.hotkeyBinding.modifierFlagsRawValue, 0)
        XCTAssertEqual(settings.hotkeyBinding.modifierKeyRawValue, HotkeyBinding.functionModifierRawValue)
        XCTAssertEqual(settings.hotkeyBinding.displayTitle, "Fn")
        XCTAssertTrue(settings.showListeningIndicator)
        XCTAssertFalse(settings.playSoundCues)
        XCTAssertTrue(settings.autoPasteAfterInsert)
    }

    func testLegacyPresetDecodesToCustomBinding() throws {
        let legacyJSON = """
        {
          "hotkeyEnabled": true,
          "hotkeyTriggerMode": "tap_to_toggle",
          "hotkeyPreset": "control_space",
          "showListeningIndicator": true,
          "playSoundCues": false,
          "autoPasteAfterInsert": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InteractionSettings.self, from: legacyJSON)
        XCTAssertTrue(decoded.hotkeyEnabled)
        XCTAssertEqual(decoded.hotkeyTriggerMode, .tapToToggle)
        XCTAssertEqual(decoded.hotkeyBinding.keyCode, HotkeyBinding.spaceKeyCode)
        XCTAssertEqual(decoded.hotkeyBinding.modifierFlagsRawValue, HotkeyBinding.controlModifierRawValue)
        XCTAssertNil(decoded.hotkeyBinding.modifierKeyRawValue)
        XCTAssertEqual(decoded.hotkeyBinding.displayTitle, "Control + Space")
        XCTAssertFalse(decoded.autoPasteAfterInsert)
    }
}
