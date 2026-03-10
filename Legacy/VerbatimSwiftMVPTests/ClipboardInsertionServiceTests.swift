import XCTest
@testable import VerbatimSwiftMVP

#if canImport(AppKit)
final class ClipboardInsertionServiceTests: XCTestCase {
    func testAccessibilityMissingReturnsCopiedOnlyWhenClipboardWriteSucceeds() {
        let sut = ClipboardInsertionService(
            hooks: .init(
                writeToPasteboard: { _ in true },
                hasAccessibilityPermission: { false },
                restoreTargetApplication: { _ in .restored },
                performPaste: { true }
            )
        )

        let result = sut.insert(
            text: "Hello",
            autoPaste: true,
            target: InsertionTarget(appName: "Messages", bundleID: "com.apple.MobileSMS", processIdentifier: 9),
            requiresFrozenTarget: false
        )

        XCTAssertEqual(result, .copiedOnlyNeedsPermission)
    }

    func testTargetRestoreFailureReturnsCopiedOnly() {
        let sut = ClipboardInsertionService(
            hooks: .init(
                writeToPasteboard: { _ in true },
                hasAccessibilityPermission: { true },
                restoreTargetApplication: { _ in .activationFailed },
                performPaste: { true }
            )
        )

        let result = sut.insert(
            text: "Hello",
            autoPaste: true,
            target: InsertionTarget(appName: "Messages", bundleID: "com.apple.MobileSMS", processIdentifier: 9),
            requiresFrozenTarget: true
        )

        XCTAssertEqual(result, .copiedOnly(reason: .targetRestoreFailed))
    }

    func testPasteFailureReturnsCopiedOnly() {
        let sut = ClipboardInsertionService(
            hooks: .init(
                writeToPasteboard: { _ in true },
                hasAccessibilityPermission: { true },
                restoreTargetApplication: { _ in .restored },
                performPaste: { false }
            )
        )

        let result = sut.insert(
            text: "Hello",
            autoPaste: true,
            target: InsertionTarget(appName: "Messages", bundleID: "com.apple.MobileSMS", processIdentifier: 9),
            requiresFrozenTarget: true
        )

        XCTAssertEqual(result, .copiedOnly(reason: .pasteFailed))
    }
}
#endif
