import Foundation
import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var levelHandler: ((Float) -> Void)?
    private var maxLevelObserved: Float = 0

    func start(levelHandler: @escaping (Float) -> Void) throws {
        maxLevelObserved = 0
        stopEngineIfNeeded()
        self.levelHandler = levelHandler

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbatim-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

            let level = Self.rms(buffer: buffer)
            self.maxLevelObserved = max(self.maxLevelObserved, level)
            self.levelHandler?(level)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> URL? {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        stopEngineIfNeeded()
        let url = currentURL
        currentURL = nil
        audioFile = nil
        return url
    }

    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func wasSilentThreshold(_ threshold: Float) -> Bool {
        maxLevelObserved < threshold
    }

    private func stopEngineIfNeeded() {
        if engine.isRunning {
            engine.stop()
            engine.reset()
        }
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?.pointee else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var energy: Float = 0
        for index in 0..<frameLength {
            energy += channelData[index] * channelData[index]
        }
        let level = sqrt(energy / Float(frameLength))
        return min(max(level * 8, 0), 1)
    }
}
