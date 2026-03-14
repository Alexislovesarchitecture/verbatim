import Foundation
import Carbon

enum AppTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case home
    case style
    case dictionary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .style: return "Style"
        case .dictionary: return "Dictionary"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .style: return "textformat.alt"
        case .dictionary: return "book.closed"
        }
    }
}

enum StyleCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case personalMessages = "personal_messages"
    case workMessages = "work_messages"
    case email
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalMessages:
            return "Personal messages"
        case .workMessages:
            return "Work messages"
        case .email:
            return "Email"
        case .other:
            return "Other"
        }
    }

    var shortTitle: String {
        switch self {
        case .personalMessages:
            return "Personal"
        case .workMessages:
            return "Work"
        case .email:
            return "Email"
        case .other:
            return "Other"
        }
    }

    var heroTitle: String {
        switch self {
        case .personalMessages:
            return "Saved defaults for personal chats"
        case .workMessages:
            return "Saved defaults for workplace messaging"
        case .email:
            return "Saved defaults for email writing"
        case .other:
            return "Saved defaults for everything else"
        }
    }

    var heroSubtitle: String {
        switch self {
        case .personalMessages:
            return "Use looser punctuation and lighter formatting for friendly conversation."
        case .workMessages:
            return "Keep quick work replies clear without over-formatting them."
        case .email:
            return "Bias toward stricter capitalization and sentence punctuation."
        case .other:
            return "Fallback defaults for notes, forms, browsers, and everything unclassified."
        }
    }

    var sampleApps: [String] {
        switch self {
        case .personalMessages:
            return ["Messages", "WhatsApp", "Telegram", "Discord"]
        case .workMessages:
            return ["Slack", "Teams", "Discord", "Google Chat"]
        case .email:
            return ["Mail", "Outlook", "Gmail", "HEY"]
        case .other:
            return ["Notes", "Todoist", "Safari", "Atlas"]
        }
    }

    var supportedPresets: [StylePreset] {
        switch self {
        case .personalMessages:
            return [.formal, .casual, .veryCasual]
        case .workMessages, .email, .other:
            return [.formal, .casual, .enthusiastic]
        }
    }
}

enum StylePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case formal
    case casual
    case enthusiastic
    case veryCasual = "very_casual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formal:
            return "Formal"
        case .casual:
            return "Casual"
        case .enthusiastic:
            return "Enthusiastic"
        case .veryCasual:
            return "Very Casual"
        }
    }

    var summary: String {
        switch self {
        case .formal:
            return "Caps + punctuation"
        case .casual:
            return "Caps + lighter punctuation"
        case .enthusiastic:
            return "Clean punctuation + extra energy"
        case .veryCasual:
            return "Minimal punctuation"
        }
    }

    func preview(for category: StyleCategory) -> String {
        switch (category, self) {
        case (.email, .formal):
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat.\n\nBest,\nMary"
        case (.email, .casual):
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat.\n\nBest,\nMary"
        case (.email, .enthusiastic):
            return "Hi Alex,\n\nIt was great talking with you today. Looking forward to our next chat!\n\nBest,\nMary"
        case (.workMessages, .formal):
            return "Hey, if you're free, let's chat about the results."
        case (.workMessages, .casual):
            return "Hey, if you're free let's chat about the results"
        case (.workMessages, .enthusiastic):
            return "Hey, if you're free, let's chat about the results!"
        case (.personalMessages, .formal):
            return "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you."
        case (.personalMessages, .casual):
            return "Hey are you free for lunch tomorrow? Let's do 12 if that works for you"
        case (.personalMessages, .veryCasual):
            return "hey are you free for lunch tomorrow? let's do 12 if that works for you"
        case (.other, .formal):
            return "So far, I am enjoying the new workout routine."
        case (.other, .casual):
            return "So far I am enjoying the new workout routine."
        case (.other, .enthusiastic):
            return "So far, I am enjoying the new workout routine!"
        default:
            return "Saved formatting defaults for this category."
        }
    }
}

struct StyleCategorySettings: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var preset: StylePreset

    init(enabled: Bool = false, preset: StylePreset) {
        self.enabled = enabled
        self.preset = preset
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case preset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        preset = try container.decodeIfPresent(StylePreset.self, forKey: .preset) ?? .casual
    }
}

struct StyleSettings: Codable, Equatable, Sendable {
    var personalMessages = StyleCategorySettings(preset: .casual)
    var workMessages = StyleCategorySettings(preset: .formal)
    var email = StyleCategorySettings(preset: .formal)
    var other = StyleCategorySettings(preset: .casual)

