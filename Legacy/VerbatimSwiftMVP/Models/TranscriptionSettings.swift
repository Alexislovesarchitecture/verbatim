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

    static var userFacingCases: [LocalTranscriptionModel] {
        [.whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeV3]
    }

    var isAppleModel: Bool {
        self == .appleOnDevice
    }

    var isWhisperModel: Bool {
        !isAppleModel
    }

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
            return "Apple Dictation with system-managed on-device speech assets"
        case .whisperTiny:
            return "74 MB · Fastest, lowest accuracy"
        case .whisperBase:
            return "141 MB · Recommended balance"
        case .whisperSmall:
            return "465 MB · Better accuracy, slower"
        case .whisperMedium:
            return "1.43 GB · High accuracy, heavy"
        case .whisperLargeV3:
            return "2.88 GB · Best quality, largest download"
        }
    }

    var backend: LocalTranscriptionBackend {
        switch self {
        case .appleOnDevice:
            return .appleSpeech
        case .whisperTiny, .whisperBase, .whisperSmall, .whisperMedium, .whisperLargeV3:
            return .whisperKitSDK
        }
    }

    var whisperCppModelName: String? {
        switch self {
        case .appleOnDevice:
            return nil
        case .whisperTiny:
            return "tiny"
        case .whisperBase:
            return "base"
        case .whisperSmall:
            return "small"
        case .whisperMedium:
            return "medium"
        case .whisperLargeV3:
            return "large-v3"
        }
    }

    var whisperModelName: String? {
        whisperCppModelName
    }

    var whisperKitModelName: String? {
        switch self {
        case .appleOnDevice:
            return nil
        case .whisperTiny:
            return "tiny"
        case .whisperBase:
            return "base"
        case .whisperSmall:
            return "small"
        case .whisperMedium:
            return "medium"
        case .whisperLargeV3:
            return "large-v3"
        }
    }

    var recommendedForFirstDownload: Bool {
        self == .whisperBase
    }
}

enum LocalTranscriptionEngineMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleSpeech = "apple_speech"
    case whisperKit = "whisperkit"
    case legacyWhisper = "legacy_whisper"

    var id: String { rawValue }

    static var userFacingCases: [LocalTranscriptionEngineMode] {
        [.appleSpeech, .whisperKit]
    }

    static func persistedValue(_ rawValue: String, selectedModel: LocalTranscriptionModel?) -> LocalTranscriptionEngineMode? {
        if let mode = LocalTranscriptionEngineMode(rawValue: rawValue) {
            switch mode {
            case .appleSpeech, .whisperKit:
                return mode
            case .legacyWhisper:
                return selectedModel?.isAppleModel == true ? .appleSpeech : .whisperKit
            }
        }

        switch rawValue {
        case "whisper_auto", "whisperkit_server", LocalTranscriptionEngineMode.legacyWhisper.rawValue:
            return selectedModel?.isWhisperModel == false ? .appleSpeech : .whisperKit
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .whisperKit:
            return "Whisper"
        case .legacyWhisper:
            return "Legacy Whisper"
        }
    }

    var subtitle: String {
        switch self {
        case .appleSpeech:
            return "On-device Apple transcription"
        case .whisperKit:
            return "Local WhisperKit transcription"
        case .legacyWhisper:
            return "Local whisper.cpp fallback"
        }
    }
}

enum WhisperKitServerConnectionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case managedHelper = "managed_helper"
    case externalServer = "external_server"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .managedHelper:
            return "Managed Helper"
        case .externalServer:
            return "External Server"
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

    static var setupCases: [HotkeyTriggerMode] {
        [.tapToToggle, .holdToTalk]
    }
}

enum AppSetupStep: String, CaseIterable, Identifiable, Codable, Sendable {
    case welcome
    case transcription
    case permissions
    case activation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .transcription:
            return "Setup"
        case .permissions:
            return "Permissions"
        case .activation:
            return "Activation"
        }
    }

    var stepLabel: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .transcription:
            return "Setup"
        case .permissions:
            return "Permissions"
        case .activation:
            return "Activation"
        }
    }

    var previousStep: AppSetupStep? {
        switch self {
        case .welcome:
            return nil
        case .transcription:
            return .welcome
        case .permissions:
            return .transcription
        case .activation:
            return .permissions
        }
    }

    var nextStep: AppSetupStep? {
        switch self {
        case .welcome:
            return .transcription
        case .transcription:
            return .permissions
        case .permissions:
            return .activation
        case .activation:
            return nil
        }
    }

    static var progressSteps: [AppSetupStep] {
        [.transcription, .permissions, .activation]
    }
}

