import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#elseif canImport(UIKit)
import UIKit
#endif

enum InsertionError: LocalizedError {
    case emptyText
    case accessibilityPermissionRequired

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Cannot insert empty text."
        case .accessibilityPermissionRequired:
            return "Enable Accessibility access for Verbatim to auto-paste into the active app."
        }
    }
}

final class ClipboardInsertionService: InsertionServiceProtocol {
    func insert(text: String, autoPaste: Bool) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw InsertionError.emptyText
        }

#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        if autoPaste {
            try pasteToFrontmostApplication()
        }
#elseif canImport(UIKit)
        UIPasteboard.general.string = trimmed
#endif
    }

#if canImport(AppKit)
    private func pasteToFrontmostApplication() throws {
        guard AXIsProcessTrusted() else {
            throw InsertionError.accessibilityPermissionRequired
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
#endif
}