    init() {}

    enum CodingKeys: String, CodingKey {
        case personalMessages
        case workMessages
        case email
        case other
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        personalMessages = try container.decodeIfPresent(StyleCategorySettings.self, forKey: .personalMessages) ?? StyleCategorySettings(preset: .casual)
        workMessages = try container.decodeIfPresent(StyleCategorySettings.self, forKey: .workMessages) ?? StyleCategorySettings(preset: .formal)
        email = try container.decodeIfPresent(StyleCategorySettings.self, forKey: .email) ?? StyleCategorySettings(preset: .formal)
        other = try container.decodeIfPresent(StyleCategorySettings.self, forKey: .other) ?? StyleCategorySettings(preset: .casual)
    }

    func configuration(for category: StyleCategory) -> StyleCategorySettings {
        switch category {
        case .personalMessages:
            return personalMessages
        case .workMessages:
            return workMessages
        case .email:
            return email
        case .other:
            return other
        }
    }

    mutating func setPreset(_ preset: StylePreset, for category: StyleCategory) {
        let resolvedPreset = category.supportedPresets.contains(preset) ? preset : (category.supportedPresets.first ?? preset)
        switch category {
        case .personalMessages:
            personalMessages.preset = resolvedPreset
        case .workMessages:
            workMessages.preset = resolvedPreset
        case .email:
            email.preset = resolvedPreset
        case .other:
            other.preset = resolvedPreset
        }
    }

    mutating func setEnabled(_ enabled: Bool, for category: StyleCategory) {
        switch category {
        case .personalMessages:
            personalMessages.enabled = enabled
        case .workMessages:
            workMessages.enabled = enabled
        case .email:
            email.enabled = enabled
        case .other:
            other.enabled = enabled
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case preferences
    case transcription
    case hotkeys
    case privacyPermissions = "privacy_permissions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .transcription: return "Transcription"
        case .hotkeys: return "Hotkeys"
        case .privacyPermissions: return "Privacy & Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .preferences: return "slider.horizontal.3"
        case .transcription: return "waveform.and.mic"
        case .hotkeys: return "keyboard"
        case .privacyPermissions: return "lock.shield"
        }
    }

    var railGroupTitle: String {
        switch self {
        case .preferences, .hotkeys:
            return "APP"
        case .transcription:
            return "SPEECH & AI"
        case .privacyPermissions:
            return "PRIVACY"
        }
    }
}

enum ProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisper
    case parakeet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }
}

struct LanguageSelection: Hashable, Codable, Identifiable, Sendable {
    let identifier: String

    var id: String { identifier }

    static let auto = LanguageSelection(identifier: "auto")

    var isAuto: Bool {
        identifier == Self.auto.identifier
    }

    var title: String {
        if isAuto { return "Auto-detect" }
        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultShortcut = KeyboardShortcut(
        keyCode: 49,
        modifiers: UInt32(cmdKey | optionKey)
    )

    var isEmpty: Bool {
        modifiers == 0 && keyCode == 0
    }
}

struct ActiveAppContext: Equatable, Codable, Sendable {
    let appName: String
    let bundleID: String
    let processIdentifier: Int32?
    let styleCategory: StyleCategory
    let windowTitle: String?
    let focusedElementRole: String?
    let focusedElementSubrole: String?
    let focusedElementTitle: String?
    let focusedElementPlaceholder: String?
    let focusedElementDescription: String?
    let focusedValueSnippet: String?

    var summary: String {
        if let windowTitle, windowTitle.isEmpty == false {
            return "\(appName) • \(windowTitle)"
        }
        return appName
    }

    var isEditableTextInput: Bool {
        editableRoleClass != nil
    }

    var isSecureTextInput: Bool {
        let combined = [focusedElementRole, focusedElementSubrole, focusedElementDescription]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        return combined.contains("secure") || combined.contains("password")
    }

    var editableRoleClass: String? {
        let combined = [focusedElementRole, focusedElementSubrole]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        if combined.contains("axtextarea") { return "text_area" }
        if combined.contains("axsearchfield") { return "search_field" }
        if combined.contains("axtextfield") || combined.contains("axtextinput") { return "text_field" }
        if combined.contains("axcombobox") { return "combo_box" }
        if combined.contains("axwebarea") { return "web_area" }
        return nil
    }
}

enum StyleDecisionSource: String, Codable, Sendable {
    case focusedField = "focused_field"
    case windowTitle = "window_title"
    case bundleID = "bundle_id"
    case fallback

