import Foundation
import AppKit
import ApplicationServices

final class TextInsertionService: TextInsertionServicing {
    func insertOrFallback(_ text: String) -> InsertOutcome {
        copyToClipboard(text)
        guard isFocusedElementEditable() else {
            return .clipboardReady
        }
        simulatePasteShortcut()
        return .inserted
    }

    func pasteLastCapture(_ text: String) {
        copyToClipboard(text)
        simulatePasteShortcut()
    }

    func focusedAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown App"
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func isFocusedElementEditable() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard status == .success, let element = value else { return false }

        let editableAttributeCandidates = [
            kAXSelectedTextRangeAttribute,
            kAXSelectedTextAttribute,
            kAXValueAttribute
        ]

        return editableAttributeCandidates.contains { attribute in
            AXUIElementCopyAttributeValue(element as! AXUIElement, attribute as CFString, nil) == .success
        }
    }

    private func simulatePasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        commandDown?.post(tap: .cghidEventTap)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        commandUp?.post(tap: .cghidEventTap)
    }
}
