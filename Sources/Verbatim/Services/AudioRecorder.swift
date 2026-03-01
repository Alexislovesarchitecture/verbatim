import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var levelHandler: ((Float) -> Void)?

    func start(levelHandler: @escaping (Float) -> Void) throws {
        stopEngineIfNeeded()
        self.levelHandler = levelHandler

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        currentURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                print("Write buffer failed: \(error)")
            }
            self.levelHandler?(Self.rms(buffer: buffer))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> URL? {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        stopEngineIfNeeded()
        let url = currentURL
        audioFile = nil
        currentURL = nil
        return url
    }

    func cancel() {
        let url = stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stopEngineIfNeeded() {
        if engine.isRunning {
            engine.stop()
            engine.reset()
        }
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        return min(max(rms * 8, 0), 1)
    }
}
