import Foundation

enum StyleCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case email
    case personal
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work:
            return "Work"
        case .email:
            return "Email"
        case .personal:
            return "Personal"
        case .other:
            return "Other"
        }
    }

    var defaultPreset: StylePreset {
        switch self {
        case .work, .email:
            return .formal
        case .personal, .other:
            return .casual
        }
    }

    var availablePresets: [StylePreset] {
        switch self {
        case .personal:
            return [.formal, .casual, .veryCasual]
        case .work, .email, .other:
            return [.formal, .casual, .enthusiastic]
        }
    }

    func supports(_ preset: StylePreset) -> Bool {
        availablePresets.contains(preset)
    }

    func resolvedPreset(_ preset: StylePreset) -> StylePreset {
        supports(preset) ? preset : defaultPreset
    }

    func presetDefinition(for preset: StylePreset, emailSignatureName: String) -> StylePresetDefinition {
        let resolved = resolvedPreset(preset)
        let trimmedSignature = emailSignatureName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (self, resolved) {
        case (.personal, .formal):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Formal",
                summary: "Correct capitalization, punctuation, grammar, and clean message structure.",
                ruleSummary: "Caps: full. Punctuation: full. Format: message. Structure: polished.",
                instructionPrefix: "Rewrite the text as a formal personal message. Use correct capitalization, punctuation, and grammar. Keep the original intent and overall structure, but make the phrasing clean and readable. Do not make it sound corporate or add new information. Return only the final message."
            )
        case (.personal, .casual):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Casual",
                summary: "Relaxed capitalization and punctuation with the same structure and cleaner spelling.",
                ruleSummary: "Caps: relaxed. Punctuation: light. Format: message. Structure: unchanged.",
                instructionPrefix: "Rewrite the text as a casual personal message. Clean up spelling and obvious grammar issues, but keep capitalization and punctuation relaxed when natural. Preserve the same structure and intent. Return only the final message."
            )
        case (.personal, .veryCasual):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Very Casual",
                summary: "Mostly preserve the loose message style, fix spelling, and keep punctuation minimal.",
                ruleSummary: "Caps: minimal. Punctuation: minimal. Format: message. Structure: mostly untouched.",
                instructionPrefix: "Rewrite the text as a very casual personal message. Correct spelling and obvious transcription errors, but keep capitalization minimal, punctuation light, and the original loose structure. Do not add emphasis, emojis, or polished phrasing. Return only the final message."
            )
        case (.work, .formal):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Formal",
                summary: "Professional capitalization, punctuation, grammar, and clear work-ready structure.",
                ruleSummary: "Caps: full. Punctuation: full. Format: professional. Structure: organized.",
                instructionPrefix: "Rewrite the text as a formal work message. Use professional capitalization, punctuation, and grammar. Keep the structure clear and email-ready when appropriate, without inventing details or sounding stiff. Return only the final message."
            )
        case (.work, .casual):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Casual",
                summary: "Professional but relaxed wording with moderate punctuation and the same message structure.",
                ruleSummary: "Caps: moderate. Punctuation: moderate. Format: work message. Structure: preserved.",
                instructionPrefix: "Rewrite the text as a casual work message. Keep it professional, but lighter and more natural than formal email language. Use moderate capitalization and punctuation, preserve the message structure, and correct spelling. Return only the final message."
            )
        case (.work, .enthusiastic):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Enthusiastic",
                summary: "Warm, polished work language with moderate excitement and occasional expressive phrasing.",
                ruleSummary: "Caps: moderate. Punctuation: moderate. Format: work message. Structure: polished with warmth.",
                instructionPrefix: "Rewrite the text as an enthusiastic work message. Keep it professional and clear, but allow mildly expressive wording and at most one exclamation point when it fits naturally. Correct spelling, capitalization, and structure without becoming overly excited. Return only the final message."
            )
        case (.email, .formal):
            let signoff = trimmedSignature.isEmpty
                ? "Close with 'Best regards,' and omit the name line if no sender name is configured."
                : "Close with 'Best regards,' on its own line followed by '\(trimmedSignature)' on the final line."
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Formal",
                summary: "Structured professional email with greeting, body paragraphs, and a 'Best regards' sign-off.",
                ruleSummary: "Caps: full. Punctuation: full. Format: email. Structure: greeting, body, sign-off.",
                instructionPrefix: "Rewrite the text as a formal email. Always format it as an email with a greeting line ending in a comma, a blank line, the email body, a blank line, and a closing. Use professional capitalization, punctuation, and grammar. \(signoff) Return only the final email."
            )
        case (.email, .casual):
            let signoff = trimmedSignature.isEmpty
                ? "Close with 'Best regards,' and omit the name line if no sender name is configured."
                : "Close with 'Best regards,' on its own line followed by '\(trimmedSignature)' on the final line."
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Casual",
                summary: "Email formatting with lighter tone, moderate punctuation, and the same basic structure.",
                ruleSummary: "Caps: moderate. Punctuation: moderate. Format: email. Structure: greeting, body, sign-off.",
                instructionPrefix: "Rewrite the text as a casual email. Always format it as an email with a greeting line ending in a comma, a blank line, the email body, a blank line, and a closing. Keep the tone friendly and natural while still correcting spelling and structure. \(signoff) Return only the final email."
            )
        case (.email, .enthusiastic):
            let signoff = trimmedSignature.isEmpty
                ? "Close with 'Best regards,' and omit the name line if no sender name is configured."
                : "Close with 'Best regards,' on its own line followed by '\(trimmedSignature)' on the final line."
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Enthusiastic",
                summary: "Email formatting with warm language, clean structure, and moderate excitement.",
                ruleSummary: "Caps: moderate. Punctuation: moderate. Format: email. Structure: greeting, body, sign-off.",
                instructionPrefix: "Rewrite the text as an enthusiastic email. Always format it as an email with a greeting line ending in a comma, a blank line, the email body, a blank line, and a closing. Keep the excitement moderate, use warm professional wording, and allow at most one exclamation point if it fits naturally. \(signoff) Return only the final email."
            )
        case (.other, .formal):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Formal",
                summary: "Useful for notes and app text that need polished capitalization, punctuation, and structure.",
                ruleSummary: "Caps: full. Punctuation: full. Format: app text. Structure: polished.",
                instructionPrefix: "Rewrite the text in a formal general-purpose style for notes, app updates, or structured writing. Use correct capitalization, punctuation, grammar, and clear structure. Do not turn it into an email unless the source clearly is one. Return only the final text."
            )
        case (.other, .casual):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Casual",
                summary: "General cleanup with moderate punctuation and a natural tone for notes or app writing.",
                ruleSummary: "Caps: relaxed. Punctuation: light. Format: app text. Structure: preserved.",
                instructionPrefix: "Rewrite the text in a casual general-purpose style for notes, Linear updates, or other app writing. Correct spelling and structure, but keep capitalization and punctuation moderately relaxed. Return only the final text."
            )
        case (.other, .enthusiastic):
            return StylePresetDefinition(
                category: self,
                preset: resolved,
                title: "Enthusiastic",
                summary: "General app writing with warmer phrasing and moderate expressiveness.",
                ruleSummary: "Caps: moderate. Punctuation: moderate. Format: app text. Structure: polished with energy.",
                instructionPrefix: "Rewrite the text in an enthusiastic general-purpose style for notes, app updates, or other writing. Keep it readable and structured, add mild warmth or expressiveness, and use at most one exclamation point when it fits. Return only the final text."
            )
        default:
            return presetDefinition(for: defaultPreset, emailSignatureName: trimmedSignature)
        }
    }
}

