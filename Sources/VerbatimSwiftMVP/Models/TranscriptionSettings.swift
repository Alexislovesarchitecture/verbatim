import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable {
    case remote
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote:
            return "Remote"
        case .local:
            return "Local"
        }
    }

    var subtitle: String {
        switch self {
        case .remote:
            return "OpenAI API"
        case .local:
            return "On-device"
        }
    }
}

enum LogicMode: String, CaseIterable, Identifiable, Sendable {
    case remote
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote:
            return "Remote"
        case .local:
            return "Local"
        }
    }

    var subtitle: String {
        switch self {
        case .remote:
            return "OpenAI-compatible API"
        case .local:
            return "Phase 2: gpt-oss-20b"
        }
    }
}

enum LogicOutputFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case paragraph
    case bullets

    var id: String { rawValue }
}

enum LogicReasoningEffort: String, CaseIterable, Identifiable, Codable, Sendable {
    case modelDefault = "model_default"
    case minimal
    case low
    case medium
    case high
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modelDefault:
            return "Default"
        case .minimal:
            return "Minimal"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .off:
            return "Off"
        }
    }
}

enum SelfCorrectionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case keepAll = "keep_all"
    case keepFinal = "keep_final"
    case annotate = "annotate"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepAll:
            return "Keep all"
        case .keepFinal:
            return "Keep final"
        case .annotate:
            return "Annotate"
        }
    }
}

enum TranscriptViewMode: String, CaseIterable, Identifiable, Sendable {
    case raw
    case formatted

    var id: String { rawValue }
}

enum LocalTranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case appleOnDevice = "apple-on-device"
    case whisperTiny = "whisper-tiny"
    case whisperBase = "whisper-base"
    case whisperSmall = "whisper-small"
    case whisperMedium = "whisper-medium"
    case whisperLargeV3 = "whisper-large-v3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice:
            return "Apple On-Device"
        case .whisperTiny:
            return "Whisper Tiny"
        case .whisperBase:
            return "Whisper Base"
        case .whisperSmall:
            return "Whisper Small"
        case .whisperMedium:
            return "Whisper Medium"
        case .whisperLargeV3:
            return "Whisper Large v3"
        }
    }

    var detail: String {
        switch self {
        case .appleOnDevice:
            return "Built-in Apple Speech framework"
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeV3:
            return "Coming soon"
        }
    }

    var isImplemented: Bool {
        switch self {
        case .appleOnDevice:
            return true
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeV3:
            return false
        }
    }
}

enum HotkeyTriggerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case holdToTalk = "hold_to_talk"
    case tapToToggle = "tap_to_toggle"
    case doubleTapLock = "double_tap_lock"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk:
            return "Hold to Talk"
        case .tapToToggle:
            return "Tap to Toggle"
        case .doubleTapLock:
            return "Double Tap to Lock"
        }
    }
}

struct HotkeyBinding: Codable, Hashable, Sendable {
    static let commandModifierRawValue: UInt = 1 << 20
    static let optionModifierRawValue: UInt = 1 << 19
    static let controlModifierRawValue: UInt = 1 << 18
    static let shiftModifierRawValue: UInt = 1 << 17
    static let functionModifierRawValue: UInt = 1 << 23
    static let relevantModifierMask: UInt = commandModifierRawValue
        | optionModifierRawValue
        | controlModifierRawValue
        | shiftModifierRawValue
        | functionModifierRawValue

    static let functionKeyCode: UInt16 = 63
    static let spaceKeyCode: UInt16 = 49

    var keyCode: UInt16
    var modifierFlagsRawValue: UInt
    var keyDisplay: String
    var modifierKeyRawValue: UInt?

    var displayTitle: String {
        let parts = Self.modifierNames(from: modifierFlagsRawValue) + [keyDisplay]
        return parts.joined(separator: " + ")
    }

