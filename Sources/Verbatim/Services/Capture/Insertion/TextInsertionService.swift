import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol TextInsertionServicing {
    func requestAccessibilityIfNeeded()
    func copyToClipboard(_ text: String)
    func hasEditableTarget() -> Bool
    func insert(_ text: String) -> Bool
    func frontmostApplicationName() -> String
    func frontmostBundleIdentifier() -> String?
    func inferStyleCategory() -> StyleCategory
}

@MainActor
final class TextInsertionService: TextInsertionServicing {
    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func hasEditableTarget() -> Bool {
        focusedEditableElement() != nil
    }

    func insert(_ text: String) -> Bool {
        guard let element = focusedEditableElement() else { return false }
        var currentValueRef: CFTypeRef?
        let currentResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValueRef)
        let currentValue = (currentResult == .success ? currentValueRef as? String : nil) ?? ""

        if let selectedRange = selectedRange(from: element),
           let nsRange = Range(selectedRange, in: currentValue) {
            var edited = currentValue
            edited.replaceSubrange(nsRange, with: text)
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, edited as CFTypeRef) == .success
        }

        if currentValue.isEmpty {
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
        }

        let separator = currentValue.hasSuffix(" ") || currentValue.hasSuffix("\n") ? "" : " "
        let updated = currentValue + separator + text
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef) == .success
    }

    func frontmostApplicationName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    func frontmostBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func inferStyleCategory() -> StyleCategory {
        let name = frontmostApplicationName().lowercased()
        if name.contains("mail") || name.contains("outlook") || name.contains("notes") || name.contains("finder") {
            return .email
        }
        if name.contains("slack") || name.contains("teams") || name.contains("discord") {
            return .work
        }
        if name.contains("messages") || name.contains("telegram") || name.contains("whatsapp") {
            return .personal
        }
        return .other
    }

    private func focusedEditableElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard result == .success, let focusedValue else { return nil }
        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return settable.boolValue ? element : nil
    }

    private func selectedRange(from element: AXUIElement) -> NSRange? {
        var rangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard result == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }

        let value = unsafeBitCast(rangeRef, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }

        var axRange = CFRange()
        guard AXValueGetValue(value, .cfRange, &axRange) else { return nil }
        return NSRange(location: axRange.location, length: axRange.length)
    }
}
