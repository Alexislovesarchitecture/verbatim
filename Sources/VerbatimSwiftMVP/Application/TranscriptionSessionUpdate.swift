import Foundation

struct TranscriptionSessionRequest: Sendable {
    let mode: TranscriptionMode
    let localModel: LocalTranscriptionModel
    let options: TranscriptionOptions
}

enum TranscriptionSessionUpdate: Sendable {
    case session(TranscriptionSession)
    case transcript(event: TranscriptEvent, snapshot: TranscriptMergeSnapshot)
}
