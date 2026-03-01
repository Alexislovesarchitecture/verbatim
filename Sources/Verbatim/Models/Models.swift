import Foundation

enum SidebarSection: String, CaseIterable, Identifiable, Codable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"
    case notes = "Notes"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "textformat"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

enum ListeningState: String, Codable {
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
        case .recording: return "Listening"
        case .recordingLocked: return "Locked"
        case .transcribing: return "Transcribing"
        case .inserting: return "Inserting"
        case .clipboardReady: return "Ready to paste"
        case .error: return "Error"
        }
    }
}

enum InsertResult: String, Codable {
    case inserted
    case pastedViaClipboard
    case clipboardOnly
    case failed

    var label: String {
        switch self {
        case .inserted: return "Inserted"
        case .pastedViaClipboard: return "Pasted"
        case .clipboardOnly: return "Clipboard"
        case .failed: return "Failed"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable, Codable, Identifiable {
    case openAI = "OpenAI"
    case whisperCLI = "Local whisper.cpp"

    var id: String { rawValue }
}

enum StyleTone: String, CaseIterable, Codable, Identifiable {
    case formal = "Formal"
    case casual = "Casual"
    case veryCasual = "Very casual"
    case excited = "Excited"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .formal: return "Caps + punctuation"
        case .casual: return "Caps + lighter punctuation"
        case .veryCasual: return "Less caps + less punctuation"
        case .excited: return "More energy"
        }
    }

    var sample: String {
        switch self {
        case .formal:
            return "Hey, are you free for lunch tomorrow? Let’s do 12 if that works for you."
        case .casual:
            return "Hey, are you free for lunch tomorrow? Let’s do 12 if that works for you"
        case .veryCasual:
            return "hey are you free for lunch tomorrow? let’s do 12 if that works for you"
        case .excited:
            return "Hey, are you free for lunch tomorrow? Let’s do 12 if that works for you!"
        }
    }
}

enum AppStyleCategory: String, CaseIterable, Codable, Identifiable {
    case personal = "Personal messages"
    case work = "Work messages"
    case email = "Email"
    case other = "Other"

    var id: String { rawValue }
}

struct DictationEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var rawText: String
    var formattedText: String
    var destinationApp: String
    var durationSeconds: Double
    var result: InsertResult
    var inputWasSilent: Bool = false

    var wordCount: Int {
        formattedText.split(whereSeparator: { $0.isWhitespace }).count
    }

    var wordsPerMinute: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(wordCount) / durationSeconds) * 60.0)
    }
}

struct DictionaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var phrase: String
    var replacement: String?
    var isLearned: Bool = false
}

struct SnippetEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var trigger: String
    var expansion: String
}

struct NoteEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var title: String
    var body: String
}

struct AppSettings: Codable {
    var displayName: String = "Alexis"
    var provider: TranscriptionProvider = .openAI
    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4o-mini-transcribe"
    var whisperCLIPath: String = "/opt/homebrew/bin/whisper-cli"
    var whisperModelPath: String = ""
    var languageCode: String = "en"
    var autoInsert: Bool = true
    var autoPasteFallback: Bool = true
    var playStartSound: Bool = true
    var removeFillers: Bool = true
    var useSnippetExpansion: Bool = true
    var keepHistory: Bool = true
    var keepClipboardBackup: Bool = true
    var personalTone: StyleTone = .casual
    var workTone: StyleTone = .formal
    var emailTone: StyleTone = .formal
    var otherTone: StyleTone = .casual

    func tone(for category: AppStyleCategory) -> StyleTone {
        switch category {
        case .personal: return personalTone
        case .work: return workTone
        case .email: return emailTone
        case .other: return otherTone
        }
    }

    mutating func setTone(_ tone: StyleTone, for category: AppStyleCategory) {
        switch category {
        case .personal: personalTone = tone
        case .work: workTone = tone
        case .email: emailTone = tone
        case .other: otherTone = tone
        }
    }
}

struct PersistedState: Codable {
    var settings: AppSettings
    var entries: [DictationEntry]
    var dictionaryEntries: [DictionaryEntry]
    var snippetEntries: [SnippetEntry]
    var noteEntries: [NoteEntry]
}

extension PersistedState {
    static let sample = PersistedState(
        settings: AppSettings(),
        entries: [
            DictationEntry(rawText: "I want to make it so the app stores the capture even if I missed the text field", formattedText: "I want Verbatim to store the capture even if I missed the text field.", destinationApp: "Notes", durationSeconds: 5.2, result: .clipboardOnly),
            DictationEntry(rawText: "Add a start sound and a lock button", formattedText: "Add a start sound and a lock button.", destinationApp: "Xcode", durationSeconds: 2.8, result: .inserted)
        ],
        dictionaryEntries: [
            DictionaryEntry(phrase: "Verbatim", replacement: nil, isLearned: true),
            DictionaryEntry(phrase: "Wispr", replacement: nil, isLearned: true),
            DictionaryEntry(phrase: "Fn", replacement: nil, isLearned: true),
            DictionaryEntry(phrase: "cmd v", replacement: "Command-V", isLearned: false)
        ],
        snippetEntries: [
            SnippetEntry(trigger: "my email address", expansion: "alexislovesarchitecture@gmail.com"),
            SnippetEntry(trigger: "organize thoughts prompt", expansion: "Organize these unstructured thoughts into a clear, polished version without adding new claims or changing meaning."),
            SnippetEntry(trigger: "meeting link", expansion: "You can book a time with me here: https://calendly.com/your-link")
        ],
        noteEntries: [
            NoteEntry(title: "Verbatim MVP", body: "Must keep last capture, support Fn hold-to-talk, lock mode, overlay, and clipboard fallback.")
        ]
    )
}
