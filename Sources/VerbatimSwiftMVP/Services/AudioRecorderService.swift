import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case fileCreationFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable it in System Settings > Privacy & Security."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No active recording to stop."
        case .fileCreationFailed:
            return "Could not prepare a recording file."
        }
    }
}

@MainActor
@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class AudioRecorderService {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var isRecording = false

    func startRecording() async throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let permitted = await requestMicrophonePermission()
        guard permitted else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let fileName = "verbatim_recording_\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        cleanup(fileURL)

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            outputURL = fileURL
        } catch {
            throw AudioRecorderError.fileCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            do {
                try self?.audioFile?.write(from: buffer)
            } catch {
                // Ignore write failures at tap level; surface any stop/transcription issues later.
            }
        }

        try engine.start()
        isRecording = true
    }

    func stopRecording() async throws -> URL? {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        let recordedURL = outputURL
        outputURL = nil
        audioFile = nil
        return recordedURL
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func cleanup(_ url: URL?) {
        guard let url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
