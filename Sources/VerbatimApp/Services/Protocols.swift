import Foundation

struct CapturedAudio {
    var fileURL: URL
    var durationSeconds: Double
}

struct TranscriptionRequest {
    var audioURL: URL
    var languageCode: String
    var customTerms: [String]
}

struct TranscriptionResult {
    var rawText: String
    var engine: TranscriptOrigin
}

protocol AudioCaptureServicing {
    func startRecording() throws
    func stopRecording() async throws -> CapturedAudio
    func cancelRecording()
    var isRecording: Bool { get }
}

protocol TranscriptionServicing {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}

protocol TextInsertionServicing {
    func insertOrFallback(_ text: String) -> InsertOutcome
    func pasteLastCapture(_ text: String)
    func focusedAppName() -> String
}

protocol SoundServicing {
    func playStart()
    func playStop()
}
