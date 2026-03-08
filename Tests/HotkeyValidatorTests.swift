import XCTest
@testable import VerbatimSwiftMVP

final class HotkeyValidatorTests: XCTestCase {
    func testReservedCommandSpaceIsBlocking() {
        let result = HotkeyBinding(
            keyCode: HotkeyBinding.spaceKeyCode,
            modifierFlagsRawValue: HotkeyBinding.commandModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        ).validationResult

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.blockingIssues.contains {
            if case .reservedBySystem = $0 { return true }
            return false
        })
    }

    func testOptionSpaceProducesWarningOnly() {
        let result = HotkeyBinding.optionSpace.validationResult

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testFnAloneIsAllowed() {
        XCTAssertTrue(HotkeyBinding.defaultFunctionKey.validationResult.isValid)
    }
}