    var title: String {
        switch self {
        case .focusedField:
            return "Focused field"
        case .windowTitle:
            return "Window title"
        case .bundleID:
            return "App identity"
        case .fallback:
            return "Fallback"
        }
    }
}

struct StyleDecisionReport: Equatable, Codable, Sendable {
    var timestamp: Date
    var category: StyleCategory
    var preset: StylePreset
    var source: StyleDecisionSource
    var confidence: Double
    var formattingEnabled: Bool
    var reason: String?
    var outputPreview: String?
}

enum TriggerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case hold = "hold"
    case toggle = "toggle"
    case doubleTapLock = "double_tap_lock"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "hold_to_talk", "hold":
            self = .hold
        case "tap_to_toggle", "toggle":
            self = .toggle
        case "double_tap_lock":
            self = .doubleTapLock
        default:
            self = .hold
        }
    }

    var title: String {
        switch self {
        case .hold:
            return "Hold to Talk"
        case .toggle:
            return "Tap to Toggle"
        case .doubleTapLock:
            return "Double Tap to Lock"
        }
    }
}

typealias HotkeyTriggerMode = TriggerMode

enum TriggerID: String, Codable, Identifiable, Sendable {
    case dictation

    var id: String { rawValue }
}

enum InputEvent: String, Codable, Sendable {
    case triggerDown = "trigger_down"
    case triggerUp = "trigger_up"
    case triggerToggle = "trigger_toggle"
}

enum DictationAction: String, Codable, Sendable {
    case none
    case startRecording = "start_recording"
    case stopRecording = "stop_recording"
    case cancelRecording = "cancel_recording"
}

struct TriggerStateSummary: Equatable, Codable, Sendable {
    var statusMessage: String
    var effectiveTriggerLabel: String
    var backendLabel: String
    var fallbackReason: String?
    var isAvailable: Bool
}

enum FunctionKeyFallbackMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case ask
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .ask:
            return "Ask"
        case .disabled:
            return "Disabled"
        }
    }
}

struct HotkeyValidationResult: Equatable, Codable, Sendable {
    var isValid: Bool
    var blockingMessage: String?
    var warningMessage: String?
}

struct HotkeyBinding: Codable, Hashable, Sendable {
    static let commandModifierRawValue: UInt = 1 << 20
    static let optionModifierRawValue: UInt = 1 << 19
    static let controlModifierRawValue: UInt = 1 << 18
    static let shiftModifierRawValue: UInt = 1 << 17
    static let superModifierRawValue: UInt = 1 << 24
    static let functionModifierRawValue: UInt = 1 << 23
    static let relevantModifierMask: UInt = commandModifierRawValue
        | optionModifierRawValue
        | controlModifierRawValue
        | shiftModifierRawValue
        | superModifierRawValue
        | functionModifierRawValue
    static let functionKeyCode: UInt16 = 63
    static let spaceKeyCode: UInt16 = 49

    var keyCode: UInt16
    var modifierFlagsRawValue: UInt
    var keyDisplay: String
    var modifierKeyRawValue: UInt?

    var displayTitle: String {
        let parts = Self.modifierNames(from: modifierFlagsRawValue) + [keyDisplay]
        return parts.joined(separator: modifierKeyRawValue == nil ? " + " : "")
    }

    var usesFn: Bool {
        modifierKeyRawValue == Self.functionModifierRawValue
            || (modifierFlagsRawValue & Self.functionModifierRawValue != 0)
    }

    var isModifierOnly: Bool {
        modifierKeyRawValue != nil
    }

    var isFunctionOnlyBinding: Bool {
        keyCode == Self.functionKeyCode
            && modifierKeyRawValue == Self.functionModifierRawValue
            && modifierFlagsRawValue == 0
    }

    var validationResult: HotkeyValidationResult {
        if isModifierOnly && modifierKeyRawValue != Self.functionModifierRawValue {
            return HotkeyValidationResult(isValid: false, blockingMessage: "Only Fn / Globe can be used alone.", warningMessage: nil)
        }
        if isModifierOnly {
            return HotkeyValidationResult(isValid: true, blockingMessage: nil, warningMessage: "Fn / Globe support depends on Accessibility access and your keyboard.")
        }
        if modifierFlagsRawValue == 0 {
            return HotkeyValidationResult(isValid: false, blockingMessage: "Choose a shortcut with at least one modifier.", warningMessage: nil)
        }
        return HotkeyValidationResult(isValid: true, blockingMessage: nil, warningMessage: nil)
    }