enum AppSetupPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen Recording"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            return "Required to capture your voice."
        case .accessibility:
            return "Required for global hotkeys and insertion."
        case .screenRecording:
            return "Optional for meeting audio capture."
        }
    }

    var isRequired: Bool {
        switch self {
        case .microphone, .accessibility:
            return true
        case .screenRecording:
            return false
        }
    }

    var systemSettingsAnchor: String {
        switch self {
        case .microphone:
            return "Privacy_Microphone"
        case .accessibility:
            return "Privacy_Accessibility"
        case .screenRecording:
            return "Privacy_ScreenCapture"
        }
    }
}

struct AppSetupPermissionRowState: Identifiable, Equatable, Sendable {
    let kind: AppSetupPermissionKind
    let isGranted: Bool
    let detail: String
    let actionTitle: String

    var id: AppSetupPermissionKind { kind }
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
        validationResult.isValid
    }

    var usesFn: Bool {
        modifierKeyRawValue == Self.functionModifierRawValue
            || (modifierFlagsRawValue & Self.functionModifierRawValue != 0)
    }

    var hasNoOtherKeyOrModifier: Bool {
        modifierKeyRawValue == Self.functionModifierRawValue && modifierFlagsRawValue == 0
    }

    var isModifierOnly: Bool {
        modifierKeyRawValue != nil
    }

    var isModifierOnlyBinding: Bool {
        modifierKeyRawValue != nil
    }

    var isFunctionOnlyBinding: Bool {
        keyCode == Self.functionKeyCode
            && modifierKeyRawValue == Self.functionModifierRawValue
            && modifierFlagsRawValue == 0
    }

    var isStandardShortcutBinding: Bool {
        modifierKeyRawValue == nil
    }

    var validationResult: HotkeyValidationResult {
        HotkeyValidator().validate(self)
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

    static let recommendedFallbacks: [HotkeyBinding] = [
        .controlOptionSpace,
        .optionSpace,
        .commandShiftSpace
    ]
}

enum HotkeyValidationIssue: Identifiable, Equatable, Sendable {
    case noPrimaryKey
    case modifierOnlyNotAllowed
    case reservedBySystem(String)
    case fnOnlyRequiresSpecialHandling
    case likelyConflict(String)
    case awkwardModifierCombo(String)

    var id: String {
        switch self {
        case .noPrimaryKey:
            return "no_primary_key"
        case .modifierOnlyNotAllowed:
            return "modifier_only_not_allowed"
        case .reservedBySystem(let message):
            return "reserved_\(message)"
        case .fnOnlyRequiresSpecialHandling:
            return "fn_requires_special_handling"
        case .likelyConflict(let message):
            return "likely_conflict_\(message)"
        case .awkwardModifierCombo(let message):
            return "awkward_combo_\(message)"
        }
    }

    var isBlocking: Bool {
        switch self {
        case .noPrimaryKey, .modifierOnlyNotAllowed, .reservedBySystem, .fnOnlyRequiresSpecialHandling:
            return true
        case .likelyConflict, .awkwardModifierCombo:
            return false
        }
    }

    var message: String {
        switch self {
        case .noPrimaryKey:
            return "Choose a real key combination or Fn by itself."
        case .modifierOnlyNotAllowed:
            return "Modifier-only hotkeys are not supported unless the key is Fn."
        case .reservedBySystem(let description):
            return description
        case .fnOnlyRequiresSpecialHandling:
            return "This Fn combination is not supported for global capture."
        case .likelyConflict(let description):
            return description
        case .awkwardModifierCombo(let description):
            return description
        }
    }
}

struct HotkeyValidationResult: Equatable, Sendable {
    let issues: [HotkeyValidationIssue]

    var blockingIssues: [HotkeyValidationIssue] {
        issues.filter(\.isBlocking)
    }

    var warnings: [HotkeyValidationIssue] {
        issues.filter { !$0.isBlocking }
    }

    var isValid: Bool {
        blockingIssues.isEmpty
    }
}

