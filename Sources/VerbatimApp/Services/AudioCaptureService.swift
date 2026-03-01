import Foundation
import AVFoundation

final class AudioCaptureService: NSObject, AudioCaptureServicing, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var startDate: Date?

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    func startRecording() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        recorder?.prepareToRecord()
        recorder?.record()
        fileURL = url
        startDate = Date()
    }

    func stopRecording() async throws -> CapturedAudio {
        guard let recorder, let fileURL else {
            throw NSError(domain: "Verbatim.AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording was not active."])
        }

        recorder.stop()
        self.recorder = nil
        let duration = max(0.1, Date().timeIntervalSince(startDate ?? .now))
        self.startDate = nil
        self.fileURL = nil
        return CapturedAudio(fileURL: fileURL, durationSeconds: duration)
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        startDate = nil
    }
}