    static var defaultFunctionKey: HotkeyBinding {
        HotkeyBinding(
            keyCode: functionKeyCode,
            modifierFlagsRawValue: 0,
            keyDisplay: "Fn",
            modifierKeyRawValue: functionModifierRawValue
        )
    }

    static var optionSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: optionModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var controlSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: controlModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var controlOptionSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: controlModifierRawValue | optionModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var commandShiftSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: commandModifierRawValue | shiftModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var controlShiftSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: controlModifierRawValue | shiftModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var controlSuperSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: controlModifierRawValue | superModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    static var recommendedFallbacks: [HotkeyBinding] {
        [.optionSpace, .controlSpace, .controlOptionSpace, .commandShiftSpace]
    }

    static var windowsDefault: HotkeyBinding { .controlShiftSpace }

    static var linuxDefault: HotkeyBinding { .controlSuperSpace }

    static func fromLegacyShortcut(_ shortcut: KeyboardShortcut) -> HotkeyBinding {
        var modifierFlagsRawValue: UInt = 0
        if shortcut.modifiers & UInt32(cmdKey) != 0 { modifierFlagsRawValue |= commandModifierRawValue }
        if shortcut.modifiers & UInt32(optionKey) != 0 { modifierFlagsRawValue |= optionModifierRawValue }
        if shortcut.modifiers & UInt32(controlKey) != 0 { modifierFlagsRawValue |= controlModifierRawValue }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { modifierFlagsRawValue |= shiftModifierRawValue }

        return HotkeyBinding(
            keyCode: UInt16(shortcut.keyCode),
            modifierFlagsRawValue: modifierFlagsRawValue,
            keyDisplay: keyDisplay(for: UInt16(shortcut.keyCode)),
            modifierKeyRawValue: nil
        )
    }

    static func keyDisplay(for keyCode: UInt16) -> String {
        let table: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Escape",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z", 63: "Fn"
        ]
        return table[keyCode] ?? "Key \(keyCode)"
    }

    private static func modifierNames(from flags: UInt) -> [String] {
        var parts: [String] = []
        if flags & controlModifierRawValue != 0 { parts.append("Control") }
        if flags & optionModifierRawValue != 0 { parts.append("Option") }
        if flags & shiftModifierRawValue != 0 { parts.append("Shift") }
        if flags & superModifierRawValue != 0 { parts.append("Super") }
        if flags & commandModifierRawValue != 0 { parts.append("Command") }
        return parts
    }
}

struct PlatformTriggerBindings: Codable, Equatable, Sendable {
    var macos: HotkeyBinding = .defaultFunctionKey
    var windows: HotkeyBinding = .windowsDefault
    var linux: HotkeyBinding = .linuxDefault
}

struct DictationTriggerSettings: Codable, Equatable, Sendable {
    var mode: TriggerMode = .hold
    var bindings: PlatformTriggerBindings = .init()
}

enum OverlayStatus: Equatable, Sendable {
    case idle
    case recording
    case processing
    case success(String)
    case error(String)
}

enum RuntimeState: String, Equatable, Sendable {
    case stopped
    case starting
    case ready
    case failed
}

struct ProviderAvailability: Equatable, Sendable {
    var isAvailable: Bool
    var reason: String?
}

enum ProviderReadinessKind: String, Equatable, Sendable {
    case ready
    case missingLanguage
    case missingModel
    case missingAsset
    case installing
    case unavailable
    case permissionRequired
    case binaryMissing
}

struct ProviderReadiness: Equatable, Sendable {
    var kind: ProviderReadinessKind
    var message: String
    var actionTitle: String?

    var isReady: Bool {
        kind == .ready
    }

    static let ready = ProviderReadiness(kind: .ready, message: "Ready.", actionTitle: nil)
}

enum OperatingSystemFamily: String, CaseIterable, Codable, Sendable {
    case macOS = "macos"
    case windows

    var title: String {
        switch self {
        case .macOS:
            return "macOS"
        case .windows:
            return "Windows"
        }
    }
}

enum CPUArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64

    var title: String {
        rawValue
    }
}

enum AcceleratorClass: String, CaseIterable, Codable, Sendable {
    case none
    case appleSilicon = "apple_silicon"
    case nvidiaCUDA = "nvidia_cuda"

    var title: String {
        switch self {
        case .none:
            return "None"
        case .appleSilicon:
            return "Apple Silicon"
        case .nvidiaCUDA:
            return "NVIDIA CUDA"
        }
    }
}

