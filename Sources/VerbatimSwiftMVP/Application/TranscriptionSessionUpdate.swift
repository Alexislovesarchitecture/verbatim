import Foundation

struct TranscriptionSessionRequest: Sendable {
    let mode: TranscriptionMode
    let localModel: LocalTranscriptionModel
    let options: TranscriptionOptions
    let interactionSettings: InteractionSettings
    let recordingSessionContext: RecordingSessionContext?
}

enum TranscriptionSessionUpdate: Sendable {
    case session(TranscriptionSession)
    case transcript(event: TranscriptEvent, snapshot: TranscriptMergeSnapshot)
    case completion(RecordingCompletionResult)
}
