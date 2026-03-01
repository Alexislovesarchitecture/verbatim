import Foundation

enum CaptureCoordinatorState {
    case idle
    case recording
    case locked
    case transcribing
    case inserting
    case clipboardReady
    case failed
}

protocol CaptureCoordinatorProtocol {
    func startListening()
    func stopListening()
    func lockListening()
    func unlockListening()
    func ingest(rawAudioURL: URL, wasLocked: Bool) async
    func copyLastCapture()
    func getLastCaptureText() -> String?
}