struct SystemVersionInfo: Equatable, Codable, Sendable {
    var major: Int
    var minor: Int
    var patch: Int

    var title: String {
        "\(major).\(minor).\(patch)"
    }
}

struct SystemProfile: Equatable, Codable, Sendable {
    var osFamily: OperatingSystemFamily
    var osVersion: SystemVersionInfo
    var architecture: CPUArchitecture
    var accelerator: AcceleratorClass

    static var current: SystemProfile {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let osFamily: OperatingSystemFamily = .macOS
        #elseif os(Windows)
        let osFamily: OperatingSystemFamily = .windows
        #else
        let osFamily: OperatingSystemFamily = .macOS
        #endif

        #if arch(arm64)
        let architecture: CPUArchitecture = .arm64
        let accelerator: AcceleratorClass = .appleSilicon
        #elseif arch(x86_64)
        let architecture: CPUArchitecture = .x86_64
        let accelerator: AcceleratorClass = .none
        #else
        let architecture: CPUArchitecture = .x86_64
        let accelerator: AcceleratorClass = .none
        #endif

        return SystemProfile(
            osFamily: osFamily,
            osVersion: SystemVersionInfo(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion),
            architecture: architecture,
            accelerator: accelerator
        )
    }

    var summary: String {
        "\(osFamily.title) \(osVersion.title) • \(architecture.title) • \(accelerator.title)"
    }
}

struct CapabilityRequirement: Equatable, Codable, Sendable {
    var allowedOSFamilies: [OperatingSystemFamily]
    var allowedArchitectures: [CPUArchitecture]
    var requiredAccelerators: [AcceleratorClass]

    func supports(_ profile: SystemProfile) -> Bool {
        let osSupported = allowedOSFamilies.isEmpty || allowedOSFamilies.contains(profile.osFamily)
        let architectureSupported = allowedArchitectures.isEmpty || allowedArchitectures.contains(profile.architecture)
        let acceleratorSupported = requiredAccelerators.isEmpty || requiredAccelerators.contains(profile.accelerator)
        return osSupported && architectureSupported && acceleratorSupported
    }
}

enum CapabilityStatusKind: String, Codable, Sendable {
    case available
    case unsupported
    case supportedButNotReady = "supported_but_not_ready"

    var title: String {
        switch self {
        case .available:
            return "Available"
        case .unsupported:
            return "Unsupported"
        case .supportedButNotReady:
            return "Needs Setup"
        }
    }
}

struct CapabilityStatus: Equatable, Codable, Sendable {
    var kind: CapabilityStatusKind
    var reason: String?
    var actionTitle: String?

    static let available = CapabilityStatus(kind: .available, reason: nil, actionTitle: nil)

    var isAvailable: Bool {
        kind == .available
    }

    var isSupported: Bool {
        kind != .unsupported
    }

    var supportsSetupAction: Bool {
        kind == .supportedButNotReady && actionTitle != nil
    }

    var detail: String {
        reason ?? kind.title
    }
}

struct ProviderCapabilityDescriptor: Equatable, Codable, Sendable {
    var provider: ProviderID
    var title: String
    var requirements: CapabilityRequirement
    var unsupportedReason: String
}

enum FeatureID: String, CaseIterable, Identifiable, Codable, Sendable {
    case providerSelection = "provider_selection"
    case autoPaste = "auto_paste"
    case hotkeyCapture = "hotkey_capture"
    case modelManagement = "model_management"
    case appleSpeechAssets = "apple_speech_assets"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .providerSelection:
            return "Provider Selection"
        case .autoPaste:
            return "Auto-paste"
        case .hotkeyCapture:
            return "Hotkey Capture"
        case .modelManagement:
            return "Model Management"
        case .appleSpeechAssets:
            return "Apple Speech Assets"
        }
    }
}

struct FeatureCapabilityDescriptor: Equatable, Codable, Sendable {
    var feature: FeatureID
    var title: String
    var requirements: CapabilityRequirement
    var unsupportedReason: String
}

struct CapabilityManifest: Equatable, Codable, Sendable {
    var providers: [ProviderCapabilityDescriptor]
    var features: [FeatureCapabilityDescriptor]
}

struct DictionaryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var phrase: String
    var hint: String

    init(id: UUID = UUID(), phrase: String, hint: String = "") {
        self.id = id
        self.phrase = phrase
        self.hint = hint
    }
}

struct HistoryItem: Identifiable, Equatable, Sendable {
    var id: Int64
    var timestamp: Date
    var provider: String
    var language: String
    var originalText: String
    var finalPastedText: String
    var error: String?
}

