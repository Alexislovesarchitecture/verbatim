import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#elseif canImport(UIKit)
import UIKit
#endif

final class ClipboardInsertionService: InsertionServiceProtocol {
#if canImport(AppKit)
    struct AppKitHooks {
        var writeToPasteboard: (String) -> Bool
        var hasAccessibilityPermission: () -> Bool
        var restoreTargetApplication: (InsertionTarget) -> TargetRestoreOutcome
        var performPaste: () -> Bool

        static let live = AppKitHooks(
            writeToPasteboard: { text in
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            },
            hasAccessibilityPermission: {
                AXIsProcessTrusted()
            },
            restoreTargetApplication: { target in
                restoreTargetApplicationLive(target)
            },
            performPaste: {
                performPasteLive()
            }
        )

        private static func restoreTargetApplicationLive(_ target: InsertionTarget) -> TargetRestoreOutcome {
            let runningApp: NSRunningApplication?
            if let pid = target.processIdentifier, pid > 0 {
                runningApp = NSRunningApplication(processIdentifier: pid)
            } else {
                runningApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == target.bundleID }
            }

            guard let runningApp else {
                return .missingTargetApplication
            }

            if runningApp.isActive {
                return .restored
            }

            let didActivate = runningApp.activate()
            Thread.sleep(forTimeInterval: 0.12)
            return didActivate && runningApp.isActive ? .restored : .activationFailed
        }

        private static func performPasteLive() -> Bool {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                return false
            }

            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            return true
        }
    }

    enum TargetRestoreOutcome {
        case restored
        case missingTargetApplication
        case activationFailed
    }

    private let hooks: AppKitHooks

    init(hooks: AppKitHooks = .live) {
        self.hooks = hooks
    }
#else
    init() {}
#endif

    func insert(text: String, autoPaste: Bool, target: InsertionTarget?, requiresFrozenTarget: Bool) -> InsertionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed(reason: .emptyText)
        }

#if canImport(AppKit)
        guard hooks.writeToPasteboard(trimmed) else {
            return .failed(reason: .clipboardWriteFailed)
        }

        guard autoPaste else {
            return .copiedOnly(reason: .autoPasteDisabled)
        }

        if requiresFrozenTarget, target == nil {
            return .copiedOnly(reason: .missingInsertionTarget)
        }

        guard hooks.hasAccessibilityPermission() else {
            return .copiedOnlyNeedsPermission
        }

        if let target {
            switch hooks.restoreTargetApplication(target) {
            case .restored:
                break
            case .missingTargetApplication:
                return .copiedOnly(reason: .invalidTargetApplication)
            case .activationFailed:
                return .copiedOnly(reason: .targetRestoreFailed)
            }
        }

        return hooks.performPaste() ? .pasted : .copiedOnly(reason: .pasteFailed)
#elseif canImport(UIKit)
        UIPasteboard.general.string = trimmed
        return autoPaste ? .pasted : .copiedOnly(reason: .autoPasteDisabled)
#endif
    }
}
