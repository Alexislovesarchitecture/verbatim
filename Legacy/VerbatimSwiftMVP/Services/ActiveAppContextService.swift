import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

protocol ActiveAppContextServiceProtocol {
    func currentContext() -> ActiveAppContext
}

final class ActiveAppContextService: ActiveAppContextServiceProtocol {
    func currentContext() -> ActiveAppContext {
#if canImport(AppKit)
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleID = app?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = app?.processIdentifier ?? 0

        let resolvedName = (appName?.isEmpty == false) ? appName! : "Unknown App"
        let resolvedBundle = (bundleID?.isEmpty == false) ? bundleID! : "unknown.bundle"
        return ActiveAppContext(
            appName: resolvedName,
            bundleID: resolvedBundle,
            processIdentifier: pid,
            styleCategory: styleCategory(bundleID: resolvedBundle, appName: resolvedName),
            windowTitle: focusedWindowTitle(pid: pid),
            focusedElementRole: focusedElementRole(pid: pid)
        )
#else
        return ActiveAppContext(
            appName: "Unknown App",
            bundleID: "unknown.bundle",
            processIdentifier: nil,
            styleCategory: .other,
            windowTitle: nil,
            focusedElementRole: nil
        )
#endif
    }

    private func styleCategory(bundleID: String, appName: String) -> StyleCategory {
        let combined = "\(bundleID.lowercased()) \(appName.lowercased())"

        if combined.contains("mail") || combined.contains("outlook") || combined.contains("spark") {
            return .email
        }

        if combined.contains("linear")
            || combined.contains("notes")
            || combined.contains("obsidian")
            || combined.contains("bear")
            || combined.contains("drafts") {
            return .other
        }

        if combined.contains("slack") || combined.contains("teams") || combined.contains("notion") || combined.contains("jira") {
            return .work
        }

        if combined.contains("messages") || combined.contains("whatsapp") || combined.contains("telegram") || combined.contains("discord") {
            return .personal
        }

        return .other
    }

#if canImport(AppKit)
    private func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted(), pid != 0 else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowElement = windowRef as! AXUIElement? else {
            return nil
        }

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    private func focusedElementRole(pid: pid_t) -> String? {
        guard AXIsProcessTrusted(), pid != 0 else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef as! AXUIElement? else {
            return nil
        }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }
#endif
}