struct HistoryDaySection: Identifiable, Equatable, Sendable {
    var bucketDate: Date
    var title: String
    var items: [HistoryItem]

    var id: Date { bucketDate }
}

enum HistorySectionBuilder {
    static func build(
        items: [HistoryItem],
        searchText: String,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [HistoryDaySection] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems: [HistoryItem]
        if trimmedSearch.isEmpty {
            filteredItems = items
        } else {
            let needle = trimmedSearch.localizedLowercase
            filteredItems = items.filter { item in
                let haystacks = [item.originalText, item.finalPastedText]
                return haystacks.contains { $0.localizedLowercase.contains(needle) }
            }
        }

        let grouped = Dictionary(grouping: filteredItems) { item in
            calendar.startOfDay(for: item.timestamp)
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        return grouped
            .map { bucketDate, bucketItems in
                let title: String
                if calendar.isDate(bucketDate, inSameDayAs: today) {
                    title = "Today"
                } else if calendar.isDate(bucketDate, inSameDayAs: yesterday) {
                    title = "Yesterday"
                } else {
                    title = bucketDate.formatted(date: .abbreviated, time: .omitted)
                }

                return HistoryDaySection(
                    bucketDate: bucketDate,
                    title: title,
                    items: bucketItems.sorted { $0.timestamp > $1.timestamp }
                )
            }
            .sorted { $0.bucketDate > $1.bucketDate }
    }
}

enum PasteMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoPaste = "auto_paste"
    case clipboardOnly = "clipboard_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoPaste: return "Auto-paste"
        case .clipboardOnly: return "Copy only"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedProvider: ProviderID = .appleSpeech
    var preferredLanguageID: String = "en-US"
    var selectedWhisperModelID: String = "base"
    var selectedParakeetModelID: String = "parakeet-tdt-0.6b-v3"
    var styleSettings: StyleSettings = .init()
    var dictationTrigger: DictationTriggerSettings = .init()
    var hotkey: KeyboardShortcut = .defaultShortcut
    var hotkeyEnabled: Bool = true
    var functionKeyFallbackMode: FunctionKeyFallbackMode = .automatic
    var pasteMode: PasteMode = .autoPaste
    var menuBarEnabled: Bool = true
    var showOverlay: Bool = true
    var onboardingCompleted: Bool = false
    var lastAppTab: AppTab = .home
    var lastSettingsTab: SettingsTab = .preferences