enum StylePreset: String, Codable, CaseIterable, Identifiable, Sendable {
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
}

struct StylePresetDefinition: Identifiable, Hashable, Sendable {
    let category: StyleCategory
    let preset: StylePreset
    let title: String
    let summary: String
    let ruleSummary: String
    let instructionPrefix: String

    var id: String {
        "\(category.rawValue)_\(preset.rawValue)"
    }
}

enum PromptOutputMode: String, Codable, Sendable {
    case text
    case jsonSchema = "json_schema"
    case jsonObjectFallback = "json_object_fallback"
}

enum LLMResultStatus: String, Codable, Sendable {
    case success
    case repaired
    case fallback
}

enum LLMValidationStatus: String, Codable, Sendable {
    case valid
    case invalid
    case notApplicable = "not_applicable"
}

struct GlossaryEntry: Codable, Hashable, Identifiable, Sendable {
    let from: String
    let to: String

    var id: String {
        "\(from.lowercased())->\(to.lowercased())"
    }
}

struct DeterministicResult: Codable, Sendable {
    let text: String
    let punctuationAdjusted: Bool
    let removedFillers: [String]
    let appliedGlossary: [GlossaryEntry]
}

enum ResolvedCorrectionKind: String, Codable, Sendable, Equatable {
    case spelledWordCollapse = "spelled_word_collapse"
    case overwrite
    case localReplacement = "local_replacement"
    case restart
    case literalSpellingPreserved = "literal_spelling_preserved"
}

