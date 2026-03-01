import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"
    case notes = "Notes"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .home: return "house.fill"
        case .dictionary: return "book.closed.fill"
        case .snippets: return "text.badge.plus"
        case .style: return "textformat"
        case .notes: return "note.text"
        case .settings: return "gearshape.fill"
        }
    }
}

enum HomeHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case inserted = "Inserted"
    case clipboard = "Clipboard"
    case failed = "Failed"

    var id: String { rawValue }

    var status: CaptureStatus? {
        switch self {
        case .all: return nil
        case .inserted: return .inserted
        case .clipboard: return .clipboard
        case .failed: return .failed
        }
    }
}

enum CaptureStatus: String, Codable, CaseIterable, Identifiable {
    case inserted
    case clipboard
    case failed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .inserted: return "Inserted"
        case .clipboard: return "Clipboard"
        case .failed: return "Failed"
        }
    }
}

enum EngineUsed: String, Codable, CaseIterable, Identifiable {
    case openai
    case whispercpp

    var id: String { rawValue }
    var title: String { rawValue == "openai" ? "OpenAI" : "whisper.cpp" }
}

enum DictionaryScope: String, Codable, CaseIterable, Identifiable {
    case personal
    case sharedStub

    var id: String { rawValue }
    var title: String { rawValue == "sharedStub" ? "Shared" : "Personal" }
}

enum DictionaryKind: String, Codable, CaseIterable, Identifiable {
    case term
    case replacement
    case expansion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .term: return "Term"
        case .replacement: return "Replacement"
        case .expansion: return "Expansion"
        }
    }
}

enum SnippetScope: String, Codable, CaseIterable, Identifiable {
    case personal
    case sharedStub

    var id: String { rawValue }
    var title: String { rawValue == "sharedStub" ? "Shared" : "Personal" }
}

enum StyleCategory: String, Codable, CaseIterable, Identifiable {
    case personal
    case work
    case email
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal messages"
        case .work: return "Work messages"
        case .email: return "Email"
        case .other: return "Other"
        }
    }
}

enum StyleTone: String, Codable, CaseIterable, Identifiable {
    case formal
    case casual
    case veryCasual
    case excitedOptional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .veryCasual: return "Very casual"
        case .excitedOptional: return "Excited"
        }
    }
}

enum CapsMode: String, Codable, CaseIterable, Identifiable {
    case sentenceCase
    case lowercase

    var id: String { rawValue }
}

enum PunctuationMode: String, Codable, CaseIterable, Identifiable {
    case normal
    case light

    var id: String { rawValue }
}

enum ExclamationMode: String, Codable, CaseIterable, Identifiable {
    case normal
    case more
    case none

    var id: String { rawValue }
}

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case whispercpp

    var id: String { rawValue }
    var title: String { rawValue == "openai" ? "OpenAI" : "whisper.cpp" }
}

enum WhisperLocalBackend: String, Codable, CaseIterable, Identifiable {
    case server
    case cli

    var id: String { rawValue }
    var title: String {
        switch self {
        case .server:
            return "Local server"
        case .cli:
            return "Legacy CLI"
        }
    }
}

enum WhisperLocalModelId: String, Codable, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case medium
    case large
    case turbo

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum OpenAITranscriptionModel: String, Codable, CaseIterable, Identifiable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeDiarize = "gpt-4o-transcribe-diarize"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpt4oMiniTranscribe: return "gpt-4o-mini-transcribe"
        case .gpt4oTranscribe: return "gpt-4o-transcribe"
        case .gpt4oTranscribeDiarize: return "gpt-4o-transcribe-diarize"
        }
    }
}

enum InsertionModePreferred: String, Codable, CaseIterable, Identifiable {
    case accessibilityFirst
    case pasteOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibilityFirst: return "Accessibility first"
        case .pasteOnly: return "Paste only"
        }
    }
}

enum CaptureUICue: String, Codable, CaseIterable {
    case idle
    case recording
    case recordingLocked
    case transcribing
    case inserting
    case clipboardReady
    case error

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .recording: return "Hold to record"
        case .recordingLocked: return "Locked"
        case .transcribing: return "Transcribing"
        case .inserting: return "Inserting"
        case .clipboardReady: return "Ready"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "waveform"
        case .recordingLocked: return "lock.fill"
        case .transcribing: return "clock.arrow.2.circlepath"
        case .inserting: return "arrow.left.arrow.right"
        case .clipboardReady: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle"
        }
    }
}