    enum CodingKeys: String, CodingKey {
        case selectedProvider
        case preferredLanguageID
        case selectedWhisperModelID
        case selectedParakeetModelID
        case styleSettings
        case dictationTrigger
        case hotkey
        case hotkeyEnabled
        case hotkeyTriggerMode
        case hotkeyBinding
        case functionKeyFallbackMode
        case pasteMode
        case menuBarEnabled
        case showOverlay
        case onboardingCompleted
        case lastAppTab
        case lastSettingsTab
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProvider = try container.decodeIfPresent(ProviderID.self, forKey: .selectedProvider) ?? .appleSpeech
        preferredLanguageID = try container.decodeIfPresent(String.self, forKey: .preferredLanguageID) ?? "en-US"
        selectedWhisperModelID = try container.decodeIfPresent(String.self, forKey: .selectedWhisperModelID) ?? "base"
        selectedParakeetModelID = try container.decodeIfPresent(String.self, forKey: .selectedParakeetModelID) ?? "parakeet-tdt-0.6b-v3"
        styleSettings = try container.decodeIfPresent(StyleSettings.self, forKey: .styleSettings) ?? .init()
        dictationTrigger = try container.decodeIfPresent(DictationTriggerSettings.self, forKey: .dictationTrigger) ?? .init()
        hotkey = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .hotkey) ?? .defaultShortcut
        hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? true
        let legacyTriggerMode = try container.decodeIfPresent(HotkeyTriggerMode.self, forKey: .hotkeyTriggerMode)
        let legacyBinding = try container.decodeIfPresent(HotkeyBinding.self, forKey: .hotkeyBinding)
        if container.contains(.dictationTrigger) == false {
            dictationTrigger.mode = legacyTriggerMode ?? .hold
            dictationTrigger.bindings.macos = legacyBinding ?? HotkeyBinding.fromLegacyShortcut(hotkey)
        } else {
            if let legacyTriggerMode {
                dictationTrigger.mode = legacyTriggerMode
            }
            if let legacyBinding {
                dictationTrigger.bindings.macos = legacyBinding
            }
        }
        functionKeyFallbackMode = try container.decodeIfPresent(FunctionKeyFallbackMode.self, forKey: .functionKeyFallbackMode) ?? .automatic
        pasteMode = try container.decodeIfPresent(PasteMode.self, forKey: .pasteMode) ?? .autoPaste
        menuBarEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? true
        showOverlay = try container.decodeIfPresent(Bool.self, forKey: .showOverlay) ?? true
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        lastAppTab = try container.decodeIfPresent(AppTab.self, forKey: .lastAppTab) ?? .home
        lastSettingsTab = try container.decodeIfPresent(SettingsTab.self, forKey: .lastSettingsTab) ?? .preferences
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProvider, forKey: .selectedProvider)
        try container.encode(preferredLanguageID, forKey: .preferredLanguageID)
        try container.encode(selectedWhisperModelID, forKey: .selectedWhisperModelID)
        try container.encode(selectedParakeetModelID, forKey: .selectedParakeetModelID)
        try container.encode(styleSettings, forKey: .styleSettings)
        try container.encode(dictationTrigger, forKey: .dictationTrigger)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
        try container.encode(functionKeyFallbackMode, forKey: .functionKeyFallbackMode)
        try container.encode(pasteMode, forKey: .pasteMode)
        try container.encode(menuBarEnabled, forKey: .menuBarEnabled)
        try container.encode(showOverlay, forKey: .showOverlay)
        try container.encode(onboardingCompleted, forKey: .onboardingCompleted)
        try container.encode(lastAppTab, forKey: .lastAppTab)
        try container.encode(lastSettingsTab, forKey: .lastSettingsTab)
    }

    var preferredLanguage: LanguageSelection {
        get { LanguageSelection(identifier: preferredLanguageID) }
        set { preferredLanguageID = newValue.identifier }
    }

    var hotkeyTriggerMode: HotkeyTriggerMode {
        get { dictationTrigger.mode }
        set { dictationTrigger.mode = newValue }
    }

    var hotkeyBinding: HotkeyBinding {
        get { dictationTrigger.bindings.macos }
        set { dictationTrigger.bindings.macos = newValue }
    }
}

struct PasteTarget: Sendable, Equatable {
    var appName: String?
    var bundleIdentifier: String?
    var processIdentifier: pid_t?
    var windowTitle: String?
    var focusedElementRole: String?
    var focusedElementSubrole: String?
    var focusedElementTitle: String?
    var focusedElementPlaceholder: String?
    var focusedElementDescription: String?
    var focusedValueSnippet: String?
    var isEditableTextInput: Bool
    var isSecureTextInput: Bool

    var editableRoleClass: String? {
        let combined = [focusedElementRole, focusedElementSubrole]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        if combined.contains("axtextarea") { return "text_area" }
        if combined.contains("axsearchfield") { return "search_field" }
        if combined.contains("axtextfield") || combined.contains("axtextinput") { return "text_field" }
        if combined.contains("axcombobox") { return "combo_box" }
        if combined.contains("axwebarea") { return "web_area" }
        return nil
    }
}

enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly(String)
    case failed(String)

    var message: String {
        switch self {
        case .pasted:
            return "Inserted."
        case .copiedOnly(let message), .failed(let message):
            return message
        }
    }
}

enum PasteFallbackReason: String, Codable, Sendable {
    case autoPasteDisabled
    case accessibilityUnavailable
    case appRestoreFailed
    case fieldNotEditable
    case fieldSecure
    case fieldMismatch
    case pasteEventFailed
    case clipboardWriteFailed
    case nothingToInsert

    var title: String {
        switch self {
        case .autoPasteDisabled:
            return "Auto-paste disabled"
        case .accessibilityUnavailable:
            return "Accessibility unavailable"
        case .appRestoreFailed:
            return "App restore failed"
        case .fieldNotEditable:
            return "Field not editable"
        case .fieldSecure:
            return "Secure field"
        case .fieldMismatch:
            return "Field no longer matched"
        case .pasteEventFailed:
            return "Paste event failed"
        case .clipboardWriteFailed:
            return "Clipboard write failed"
        case .nothingToInsert:
            return "Nothing to insert"
        }
    }
}

enum PasteInsertionOutcome: String, Codable, Sendable {
    case pasted
    case copiedSilently = "copied_silently"
    case failed

    var title: String {
        switch self {
        case .pasted:
            return "Pasted"
        case .copiedSilently:
            return "Copied silently"
        case .failed:
            return "Failed"
        }
    }
}

