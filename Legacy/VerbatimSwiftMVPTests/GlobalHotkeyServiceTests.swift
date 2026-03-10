import XCTest
@testable import VerbatimSwiftMVP

final class GlobalHotkeyServiceTests: XCTestCase {
    func testFunctionBindingFallsBackAutomaticallyWhenSpecialBackendUnavailable() {
        let sut = GlobalHotkeyService(
            eventMonitorStarter: { _, _ in true },
            functionKeyBackendStarter: { _, _ in false }
        )

        let result = sut.startMonitoring(
            binding: .defaultFunctionKey,
            fallbackMode: .automatic,
            handler: { _ in }
        )

        XCTAssertEqual(result.backend, .fallback)
        XCTAssertTrue(result.fallbackWasUsed)
        XCTAssertEqual(result.effectiveBinding, .controlOptionSpace)
        XCTAssertTrue(result.isActive)
    }

    func testFunctionBindingAskModeKeepsSelectedBindingActive() {
        let sut = GlobalHotkeyService(
            eventMonitorStarter: { _, _ in true },
            functionKeyBackendStarter: { _, _ in false }
        )

        let result = sut.startMonitoring(
            binding: .defaultFunctionKey,
            fallbackMode: .ask,
            handler: { _ in }
        )

        XCTAssertEqual(result.backend, .eventMonitor)
        XCTAssertFalse(result.fallbackWasUsed)
        XCTAssertEqual(result.effectiveBinding, .defaultFunctionKey)
        XCTAssertTrue(result.isActive)
    }

    func testStandardShortcutUsesEventMonitorBackend() {
        let sut = GlobalHotkeyService(
            eventMonitorStarter: { _, _ in true },
            functionKeyBackendStarter: { _, _ in false }
        )

        let result = sut.startMonitoring(
            binding: .controlOptionSpace,
            fallbackMode: .automatic,
            handler: { _ in }
        )

        XCTAssertEqual(result.backend, .eventMonitor)
        XCTAssertFalse(result.fallbackWasUsed)
        XCTAssertEqual(result.effectiveBinding, .controlOptionSpace)
    }
}
