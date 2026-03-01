import Foundation

protocol TranscriptionEngineProtocol {
    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String
}

enum TranscriptionEngineError: Error {
    case missingAPIKey
    case missingExecutable
    case missingModel
    case executableNotRunnable
    case requestFailed(String)
    case invalidResponse
    case missingServerBinary
    case missingServerEndpoint
    case serverTimeout
    case emptyTranscript
}
