import Foundation

struct TranscriptionSession: Identifiable, Codable, Hashable, Sendable {
    enum Stage: String, Codable, Sendable {
        case recording
        case transcribing
        case completed
        case failed
    }

    var id: UUID
    var engineID: String
    var startedAt: Date
    var endedAt: Date?
    var stage: Stage
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        engineID: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        stage: Stage,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.engineID = engineID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stage = stage
        self.errorMessage = errorMessage
    }
}

struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var start: TimeInterval?
    var end: TimeInterval?
    var speaker: String?
    var text: String

    init(
        id: String = UUID().uuidString,
        start: TimeInterval?,
        end: TimeInterval?,
        speaker: String?,
        text: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.speaker = speaker
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case speaker
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        start = try container.decodeIfPresent(TimeInterval.self, forKey: .start)
        end = try container.decodeIfPresent(TimeInterval.self, forKey: .end)
        speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

struct TokenLogprob: Codable, Hashable, Sendable {
    let token: String
    let logprob: Double
    let start: TimeInterval?
    let end: TimeInterval?
}

struct LowConfidenceSpan: Codable, Hashable, Sendable {
    let start: TimeInterval?
    let end: TimeInterval?
    let text: String
    let averageLogprob: Double
}

struct Transcript: Codable, Equatable, Sendable {
    let rawText: String
    let segments: [TranscriptSegment]
    let tokenLogprobs: [TokenLogprob]?
    let lowConfidenceSpans: [LowConfidenceSpan]
    let modelID: String
    let responseFormat: String

    static func empty(modelID: String, responseFormat: String = "text") -> Transcript {
        Transcript(
            rawText: "",
            segments: [],
            tokenLogprobs: nil,
            lowConfidenceSpans: [],
            modelID: modelID,
            responseFormat: responseFormat
        )
    }
}

struct TranscriptDelta: Codable, Hashable, Sendable {
    let id: String
    let text: String

    init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

enum TranscriptEvent: Equatable, Sendable {
    case delta(TranscriptDelta)
    case segment(TranscriptSegment)
    case done(Transcript)
}

struct AudioPCM16Frame: Equatable, Sendable {
    let sequenceNumber: UInt64
    let sampleRate: Double
    let channelCount: Int
    let samples: Data

    var sampleCount: Int {
        samples.count / MemoryLayout<Int16>.size
    }
}

enum TranscriptionSource {
    case audioFile(URL)
    case recordingArtifact(audioURL: URL, frames: AsyncStream<AudioPCM16Frame>)

    var audioURL: URL? {
        switch self {
        case .audioFile(let url):
            return url
        case .recordingArtifact(let audioURL, _):
            return audioURL
        }
    }

    var frames: AsyncStream<AudioPCM16Frame>? {
        switch self {
        case .audioFile:
            return nil
        case .recordingArtifact(_, let frames):
            return frames
        }
    }
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

struct TranscriptionOptions: Equatable, Sendable {
    let modelID: String
    var apiKey: String?
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
    var localEngineMode: LocalTranscriptionEngineMode?

    init(
        modelID: String,
        apiKey: String? = nil,
        responseFormat: String = "json",
        includeLogprobs: Bool = false,
        prompt: String? = nil,
        stream: Bool = false,
        timestampGranularities: [String] = [],
        diarizationEnabled: Bool = false,
        languageHint: String? = nil,
        chunkingStrategy: String? = nil,
        knownSpeakerNames: [String] = [],
        knownSpeakerReferences: [String] = [],
        localEngineMode: LocalTranscriptionEngineMode? = nil
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
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
        self.localEngineMode = localEngineMode
    }
}

typealias TranscriptionRequestOptions = TranscriptionOptions

struct EngineCapabilities: Equatable, Sendable {
    var supportsStreamingEvents: Bool
    var supportsLiveAudioFrames: Bool
    var supportsDiarization: Bool
    var supportsLogprobs: Bool
    var supportsTimestamps: Bool
    var supportsPrompt: Bool

    static let none = EngineCapabilities(
        supportsStreamingEvents: false,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: false,
        supportsPrompt: false
    )
}

enum TranscriptionEngineError: LocalizedError {
    case missingAudioSource

    var errorDescription: String? {
        switch self {
        case .missingAudioSource:
            return "A transcription engine requires an audio file source."
        }
    }
}

protocol TranscriptionEngine: Sendable {
    var engineID: String { get }
    var capabilities: EngineCapabilities { get }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript
    func transcribeEvents(source: TranscriptionSource, options: TranscriptionOptions) -> AsyncThrowingStream<TranscriptEvent, Error>
}

extension TranscriptionEngine {
    func transcribeEvents(source: TranscriptionSource, options: TranscriptionOptions) -> AsyncThrowingStream<TranscriptEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let audioURL = source.audioURL else {
                        throw TranscriptionEngineError.missingAudioSource
                    }
                    let transcript = try await transcribeBatch(audioURL: audioURL, options: options)
                    continuation.yield(.done(transcript))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
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

    init(from options: TranscriptionOptions, model: ModelRegistryEntry, shouldUseChunkingForLongAudio: Bool) {
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