enum ResolvedCorrectionDisposition: String, Codable, Sendable, Equatable {
    case applied
    case preserved
    case annotated
}

struct ResolvedSelfCorrection: Codable, Sendable, Equatable {
    let kind: ResolvedCorrectionKind
    let cue: String
    let originalText: String
    let replacementText: String
    let disposition: ResolvedCorrectionDisposition

    var summary: String {
        switch kind {
        case .spelledWordCollapse:
            return "collapsed \"\(originalText)\" to \"\(replacementText)\""
        case .overwrite, .localReplacement:
            return "replaced \"\(originalText)\" with \"\(replacementText)\" after \"\(cue)\""
        case .restart:
            return "restarted from \"\(cue)\" with \"\(replacementText)\""
        case .literalSpellingPreserved:
            return "preserved literal spelling for \"\(originalText)\""
        }
    }
}

struct ResolvedTranscript: Codable, Sendable, Equatable {
    let text: String
    let corrections: [ResolvedSelfCorrection]
    let notes: [String]
}

struct ContextPack: Codable, Sendable {
    let activeAppName: String
    let bundleID: String
    let styleCategory: StyleCategory
    let stylePreset: StylePreset
    let styleSummary: String
    let windowTitle: String?
    let focusedElementRole: String?
    let punctuationMode: String
    let fillerRemovalEnabled: Bool
    let autoDetectLists: Bool
    let outputFormat: LogicOutputFormat
    let selfCorrectionMode: SelfCorrectionMode
    let flagLowConfidenceWords: Bool
    let reasoningEffort: LogicReasoningEffort
    let glossary: [GlossaryEntry]
    let sessionMemory: [String]

    var signatureString: String {
        let glossarySignature = glossary
            .map { "\($0.from.lowercased())=>\($0.to.lowercased())" }
            .sorted()
            .joined(separator: "|")
        let sessionSignature = sessionMemory.joined(separator: "|")
        return [
            activeAppName,
            bundleID,
            styleCategory.rawValue,
            stylePreset.rawValue,
            styleSummary,
            windowTitle ?? "",
            focusedElementRole ?? "",
            punctuationMode,
            fillerRemovalEnabled ? "1" : "0",
            autoDetectLists ? "1" : "0",
            outputFormat.rawValue,
            selfCorrectionMode.rawValue,
            flagLowConfidenceWords ? "1" : "0",
            reasoningEffort.rawValue,
            glossarySignature,
            sessionSignature,
        ].joined(separator: "::")
    }
}