struct PasteInsertionDiagnostic: Equatable, Codable, Sendable {
    var requestedMode: PasteMode
    var targetAppName: String?
    var targetWindowTitle: String?
    var targetFieldRole: String?
    var targetFieldTitle: String?
    var targetFieldPlaceholder: String?
    var outcome: PasteInsertionOutcome
    var fallbackReason: PasteFallbackReason?
}

struct PasteOperationResult: Equatable, Sendable {
    var result: PasteResult
    var diagnostic: PasteInsertionDiagnostic
}

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var provider: ProviderID
    var name: String
    var detail: String
    var sizeLabel: String
    var downloadURL: String
    var expectedSizeBytes: Int64?
    var fileName: String?
    var extractDirectory: String?
    var supportedLanguageIDs: [String]
    var recommended: Bool
}

enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(Double?)
    case installing
    case ready
    case failed(String)
}

struct ModelStatus: Identifiable, Equatable, Sendable {
    var descriptor: ModelDescriptor
    var state: ModelInstallState
    var location: URL?

    var id: String { descriptor.id }
}

enum InstalledAssetSource: String, Codable, Equatable, Sendable {
    case importedFromOpenWhisprCache = "imported_openwhispr_cache"
    case downloadedByVerbatim = "downloaded_by_verbatim"

    var title: String {
        switch self {
        case .importedFromOpenWhisprCache:
            return "Imported from OpenWhispr cache"
        case .downloadedByVerbatim:
            return "Downloaded by Verbatim"
        }
    }
}

struct RuntimeHealthSnapshot: Equatable, Sendable {
    var binaryName: String
    var binaryPresent: Bool
    var state: RuntimeState
    var endpoint: String?
    var lastCheck: Date?
    var lastError: String?
    var logFileName: String
}

struct ProviderDiagnosticStatus: Identifiable, Equatable, Sendable {
    var provider: ProviderID
    var capability: CapabilityStatus
    var availability: ProviderAvailability
    var readiness: ProviderReadiness
    var selectionDescription: String
    var selectionInstalled: Bool
    var selectionSource: InstalledAssetSource?
    var runtimeSnapshot: RuntimeHealthSnapshot?
    var lastCheck: Date?
    var lastError: String?

    var id: ProviderID { provider }
}

struct DiagnosticEvent: Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var category: String
    var message: String

    init(id: UUID = UUID(), timestamp: Date = .now, category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

struct TranscriptionResult: Equatable, Sendable {
    var originalText: String
    var finalText: String
    var provider: ProviderID
    var language: LanguageSelection
}

protocol TranscriptionProvider: Sendable {
    var id: ProviderID { get }
    func availability() async -> ProviderAvailability
    func readiness(for language: LanguageSelection) async -> ProviderReadiness
    func transcribe(
        audioFileURL: URL,
        language: LanguageSelection,
        dictionaryHints: [DictionaryEntry]
    ) async throws -> TranscriptionResult
}

protocol DownloadableModelProvider: Sendable {
    func modelStatuses() async -> [ModelStatus]
    func downloadModel(id: String) async throws
    func deleteModel(id: String) async throws
}

protocol LocaleAssetProvider: Sendable {
    func installedLanguages() async -> [LanguageSelection]
    func installAssets(for language: LanguageSelection) async throws
}

protocol RecordingManagerProtocol: AnyObject, Sendable {
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func cancel()
}

protocol AudioNormalizationServiceProtocol: Sendable {
    func normalizeAudioFile(at sourceURL: URL) async throws -> URL
}

protocol PasteServiceProtocol: Sendable {
    func captureTarget() -> PasteTarget?
    func paste(
        text: String,
        to target: PasteTarget?,
        pasteMode: PasteMode,
        accessibilityGranted: Bool
    ) -> PasteOperationResult
}

protocol HistoryStoreProtocol: AnyObject, Sendable {
    func fetchHistory(limit: Int) -> [HistoryItem]
    func save(
        provider: ProviderID,
        language: LanguageSelection,
        originalText: String,
        finalText: String,
        error: String?
    ) -> HistoryItem
    func deleteHistory(id: Int64)
    func clearHistory()
    func fetchDictionary() -> [DictionaryEntry]
    func upsertDictionary(entry: DictionaryEntry)
    func deleteDictionary(id: UUID)
    func resetAll()
}

protocol SettingsStoreProtocol: AnyObject, Sendable {
    var settings: AppSettings { get }
    func replace(_ settings: AppSettings)
}
