import Foundation

enum TranscriptionMode: String, CaseIterable, Identifiable {
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

enum LogicMode: String, CaseIterable, Identifiable {
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

enum LogicOutputFormat: String, CaseIterable, Identifiable, Codable {
    case auto
    case paragraph
    case bullets

    var id: String { rawValue }
}

enum LogicReasoningEffort: String, CaseIterable, Identifiable, Codable {
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

enum SelfCorrectionMode: String, CaseIterable, Identifiable, Codable {
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

enum TranscriptViewMode: String, CaseIterable, Identifiable {
    case raw
    case formatted

    var id: String { rawValue }
}

enum LocalTranscriptionModel: String, CaseIterable, Identifiable {
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
