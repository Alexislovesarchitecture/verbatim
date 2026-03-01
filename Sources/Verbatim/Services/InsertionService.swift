import AppKit
import ApplicationServices
import Foundation

final class InsertionService {
    private(set) var lastCapture: String = ""

    func promptForAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func insert(text: String, autoInsert: Bool, autoPasteFallback: Bool, keepClipboardBackup: Bool) -> InsertResult {
        lastCapture = text

        guard autoInsert else {
            copyToClipboard(text)
            return .clipboardOnly
        }

        let focusedState = focusedElementState()
        if case .editable(let element) = focusedState,
           tryInsert(text: text, into: element) {
            if keepClipboardBackup {
                copyToClipboard(text)
            }
            return .inserted
        }

        copyToClipboard(text)

        if autoPasteFallback, case .editable = focusedState {
            sendPasteShortcut()
            return .pastedViaClipboard
        }

        return .clipboardOnly
    }

    func copyLastCaptureToClipboard() {
        guard !lastCapture.isEmpty else { return }
        copyToClipboard(lastCapture)
    }

    func frontmostAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    func appCategory() -> AppStyleCategory {
        let name = frontmostAppName().lowercased()
        if name.contains("mail") || name.contains("outlook") || name.contains("spark") {
            return .email
        }
        if name.contains("messages") || name.contains("telegram") || name.contains("whatsapp") || name.contains("signal") {
            return .personal
        }
        if name.contains("slack") || name.contains("teams") || name.contains("discord") {
            return .work
        }
        return .other
    }

    private enum FocusedState {
        case editable(AXUIElement)
        case unavailable
    }

    private func focusedElementState() -> FocusedState {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unavailable }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedObject: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard result == .success, let focusedObject else { return .unavailable }
        let element = unsafeBitCast(focusedObject, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue ? .editable(element) : .unavailable
    }

    private func tryInsert(text: String, into element: AXUIElement) -> Bool {
        var currentValueRef: CFTypeRef?
        let currentValueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValueRef)
        let currentValue = (currentValueResult == .success ? currentValueRef as? String : nil) ?? ""

        if let range = selectedRange(from: element),
           let swiftRange = Range(range, in: currentValue) {
            var updated = currentValue
            updated.replaceSubrange(swiftRange, with: text)
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef) == .success
        }

        if currentValue.isEmpty {
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
        }

        let separator = currentValue.hasSuffix(" ") || currentValue.hasSuffix("\n") ? "" : " "
        let updated = currentValue + separator + text
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef) == .success
    }

    private func selectedRange(from element: AXUIElement) -> NSRange? {
        var rangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard result == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }

        let value = unsafeBitCast(rangeRef, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }

        var cfRange = CFRange()
        guard AXValueGetValue(value, .cfRange, &cfRange) else { return nil }
        return NSRange(location: cfRange.location, length: cfRange.length)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