    var isValidGlobalHotkey: Bool {
        modifierKeyRawValue != nil || modifierFlagsRawValue != 0
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

    static var commandShiftSpace: HotkeyBinding {
        HotkeyBinding(
            keyCode: spaceKeyCode,
            modifierFlagsRawValue: commandModifierRawValue | shiftModifierRawValue,
            keyDisplay: "Space",
            modifierKeyRawValue: nil
        )
    }

    fileprivate static func legacyPreset(_ preset: LegacyHotkeyPreset) -> HotkeyBinding {
        switch preset {
        case .optionSpace:
            return .optionSpace
        case .controlSpace:
            return .controlSpace
        case .commandShiftSpace:
            return .commandShiftSpace
        }
    }

    static func modifierLabel(for rawValue: UInt) -> String? {
        switch rawValue {
        case controlModifierRawValue:
            return "Control"
        case optionModifierRawValue:
            return "Option"
        case shiftModifierRawValue:
            return "Shift"
        case commandModifierRawValue:
            return "Command"
        case functionModifierRawValue:
            return "Fn"
        default:
            return nil
        }
    }

    private static func modifierNames(from rawValue: UInt) -> [String] {
        var names: [String] = []
        if rawValue & controlModifierRawValue != 0 { names.append("Control") }
        if rawValue & optionModifierRawValue != 0 { names.append("Option") }
        if rawValue & shiftModifierRawValue != 0 { names.append("Shift") }
        if rawValue & commandModifierRawValue != 0 { names.append("Command") }
        if rawValue & functionModifierRawValue != 0 { names.append("Fn") }
        return names
    }
}

private enum LegacyHotkeyPreset: String, Codable {
    case optionSpace = "option_space"
    case controlSpace = "control_space"
    case commandShiftSpace = "command_shift_space"
}

#if canImport(AppKit)
extension HotkeyBinding {
    static func capture(from event: NSEvent) -> HotkeyBinding? {
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return nil }
            guard let keyDisplay = keyLabel(from: event) else { return nil }
            let modifierFlags = event.modifierFlags.rawValue & relevantModifierMask
            return HotkeyBinding(
                keyCode: event.keyCode,
                modifierFlagsRawValue: modifierFlags,
                keyDisplay: keyDisplay,
                modifierKeyRawValue: nil
            )
        case .flagsChanged:
            guard let modifierKeyRawValue = modifierFlagRawValue(forKeyCode: event.keyCode),
                  let keyDisplay = modifierLabel(for: modifierKeyRawValue) else {
                return nil
            }
            let modifierFlags = event.modifierFlags.rawValue & relevantModifierMask
            guard modifierFlags & modifierKeyRawValue != 0 else {
                return nil
            }
            let otherModifiers = modifierFlags & ~modifierKeyRawValue
            return HotkeyBinding(
                keyCode: event.keyCode,
                modifierFlagsRawValue: otherModifiers,
                keyDisplay: keyDisplay,
                modifierKeyRawValue: modifierKeyRawValue
            )
        default:
            return nil
        }
    }

    private static func keyLabel(from event: NSEvent) -> String? {
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            switch chars {
            case " ":
                return "Space"
            case "\r":
                return "Return"
            case "\t":
                return "Tab"
            case String(UnicodeScalar(127)):
                return "Delete"
            default:
                if chars.rangeOfCharacter(from: .controlCharacters) == nil {
                    return chars.uppercased()
                }
            }
        }

        switch event.keyCode {
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default:
            return "Key \(event.keyCode)"
        }
    }

    static func modifierFlagRawValue(forKeyCode keyCode: UInt16) -> UInt? {
        switch keyCode {
        case 55, 54:
            return commandModifierRawValue
        case 56, 60:
            return shiftModifierRawValue
        case 58, 61:
            return optionModifierRawValue
        case 59, 62:
            return controlModifierRawValue
        case 63:
            return functionModifierRawValue
        default:
            return nil
        }
    }
}
#endif

struct InteractionSettings: Codable, Sendable {
    var hotkeyEnabled: Bool = false
    var hotkeyTriggerMode: HotkeyTriggerMode = .holdToTalk
    var hotkeyBinding: HotkeyBinding = .defaultFunctionKey
    var showListeningIndicator: Bool = true
    var playSoundCues: Bool = false
    var autoPasteAfterInsert: Bool = true

    private enum CodingKeys: String, CodingKey {
        case hotkeyEnabled
        case hotkeyTriggerMode
        case hotkeyBinding
        case hotkeyPreset
        case showListeningIndicator
        case playSoundCues
        case autoPasteAfterInsert
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? false
        hotkeyTriggerMode = try container.decodeIfPresent(HotkeyTriggerMode.self, forKey: .hotkeyTriggerMode) ?? .holdToTalk
        showListeningIndicator = try container.decodeIfPresent(Bool.self, forKey: .showListeningIndicator) ?? true
        playSoundCues = try container.decodeIfPresent(Bool.self, forKey: .playSoundCues) ?? false
        autoPasteAfterInsert = try container.decodeIfPresent(Bool.self, forKey: .autoPasteAfterInsert) ?? true

        if let binding = try container.decodeIfPresent(HotkeyBinding.self, forKey: .hotkeyBinding) {
            hotkeyBinding = binding
        } else if let legacyPreset = try container.decodeIfPresent(LegacyHotkeyPreset.self, forKey: .hotkeyPreset) {
            hotkeyBinding = HotkeyBinding.legacyPreset(legacyPreset)
        } else {
            hotkeyBinding = .defaultFunctionKey
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
        try container.encode(hotkeyTriggerMode, forKey: .hotkeyTriggerMode)
        try container.encode(hotkeyBinding, forKey: .hotkeyBinding)
        try container.encode(showListeningIndicator, forKey: .showListeningIndicator)
        try container.encode(playSoundCues, forKey: .playSoundCues)
        try container.encode(autoPasteAfterInsert, forKey: .autoPasteAfterInsert)
    }
}
