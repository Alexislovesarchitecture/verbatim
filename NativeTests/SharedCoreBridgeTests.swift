import XCTest
@testable import Verbatim

final class SharedCoreBridgeTests: XCTestCase {
    func testTriggerModeDecodesLegacyStorageValuesAndEncodesSemanticValues() throws {
        let decoder = JSONDecoder()
        let legacyHold = try decoder.decode(TriggerMode.self, from: Data(#""hold_to_talk""#.utf8))
        let legacyToggle = try decoder.decode(TriggerMode.self, from: Data(#""tap_to_toggle""#.utf8))

        XCTAssertEqual(legacyHold, .hold)
        XCTAssertEqual(legacyToggle, .toggle)
        XCTAssertEqual(String(data: try JSONEncoder().encode(TriggerMode.hold), encoding: .utf8), #""hold""#)
        XCTAssertEqual(String(data: try JSONEncoder().encode(TriggerMode.toggle), encoding: .utf8), #""toggle""#)
    }

    func testFocusedFieldEmailCueResolvesEmailDecision() {
        let bridge = SharedCoreBridge(forceFallback: true)
        let context = ActiveAppContext(
            appName: "Atlas",
            bundleID: "com.openai.atlas",
            processIdentifier: 7,
            styleCategory: .other,
            windowTitle: "Compose - Outlook",
            focusedElementRole: "AXTextField",
            focusedElementSubrole: nil,
            focusedElementTitle: "Subject",
            focusedElementPlaceholder: nil,
            focusedElementDescription: nil,
            focusedValueSnippet: nil
        )

        let decision = bridge.resolveStyleDecision(context: context, settings: .init())

        XCTAssertEqual(decision.category, .email)
        XCTAssertEqual(decision.source, .focusedField)
    }

    func testDoubleTapLockStartsOnSecondTap() {
        let bridge = SharedCoreBridge(forceFallback: true)
        bridge.prepareTrigger(mode: .doubleTapLock)

        let first = bridge.handleInputEvent(.triggerDown, isRecording: false, timestamp: Date(timeIntervalSince1970: 10))
        let second = bridge.handleInputEvent(.triggerDown, isRecording: false, timestamp: Date(timeIntervalSince1970: 10.2))

        XCTAssertEqual(first, .none)
        XCTAssertEqual(second, .startRecording)
    }

    func testConservativeFormattingPreservesWording() {
        let bridge = SharedCoreBridge(forceFallback: true)
        var settings = StyleSettings()
        settings.setEnabled(true, for: .workMessages)
        settings.setPreset(.formal, for: .workMessages)
        let context = ActiveAppContext(
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            processIdentifier: 7,
            styleCategory: .workMessages,
            windowTitle: "Team thread",
            focusedElementRole: "AXTextField",
            focusedElementSubrole: nil,
            focusedElementTitle: "Reply",
            focusedElementPlaceholder: nil,
            focusedElementDescription: nil,
            focusedValueSnippet: nil
        )
        let decision = bridge.resolveStyleDecision(context: context, settings: settings)

        let processed = bridge.processTranscript(
            text: "um hello there",
            context: context,
            settings: settings,
            resolvedDecision: decision
        )

        XCTAssertEqual(processed.cleanedText, "hello there")
        XCTAssertEqual(processed.finalText, "Hello there.")
    }
}
