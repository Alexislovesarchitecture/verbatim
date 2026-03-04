import Foundation

enum ModelRole: String, Codable {
    case transcription
    case logic
}

enum EngineMode: String, Codable {
    case remote
    case local
}

enum EndpointKind: String, Codable {
    case audioTranscriptions
    case responses
    case ollamaLocal
}

struct ModelRegistryEntry: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    let role: ModelRole
    let mode: EngineMode
    let endpoint: EndpointKind
    let isAdvanced: Bool
    let supportsDiarization: Bool
    let supportsTimestamps: Bool
    let supportsLogprobs: Bool
    let supportsStreaming: Bool
    let supportsPrompt: Bool
    let supportsStructuredOutputs: Bool
    let allowedResponseFormats: [String]
    let requiresChunkingStrategyForLongAudio: Bool
    let notes: String?
    let isEnabled: Bool
    let reasoningEffortDefault: String?
}

struct ModelAvailabilityRow: Identifiable {
    let entry: ModelRegistryEntry
    let isAvailable: Bool

    var id: String { entry.id }
    var title: String { entry.displayName }
    var subtitle: String {
        if entry.isEnabled == false {
            return entry.notes ?? ""
        }
        return entry.notes ?? ""
    }
}

enum ModelRegistry {
    static let minimumRemoteUploadBytes: Int = 25 * 1024 * 1024
    static let supportedAudioExtensions: Set<String> = ["mp3", "mp4", "mpeg", "mpga", "m4a", "wav", "webm", "flac", "ogg"]
    static let diarizationLogprobThreshold: Double = -1.5

    static let entries: [ModelRegistryEntry] = [
        ModelRegistryEntry(
            id: "whisper-1",
            displayName: "Whisper (legacy)",
            role: .transcription,
            mode: .remote,
            endpoint: .audioTranscriptions,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: true,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: false,
            allowedResponseFormats: ["json", "text", "srt", "vtt", "verbose_json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Legacy Whisper-powered transcriber",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-4o-mini-transcribe",
            displayName: "GPT-4o mini Transcribe",
            role: .transcription,
            mode: .remote,
            endpoint: .audioTranscriptions,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: true,
            supportsStreaming: true,
            supportsPrompt: true,
            supportsStructuredOutputs: false,
            allowedResponseFormats: ["json", "text"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Fast transcribe family",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-4o-transcribe",
            displayName: "GPT-4o Transcribe",
            role: .transcription,
            mode: .remote,
            endpoint: .audioTranscriptions,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: true,
            supportsStreaming: true,
            supportsPrompt: true,
            supportsStructuredOutputs: false,
            allowedResponseFormats: ["json", "text"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Higher quality transcribe",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-4o-transcribe-diarize",
            displayName: "GPT-4o Transcribe Diarize",
            role: .transcription,
            mode: .remote,
            endpoint: .audioTranscriptions,
            isAdvanced: false,
            supportsDiarization: true,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: true,
            supportsPrompt: false,
            supportsStructuredOutputs: false,
            allowedResponseFormats: ["json", "text", "diarized_json"],
            requiresChunkingStrategyForLongAudio: true,
            notes: "Use diarized_json for speaker labels",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-4o-mini-transcribe-2025-12-15",
            displayName: "GPT-4o mini Transcribe (dated snapshot)",
            role: .transcription,
            mode: .remote,
            endpoint: .audioTranscriptions,
            isAdvanced: true,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: true,
            supportsStreaming: true,
            supportsPrompt: true,
            supportsStructuredOutputs: false,
            allowedResponseFormats: ["json", "text"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Advanced snapshot",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-5-mini",
            displayName: "GPT-5-mini",
            role: .logic,
            mode: .remote,
            endpoint: .responses,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Default logic model",
            isEnabled: true,
            reasoningEffortDefault: "minimal"
        ),
        ModelRegistryEntry(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            role: .logic,
            mode: .remote,
            endpoint: .responses,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Higher quality logic model",
            isEnabled: true,
            reasoningEffortDefault: "low"
        ),
        ModelRegistryEntry(
            id: "gpt-5-nano",
            displayName: "GPT-5-nano",
            role: .logic,
            mode: .remote,
            endpoint: .responses,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Ultra-fast remote logic model",
            isEnabled: true,
            reasoningEffortDefault: "minimal"
        ),
        ModelRegistryEntry(
            id: "gpt-4o-mini",
            displayName: "GPT-4o Mini",
            role: .logic,
            mode: .remote,
            endpoint: .responses,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Alternative logic-capable model",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-4o",
            displayName: "GPT-4o",
            role: .logic,
            mode: .remote,
            endpoint: .responses,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Remote logic model",
            isEnabled: true,
            reasoningEffortDefault: nil
        ),
        ModelRegistryEntry(
            id: "gpt-oss-20b",
            displayName: "Local gpt-oss-20b",
            role: .logic,
            mode: .local,
            endpoint: .ollamaLocal,
            isAdvanced: false,
            supportsDiarization: false,
            supportsTimestamps: false,
            supportsLogprobs: false,
            supportsStreaming: false,
            supportsPrompt: true,
            supportsStructuredOutputs: true,
            allowedResponseFormats: ["json"],
            requiresChunkingStrategyForLongAudio: false,
            notes: "Requires local Ollama runtime",
            isEnabled: true,
            reasoningEffortDefault: nil
        )
    ]

    static func entries(for role: ModelRole, mode: EngineMode, includeAdvanced: Bool) -> [ModelRegistryEntry] {
        entries.filter { entry in
            entry.role == role && entry.mode == mode && (includeAdvanced || !entry.isAdvanced)
        }
        .sorted {
            if $0.isEnabled != $1.isEnabled {
                return $0.isEnabled && !$1.isEnabled
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func entry(for id: String) -> ModelRegistryEntry? {
        entries.first { $0.id == id }
    }

    static func responseFormats(for modelID: String) -> [String] {
        entry(for: modelID)?.allowedResponseFormats ?? ["json"]
    }
}
