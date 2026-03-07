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

struct ContextPack: Codable, Sendable {
    let activeAppName: String
    let bundleID: String
    let styleCategory: StyleCategory
    let windowTitle: String?
    let focusedElementRole: String?
    let punctuationMode: String
    let fillerRemovalEnabled: Bool
    let autoDetectLists: Bool
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
            windowTitle ?? "",
            focusedElementRole ?? "",
            punctuationMode,
            fillerRemovalEnabled ? "1" : "0",
            autoDetectLists ? "1" : "0",
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
    var previewBeforeInsert: Bool = true
    var autoPasteAfterInsert: Bool = false
    var sessionMemory: [String] = []
    var glossary: [GlossaryEntry] = []

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
}

struct ActiveAppContext: Sendable {
    let appName: String
    let bundleID: String
    let styleCategory: StyleCategory
    let windowTitle: String?
    let focusedElementRole: String?
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
    func insert(text: String, autoPaste: Bool) throws
}