struct HotkeyValidator: Sendable {
    func validate(_ binding: HotkeyBinding) -> HotkeyValidationResult {
        var issues: [HotkeyValidationIssue] = []

        if binding.keyDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.noPrimaryKey)
        }

        if binding.isModifierOnly && binding.modifierKeyRawValue != HotkeyBinding.functionModifierRawValue {
            issues.append(.modifierOnlyNotAllowed)
        }

        if binding.usesFn && !binding.hasNoOtherKeyOrModifier && binding.isModifierOnly == false {
            issues.append(.fnOnlyRequiresSpecialHandling)
        }

        if binding.keyCode == HotkeyBinding.spaceKeyCode {
            switch binding.modifierFlagsRawValue {
            case HotkeyBinding.commandModifierRawValue:
                issues.append(.reservedBySystem("Command + Space is reserved by macOS."))
            case HotkeyBinding.controlModifierRawValue:
                issues.append(.reservedBySystem("Control + Space is commonly reserved by input-source switching."))
            case HotkeyBinding.optionModifierRawValue:
                issues.append(.likelyConflict("Option + Space often conflicts with app-level shortcuts."))
            case HotkeyBinding.commandModifierRawValue | HotkeyBinding.shiftModifierRawValue:
                issues.append(.likelyConflict("Command + Shift + Space can conflict with app or system shortcuts."))
            default:
                break
            }
        }

        if binding.keyDisplay == "Tab", binding.modifierFlagsRawValue == HotkeyBinding.commandModifierRawValue {
            issues.append(.reservedBySystem("Command + Tab is reserved by app switching."))
        }

        let modifierCount = Self.modifierCount(for: binding.modifierFlagsRawValue)
            + (binding.modifierKeyRawValue == nil ? 0 : 1)
        if modifierCount >= 3 {
            issues.append(.awkwardModifierCombo("This shortcut uses many modifiers and may be awkward to hold reliably."))
        }

        return HotkeyValidationResult(issues: issues)
    }

    private static func modifierCount(for rawValue: UInt) -> Int {
        let values = [
            HotkeyBinding.commandModifierRawValue,
            HotkeyBinding.optionModifierRawValue,
            HotkeyBinding.controlModifierRawValue,
            HotkeyBinding.shiftModifierRawValue,
            HotkeyBinding.functionModifierRawValue
        ]
        return values.reduce(into: 0) { count, value in
            if rawValue & value != 0 {
                count += 1
            }
        }
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
    var functionKeyFallbackMode: FunctionKeyFallbackMode = .automatic
    var silenceDetectionEnabled: Bool = true
    var silenceSensitivity: SilenceSensitivity = .normal
    var alwaysTranscribeShortRecordings: Bool = false
    var lockTargetAtStart: Bool = true
    var showListeningIndicator: Bool = true
    var playSoundCues: Bool = false
    var autoPasteAfterInsert: Bool = true
    var insertionMode: RecordingInsertionMode = .autoPasteWhenPossible
    var showPermissionWarnings: Bool = true
    var clipboardRestoreMode: ClipboardRestoreMode = .manualOnly

    private enum CodingKeys: String, CodingKey {
        case hotkeyEnabled
        case hotkeyTriggerMode
        case hotkeyBinding
        case hotkeyPreset
        case functionKeyFallbackMode
        case silenceDetectionEnabled
        case silenceSensitivity
        case alwaysTranscribeShortRecordings
        case lockTargetAtStart
        case showListeningIndicator
        case playSoundCues
        case autoPasteAfterInsert
        case insertionMode
        case showPermissionWarnings
        case clipboardRestoreMode
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? false
        hotkeyTriggerMode = try container.decodeIfPresent(HotkeyTriggerMode.self, forKey: .hotkeyTriggerMode) ?? .holdToTalk
        functionKeyFallbackMode = try container.decodeIfPresent(FunctionKeyFallbackMode.self, forKey: .functionKeyFallbackMode) ?? .automatic
        silenceDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .silenceDetectionEnabled) ?? true
        silenceSensitivity = try container.decodeIfPresent(SilenceSensitivity.self, forKey: .silenceSensitivity) ?? .normal
        alwaysTranscribeShortRecordings = try container.decodeIfPresent(Bool.self, forKey: .alwaysTranscribeShortRecordings) ?? false
        lockTargetAtStart = try container.decodeIfPresent(Bool.self, forKey: .lockTargetAtStart) ?? true
        showListeningIndicator = try container.decodeIfPresent(Bool.self, forKey: .showListeningIndicator) ?? true
        playSoundCues = try container.decodeIfPresent(Bool.self, forKey: .playSoundCues) ?? false
        autoPasteAfterInsert = try container.decodeIfPresent(Bool.self, forKey: .autoPasteAfterInsert) ?? true
        insertionMode = try container.decodeIfPresent(RecordingInsertionMode.self, forKey: .insertionMode) ?? .autoPasteWhenPossible
        showPermissionWarnings = try container.decodeIfPresent(Bool.self, forKey: .showPermissionWarnings) ?? true
        clipboardRestoreMode = try container.decodeIfPresent(ClipboardRestoreMode.self, forKey: .clipboardRestoreMode) ?? .manualOnly

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
        try container.encode(functionKeyFallbackMode, forKey: .functionKeyFallbackMode)
        try container.encode(silenceDetectionEnabled, forKey: .silenceDetectionEnabled)
        try container.encode(silenceSensitivity, forKey: .silenceSensitivity)
        try container.encode(alwaysTranscribeShortRecordings, forKey: .alwaysTranscribeShortRecordings)
        try container.encode(lockTargetAtStart, forKey: .lockTargetAtStart)
        try container.encode(showListeningIndicator, forKey: .showListeningIndicator)
        try container.encode(playSoundCues, forKey: .playSoundCues)
        try container.encode(autoPasteAfterInsert, forKey: .autoPasteAfterInsert)
        try container.encode(insertionMode, forKey: .insertionMode)
        try container.encode(showPermissionWarnings, forKey: .showPermissionWarnings)
        try container.encode(clipboardRestoreMode, forKey: .clipboardRestoreMode)
    }
}