struct PromptProfile: Codable, Identifiable, Sendable {
    let id: String
    let version: Int
    let name: String
    let styleCategory: StyleCategory?
    var enabled: Bool
    let outputMode: PromptOutputMode
    let instructionPrefix: String
    let schema: JSONValue?
    let options: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case name
        case styleCategory = "style_category"
        case enabled
        case outputMode = "output_mode"
        case instructionPrefix = "instruction_prefix"
        case schema
        case options
    }

    var schemaObject: [String: Any]? {
        guard let schema else { return nil }
        guard case .object(let object) = schema else { return nil }
        return object.mapValues { $0.toAnyValue() }
    }

    static func automaticStyleProfile(for category: StyleCategory, settings: RefineSettings) -> PromptProfile {
        let preset = settings.preset(for: category)
        let definition = category.presetDefinition(for: preset, emailSignatureName: settings.emailSignatureName)

        return PromptProfile(
            id: "auto_style_\(category.rawValue)_\(preset.rawValue)",
            version: 1,
            name: "\(category.title) \(definition.title)",
            styleCategory: category,
            enabled: true,
            outputMode: .text,
            instructionPrefix: definition.instructionPrefix,
            schema: nil,
            options: [
                "style_category": .string(category.rawValue),
                "style_preset": .string(preset.rawValue),
                "style_summary": .string(definition.ruleSummary),
            ]
        )
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
            return
        }
        if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
            return
        }
        throw DecodingError.typeMismatch(
            JSONValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func toAnyValue() -> Any {
        switch self {
        case .object(let value):
            return value.mapValues { $0.toAnyValue() }
        case .array(let value):
            return value.map { $0.toAnyValue() }
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
    }
}

struct LLMResult: Codable, Sendable {
    let text: String?
    let json: String?
    let status: LLMResultStatus
    let validationStatus: LLMValidationStatus
    let tokens: Int
    let cachedTokens: Int
    let latencyMs: Int
    let profileID: String
    let profileVersion: Int
    let modelID: String
    let fromCache: Bool
}

struct LLMCacheKey: Hashable, Sendable {
    let profileID: String
    let profileVersion: Int
    let modelID: String
    let contextSignatureHash: String
    let transcriptHash: String
}

struct TranscriptRecord: Codable, Sendable {
    let createdAt: Date
    let rawText: String
    let deterministicText: String
    let llmText: String?
    let llmJSON: String?
    let llmStatus: LLMResultStatus?
    let validationStatus: LLMValidationStatus?
    let profileID: String?
    let profileVersion: Int?
    let modelID: String?
    let tokens: Int?
    let cachedTokens: Int?
    let latencyMs: Int?
    let activeAppName: String
    let bundleID: String
    let styleCategory: StyleCategory
}

struct ActionItemsPayload: Codable, Sendable {
    struct Item: Codable, Sendable {
        let task: String
        let owner: String?
        let dueDate: String?
        let evidenceQuote: String?

        enum CodingKeys: String, CodingKey {
            case task
            case owner
            case dueDate = "due_date"
            case evidenceQuote = "evidence_quote"
        }
    }

    let items: [Item]
}

struct RefineSettings: Codable, Sendable {
    var workEnabled: Bool = false
    var emailEnabled: Bool = false
    var personalEnabled: Bool = false
    var otherEnabled: Bool = false
    private var workPresetStorage: StylePreset = .formal
    private var emailPresetStorage: StylePreset = .formal
    private var personalPresetStorage: StylePreset = .casual
    private var otherPresetStorage: StylePreset = .casual
    var previewBeforeInsert: Bool = true
    var autoPasteAfterInsert: Bool = false
    var sessionMemory: [String] = []
    var glossary: [GlossaryEntry] = []
    var emailSignatureName: String = ""

    init(
        workEnabled: Bool = false,
        emailEnabled: Bool = false,
        personalEnabled: Bool = false,
        otherEnabled: Bool = false,
        workPreset: StylePreset = .formal,
        emailPreset: StylePreset = .formal,
        personalPreset: StylePreset = .casual,
        otherPreset: StylePreset = .casual,
        previewBeforeInsert: Bool = true,
        autoPasteAfterInsert: Bool = false,
        sessionMemory: [String] = [],
        glossary: [GlossaryEntry] = [],
        emailSignatureName: String = ""
    ) {
        self.workEnabled = workEnabled
        self.emailEnabled = emailEnabled
        self.personalEnabled = personalEnabled
        self.otherEnabled = otherEnabled
        self.workPresetStorage = StyleCategory.work.resolvedPreset(workPreset)
        self.emailPresetStorage = StyleCategory.email.resolvedPreset(emailPreset)
        self.personalPresetStorage = StyleCategory.personal.resolvedPreset(personalPreset)
        self.otherPresetStorage = StyleCategory.other.resolvedPreset(otherPreset)
        self.previewBeforeInsert = previewBeforeInsert
        self.autoPasteAfterInsert = autoPasteAfterInsert
        self.sessionMemory = sessionMemory
        self.glossary = glossary
        self.emailSignatureName = emailSignatureName
    }

    enum CodingKeys: String, CodingKey {
        case workEnabled
        case emailEnabled
        case personalEnabled
        case otherEnabled
        case workPresetStorage = "workPreset"
        case emailPresetStorage = "emailPreset"
        case personalPresetStorage = "personalPreset"
        case otherPresetStorage = "otherPreset"
        case previewBeforeInsert
        case autoPasteAfterInsert
        case sessionMemory
        case glossary
        case emailSignatureName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workEnabled = try container.decodeIfPresent(Bool.self, forKey: .workEnabled) ?? false
        emailEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailEnabled) ?? false
        personalEnabled = try container.decodeIfPresent(Bool.self, forKey: .personalEnabled) ?? false
        otherEnabled = try container.decodeIfPresent(Bool.self, forKey: .otherEnabled) ?? false
        workPresetStorage = StyleCategory.work.resolvedPreset(try container.decodeIfPresent(StylePreset.self, forKey: .workPresetStorage) ?? .formal)
        emailPresetStorage = StyleCategory.email.resolvedPreset(try container.decodeIfPresent(StylePreset.self, forKey: .emailPresetStorage) ?? .formal)
        personalPresetStorage = StyleCategory.personal.resolvedPreset(try container.decodeIfPresent(StylePreset.self, forKey: .personalPresetStorage) ?? .casual)
        otherPresetStorage = StyleCategory.other.resolvedPreset(try container.decodeIfPresent(StylePreset.self, forKey: .otherPresetStorage) ?? .casual)
        previewBeforeInsert = try container.decodeIfPresent(Bool.self, forKey: .previewBeforeInsert) ?? true
        autoPasteAfterInsert = try container.decodeIfPresent(Bool.self, forKey: .autoPasteAfterInsert) ?? false
        sessionMemory = try container.decodeIfPresent([String].self, forKey: .sessionMemory) ?? []
        glossary = try container.decodeIfPresent([GlossaryEntry].self, forKey: .glossary) ?? []
        emailSignatureName = try container.decodeIfPresent(String.self, forKey: .emailSignatureName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workEnabled, forKey: .workEnabled)
        try container.encode(emailEnabled, forKey: .emailEnabled)
        try container.encode(personalEnabled, forKey: .personalEnabled)
        try container.encode(otherEnabled, forKey: .otherEnabled)
        try container.encode(preset(for: .work), forKey: .workPresetStorage)
        try container.encode(preset(for: .email), forKey: .emailPresetStorage)
        try container.encode(preset(for: .personal), forKey: .personalPresetStorage)
        try container.encode(preset(for: .other), forKey: .otherPresetStorage)
        try container.encode(previewBeforeInsert, forKey: .previewBeforeInsert)
        try container.encode(autoPasteAfterInsert, forKey: .autoPasteAfterInsert)
        try container.encode(sessionMemory, forKey: .sessionMemory)
        try container.encode(glossary, forKey: .glossary)
        try container.encode(emailSignatureName, forKey: .emailSignatureName)
    }

    func isEnabled(for category: StyleCategory) -> Bool {
        switch category {
        case .work:
            return workEnabled
        case .email:
            return emailEnabled
        case .personal:
            return personalEnabled
        case .other:
            return otherEnabled
        }
    }

    func preset(for category: StyleCategory) -> StylePreset {
        switch category {
        case .work:
            return StyleCategory.work.resolvedPreset(workPresetStorage)
        case .email:
            return StyleCategory.email.resolvedPreset(emailPresetStorage)
        case .personal:
            return StyleCategory.personal.resolvedPreset(personalPresetStorage)
        case .other:
            return StyleCategory.other.resolvedPreset(otherPresetStorage)
        }
    }

    mutating func setEnabled(_ enabled: Bool, for category: StyleCategory) {
        switch category {
        case .work:
            workEnabled = enabled
        case .email:
            emailEnabled = enabled
        case .personal:
            personalEnabled = enabled
        case .other:
            otherEnabled = enabled
        }
    }

    mutating func setPreset(_ preset: StylePreset, for category: StyleCategory) {
        let resolved = category.resolvedPreset(preset)
        switch category {
        case .work:
            workPresetStorage = resolved
        case .email:
            emailPresetStorage = resolved
        case .personal:
            personalPresetStorage = resolved
        case .other:
            otherPresetStorage = resolved
        }
    }
}

