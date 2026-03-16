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
        let focusedSnapshot = focusedElementSnapshot(pid: pid)
        return ActiveAppContext(
            appName: resolvedName,
            bundleID: resolvedBundle,
            processIdentifier: pid,
            styleCategory: styleCategory(bundleID: resolvedBundle, appName: resolvedName),
            windowTitle: focusedWindowTitle(pid: pid),
            focusedElementRole: focusedSnapshot.role,
            focusedElementSubrole: focusedSnapshot.subrole,
            focusedElementTitle: focusedSnapshot.title,
            focusedElementPlaceholder: focusedSnapshot.placeholder,
            focusedElementDescription: focusedSnapshot.description,
            focusedValueSnippet: focusedSnapshot.valueSnippet
        )
#else
        return ActiveAppContext(
            appName: "Unknown App",
            bundleID: "unknown.bundle",
            processIdentifier: nil,
            styleCategory: .other,
            windowTitle: nil,
            focusedElementRole: nil,
            focusedElementSubrole: nil,
            focusedElementTitle: nil,
            focusedElementPlaceholder: nil,
            focusedElementDescription: nil,
            focusedValueSnippet: nil
        )
#endif
    }

    private func styleCategory(bundleID: String, appName: String) -> StyleCategory {
        let combined = "\(bundleID.lowercased()) \(appName.lowercased())"

        if combined.contains("mail") || combined.contains("outlook") || combined.contains("spark") || combined.contains("hey") {
            return .email
        }

        if combined.contains("slack") || combined.contains("teams") || combined.contains("notion") || combined.contains("jira") || combined.contains("linear") || combined.contains("chat") {
            return .workMessages
        }

        if combined.contains("messages") || combined.contains("whatsapp") || combined.contains("telegram") || combined.contains("discord") {
            return .personalMessages
        }

        return .other
    }

#if canImport(AppKit)
    private struct FocusedElementSnapshot {
        var role: String?
        var subrole: String?
        var title: String?
        var placeholder: String?
        var description: String?
        var valueSnippet: String?
    }

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

    private func focusedElementSnapshot(pid: pid_t) -> FocusedElementSnapshot {
        guard AXIsProcessTrusted(), pid != 0 else { return FocusedElementSnapshot() }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef as! AXUIElement? else {
            return FocusedElementSnapshot()
        }
        let role = attributeString(kAXRoleAttribute as CFString, element: focusedElement)
        let subrole = attributeString(kAXSubroleAttribute as CFString, element: focusedElement)
        let title = attributeString(kAXTitleAttribute as CFString, element: focusedElement)
        let placeholder = attributeString("AXPlaceholderValue" as CFString, element: focusedElement)
        let description = attributeString(kAXDescriptionAttribute as CFString, element: focusedElement)
        let valueSnippet: String?
        if isEditableTextInput(role: role, subrole: subrole), isSecureTextInput(role: role, subrole: subrole) == false {
            valueSnippet = attributeString(kAXValueAttribute as CFString, element: focusedElement)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
                .description
        } else {
            valueSnippet = nil
        }
        return FocusedElementSnapshot(
            role: role,
            subrole: subrole,
            title: title,
            placeholder: placeholder,
            description: description,
            valueSnippet: valueSnippet
        )
    }

    private func attributeString(_ attribute: CFString, element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }

    private func isEditableTextInput(role: String?, subrole: String?) -> Bool {
        let combined = [role, subrole]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        return ["axtextarea", "axtextfield", "axsearchfield", "axcombobox", "axtextinput", "axwebarea"]
            .contains { combined.contains($0) }
    }

    private func isSecureTextInput(role: String?, subrole: String?) -> Bool {
        let combined = [role, subrole]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        return combined.contains("secure")
    }
#endif
}

protocol StyleFormattingServiceProtocol {
    func format(text: String, context: ActiveAppContext?, settings: StyleSettings) -> String
}

struct DeterministicStyleFormatter: StyleFormattingServiceProtocol {
    func format(text: String, context: ActiveAppContext?, settings: StyleSettings) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return text }
        guard let context else { return trimmed }

        let configuration = settings.configuration(for: context.styleCategory)
        guard configuration.enabled else { return trimmed }

        switch configuration.preset {
        case .formal:
            return formalize(trimmed)
        case .casual:
            return casualize(trimmed, preserveTerminalPunctuation: context.styleCategory == .email)
        case .enthusiastic:
            return energize(trimmed)
        case .veryCasual:
            return makeVeryCasual(trimmed)
        }
    }

    private func formalize(_ text: String) -> String {
        let capitalized = capitalizeLeadingCharacter(in: text)
        if let last = capitalized.last, [".", "!", "?"].contains(last) {
            return capitalized
        }
        return capitalized + "."
    }

    private func casualize(_ text: String, preserveTerminalPunctuation: Bool) -> String {
        var result = capitalizeLeadingCharacter(in: text)
        if preserveTerminalPunctuation {
            return result
        }
        if result.last == "." {
            result.removeLast()
        }
        return result
    }

    private func energize(_ text: String) -> String {
        let capitalized = capitalizeLeadingCharacter(in: text)
        guard let last = capitalized.last else { return capitalized }
        if last == "!" {
            return capitalized
        }
        if last == "." || last == "?" {
            return String(capitalized.dropLast()) + "!"
        }
        return capitalized + "!"
    }

    private func makeVeryCasual(_ text: String) -> String {
        var result = text
        if let last = result.last, [".", "!"].contains(last) {
            result.removeLast()
        }
        guard let first = result.first else { return result }
        let firstString = String(first)
        if firstString.uppercased() == firstString && firstString.lowercased() != firstString {
            result.replaceSubrange(result.startIndex ... result.startIndex, with: firstString.lowercased())
        }
        return result
    }

    private func capitalizeLeadingCharacter(in text: String) -> String {
        guard let firstLetterRange = text.rangeOfCharacter(from: .letters) else { return text }
        var output = text
        let firstCharacter = output[firstLetterRange.lowerBound]
        output.replaceSubrange(firstLetterRange.lowerBound ... firstLetterRange.lowerBound, with: String(firstCharacter).uppercased())
        return output
    }
}
