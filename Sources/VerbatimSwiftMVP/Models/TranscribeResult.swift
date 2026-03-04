import Foundation

struct TranscriptSegment: Codable, Hashable {
    let start: TimeInterval?
    let end: TimeInterval?
    let speaker: String?
    let text: String
}

struct TokenLogprob: Codable, Hashable {
    let token: String
    let logprob: Double
    let start: TimeInterval?
    let end: TimeInterval?
}

struct LowConfidenceSpan: Codable, Hashable {
    let start: TimeInterval?
    let end: TimeInterval?
    let text: String
    let averageLogprob: Double
}

struct Transcript: Codable {
    let rawText: String
    let segments: [TranscriptSegment]
    let tokenLogprobs: [TokenLogprob]?
    let lowConfidenceSpans: [LowConfidenceSpan]
    let modelID: String
    let responseFormat: String
}

struct FormattedOutput: Codable {
    let clean_text: String
    let format: String
    let bullets: [String]
    let self_corrections: [String]
    let low_confidence_spans: [String]
    let notes: [String]
}

struct LogicSettings: Codable {
    var removeFillerWords: Bool = true
    var selfCorrectionMode: SelfCorrectionMode = .keepFinal
    var autoDetectLists: Bool = true
    var outputFormat: LogicOutputFormat = .auto
    var flagLowConfidenceWords: Bool = true
    var reasoningEffort: LogicReasoningEffort = .modelDefault

    private enum CodingKeys: String, CodingKey {
        case removeFillerWords
        case selfCorrectionMode
        case autoDetectLists
        case outputFormat
        case flagLowConfidenceWords
        case reasoningEffort
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        removeFillerWords = try container.decodeIfPresent(Bool.self, forKey: .removeFillerWords) ?? true
        selfCorrectionMode = try container.decodeIfPresent(SelfCorrectionMode.self, forKey: .selfCorrectionMode) ?? .keepFinal
        autoDetectLists = try container.decodeIfPresent(Bool.self, forKey: .autoDetectLists) ?? true
        outputFormat = try container.decodeIfPresent(LogicOutputFormat.self, forKey: .outputFormat) ?? .auto
        flagLowConfidenceWords = try container.decodeIfPresent(Bool.self, forKey: .flagLowConfidenceWords) ?? true
        reasoningEffort = try container.decodeIfPresent(LogicReasoningEffort.self, forKey: .reasoningEffort) ?? .modelDefault
    }
}

struct TranscriptionRequestOptions: Equatable {
    let modelID: String
    var responseFormat: String
    var includeLogprobs: Bool
    var prompt: String?
    var stream: Bool
    var timestampGranularities: [String]
    var diarizationEnabled: Bool
    var languageHint: String?
    var chunkingStrategy: String?
    var knownSpeakerNames: [String]
    var knownSpeakerReferences: [String]

    init(
        modelID: String,
        responseFormat: String = "json",
        includeLogprobs: Bool = false,
        prompt: String? = nil,
        stream: Bool = false,
        timestampGranularities: [String] = [],
        diarizationEnabled: Bool = false,
        languageHint: String? = nil,
        chunkingStrategy: String? = nil,
        knownSpeakerNames: [String] = [],
        knownSpeakerReferences: [String] = []
    ) {
        self.modelID = modelID
        self.responseFormat = responseFormat
        self.includeLogprobs = includeLogprobs
        self.prompt = prompt
        self.stream = stream
        self.timestampGranularities = timestampGranularities
        self.diarizationEnabled = diarizationEnabled
        self.languageHint = languageHint
        self.chunkingStrategy = chunkingStrategy
        self.knownSpeakerNames = knownSpeakerNames
        self.knownSpeakerReferences = knownSpeakerReferences
    }
}

struct ModelCapabilityConstraintContext {
    let responseFormat: String
    let includeLogprobs: Bool
    let prompt: String?
    let stream: Bool
    let timestampGranularities: [String]
    let diarizationEnabled: Bool
    let chunkingStrategy: String?

    init(from options: TranscriptionRequestOptions, model: ModelRegistryEntry, shouldUseChunkingForLongAudio: Bool) {
        if model.allowedResponseFormats.contains(options.responseFormat) {
            responseFormat = options.responseFormat
        } else {
            responseFormat = model.allowedResponseFormats.first ?? "json"
        }

        includeLogprobs = model.supportsLogprobs ? options.includeLogprobs : false
        let trimmedPrompt = options.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt = model.supportsPrompt ? ((trimmedPrompt?.isEmpty == false) ? trimmedPrompt : nil) : nil
        stream = model.supportsStreaming ? options.stream : false

        if model.supportsTimestamps && responseFormat == "verbose_json" {
            timestampGranularities = options.timestampGranularities
        } else {
            timestampGranularities = []
        }

        if model.supportsDiarization {
            diarizationEnabled = options.diarizationEnabled
        } else {
            diarizationEnabled = false
        }

        if model.requiresChunkingStrategyForLongAudio && shouldUseChunkingForLongAudio {
            chunkingStrategy = "auto"
        } else if let explicitStrategy = options.chunkingStrategy?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !explicitStrategy.isEmpty {
            chunkingStrategy = explicitStrategy
        } else {
            chunkingStrategy = nil
        }
    }
}
