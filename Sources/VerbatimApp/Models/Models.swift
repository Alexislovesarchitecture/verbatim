import Foundation

enum SidebarRoute: String, CaseIterable, Codable, Identifiable {
    case home
    case dictionary
    case snippets
    case style
    case notes
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .notes: return "Notes"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "book.closed"
        case .snippets: return "text.insert"
        case .style: return "textformat"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

enum DictationPhase: String, Codable {
    case idle
    case recordingPush
    case recordingLocked
    case transcribing
    case inserting
    case clipboardReady
    case failed
}

enum TranscriptOrigin: String, Codable, CaseIterable, Identifiable {
    case mock
    case openAI
    case whisperCPP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: return "Mock"
        case .openAI: return "OpenAI"
        case .whisperCPP: return "Local whisper.cpp"
        }
    }
}

enum InsertOutcome: String, Codable {
    case inserted
    case clipboardReady
    case failed
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

struct TranscriptRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var timestamp: Date
    var activeAppName: String
    var rawTranscript: String
    var formattedTranscript: String
    var engine: TranscriptOrigin
    var outcome: InsertOutcome
    var durationSeconds: Double
    var wordsPerMinute: Int
    var notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        activeAppName: String,
        rawTranscript: String,
        formattedTranscript: String,
        engine: TranscriptOrigin,
        outcome: InsertOutcome,
        durationSeconds: Double,
        wordsPerMinute: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.activeAppName = activeAppName
        self.rawTranscript = rawTranscript
        self.formattedTranscript = formattedTranscript
        self.engine = engine
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.wordsPerMinute = wordsPerMinute
        self.notes = notes
    }
}

struct DictionaryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var source: String
    var replacement: String
    var learnedAutomatically: Bool

    init(id: UUID = UUID(), source: String, replacement: String, learnedAutomatically: Bool = false) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.learnedAutomatically = learnedAutomatically
    }
}

struct SnippetEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

struct StyleProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: StyleCategory
    var sentenceCase: Bool
    var punctuationLevel: Double
    var exclamationRate: Int
    var fillerRemovalEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        category: StyleCategory,
        sentenceCase: Bool,
        punctuationLevel: Double,
        exclamationRate: Int,
        fillerRemovalEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.sentenceCase = sentenceCase
        self.punctuationLevel = punctuationLevel
        self.exclamationRate = exclamationRate
        self.fillerRemovalEnabled = fillerRemovalEnabled
    }
}

struct NoteItem: Codable, Identifiable, Hashable {
    let id: UUID
    var createdAt: Date
    var title: String
    var body: String

    init(id: UUID = UUID(), createdAt: Date = .now, title: String, body: String) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
    }
}

struct UserSettings: Codable, Hashable {
    var selectedEngine: TranscriptOrigin
    var openAIAPIKey: String
    var openAIModel: String
    var whisperBinaryPath: String
    var whisperModelPath: String
    var selectedLanguageCode: String
    var autoInsertWhenEditable: Bool
    var playStartSound: Bool
    var playStopSound: Bool
    var doubleTapLockWindowSeconds: Double
    var fallbackCopiesToClipboard: Bool

    static let `default` = UserSettings(
        selectedEngine: .mock,
        openAIAPIKey: "",
        openAIModel: "gpt-4o-mini-transcribe",
        whisperBinaryPath: "/opt/homebrew/bin/whisper-cli",
        whisperModelPath: "",
        selectedLanguageCode: "en",
        autoInsertWhenEditable: true,
        playStartSound: true,
        playStopSound: false,
        doubleTapLockWindowSeconds: 0.32,
        fallbackCopiesToClipboard: true
    )
}

struct LastCapture: Codable, Hashable {
    var transcript: String
    var createdAt: Date
}

struct SeedData {
    static let dictionary: [DictionaryEntry] = [
        .init(source: "verbatim", replacement: "Verbatim", learnedAutomatically: true),
        .init(source: "open wiser", replacement: "open-wispr"),
        .init(source: "free flow", replacement: "FreeFlow"),
        .init(source: "Alexis", replacement: "Alexis", learnedAutomatically: true)
    ]

    static let snippets: [SnippetEntry] = [
        .init(trigger: "my email address", expansion: "alexislovesarchitecture@gmail.com"),
        .init(trigger: "organize thoughts prompt", expansion: "Organize these unstructured thoughts into a clear polished version without adding content or changing meaning."),
        .init(trigger: "project update intro", expansion: "Here is the current status, the open items, the risks, and the next action needed from your side.")
    ]

    static let styles: [StyleProfile] = [
        .init(name: "Formal", category: .personal, sentenceCase: true, punctuationLevel: 1.0, exclamationRate: 0),
        .init(name: "Casual", category: .personal, sentenceCase: true, punctuationLevel: 0.55, exclamationRate: 0),
        .init(name: "Very casual", category: .personal, sentenceCase: false, punctuationLevel: 0.25, exclamationRate: 0),
        .init(name: "Formal", category: .work, sentenceCase: true, punctuationLevel: 1.0, exclamationRate: 0),
        .init(name: "Casual", category: .work, sentenceCase: true, punctuationLevel: 0.65, exclamationRate: 0),
        .init(name: "Formal", category: .email, sentenceCase: true, punctuationLevel: 1.0, exclamationRate: 0),
        .init(name: "Casual", category: .email, sentenceCase: true, punctuationLevel: 0.7, exclamationRate: 1),
        .init(name: "Excited", category: .other, sentenceCase: true, punctuationLevel: 0.8, exclamationRate: 2),
        .init(name: "Casual", category: .other, sentenceCase: true, punctuationLevel: 0.55, exclamationRate: 0)
    ]

    static let history: [TranscriptRecord] = [
        .init(activeAppName: "Notes", rawTranscript: "make the status page easier to scan with more spacing between cards", formattedTranscript: "Make the status page easier to scan with more spacing between cards.", engine: .mock, outcome: .inserted, durationSeconds: 6, wordsPerMinute: 110),
        .init(activeAppName: "Mail", rawTranscript: "hey can we move the call to tomorrow morning question mark", formattedTranscript: "Hey, can we move the call to tomorrow morning?", engine: .mock, outcome: .clipboardReady, durationSeconds: 4.2, wordsPerMinute: 128, notes: "Focused field missing, copied to clipboard."),
        .init(activeAppName: "Figma", rawTranscript: "scratch that use a cleaner timeline card layout", formattedTranscript: "Use a cleaner timeline card layout.", engine: .mock, outcome: .inserted, durationSeconds: 3.5, wordsPerMinute: 120)
    ]

    static let notes: [NoteItem] = [
        .init(title: "Verbatim MVP", body: "Finish the function-key loop, clipboard fallback, and floating listening capsule before adding aggressive AI cleanup."),
        .init(title: "Formatter ideas", body: "Keep the first version deterministic. Add punctuation, new paragraph, filler removal, snippet expansion, and dictionary corrections first.")
    ]
}