struct ActiveAppContext: Sendable {
    let appName: String
    let bundleID: String
    let processIdentifier: Int32?
    let styleCategory: StyleCategory
    let windowTitle: String?
    let focusedElementRole: String?

    var insertionTarget: InsertionTarget? {
        guard isEditableTextInput else { return nil }
        return InsertionTarget(
            appName: appName,
            bundleID: bundleID,
            processIdentifier: processIdentifier
        )
    }

    var isEditableTextInput: Bool {
        guard let focusedElementRole else { return false }
        let normalized = focusedElementRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "axtextarea",
            "axtextfield",
            "axsearchfield",
            "axcombobox",
            "axtextinput",
            "axwebarea",
        ].contains(normalized)
    }
}

struct InsertionTarget: Codable, Sendable, Equatable {
    let appName: String
    let bundleID: String
    let processIdentifier: Int32?
}

protocol DeterministicFormatterServiceProtocol {
    func format(text: String, settings: LogicSettings, glossary: [GlossaryEntry]) -> DeterministicResult
}

@MainActor
protocol LLMFormatterServiceProtocol {
    func refine(
        deterministicText: String,
        contextPack: ContextPack,
        profile: PromptProfile,
        mode: LogicMode,
        modelID: String,
        apiKey: String?
    ) async throws -> LLMResult
}

protocol InsertionServiceProtocol {
    func insert(text: String, autoPaste: Bool, target: InsertionTarget?) throws
}
