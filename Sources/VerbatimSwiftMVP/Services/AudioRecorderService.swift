@preconcurrency import AVFoundation
import Foundation

struct AudioRecordingArtifact {
    let audioFileURL: URL
    let frameStream: AsyncStream<AudioPCM16Frame>
}

@MainActor
protocol AudioRecorderServiceProtocol: AnyObject {
    func startRecording() async throws -> AsyncStream<AudioPCM16Frame>
    func stopRecording() async throws -> AudioRecordingArtifact?
    func discardRecordingArtifact(_ artifact: AudioRecordingArtifact?)
}

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case alreadyRecording
    case notRecording
    case fileCreationFailed
    case conversionSetupFailed

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
        case .conversionSetupFailed:
            return "Could not configure live audio conversion."
        }
    }
}
@MainActor
final class AudioRecorderService: AudioRecorderServiceProtocol {
    private static let liveSampleRate: Double = 16_000
    private static let liveChannelCount: AVAudioChannelCount = 1

    // The engine tap executes off the main actor, so keep audio IO state behind a lock
    // instead of bouncing every buffer through the view model/UI actor.
    private final class RecordingIOState: @unchecked Sendable {
        private let lock = NSLock()
        private var audioFile: AVAudioFile?
        private var converter: AVAudioConverter?
        private var convertedFormat: AVAudioFormat?
        private var continuation: AsyncStream<AudioPCM16Frame>.Continuation?
        private var sequenceNumber: UInt64 = 0

        func configure(
            audioFile: AVAudioFile,
            converter: AVAudioConverter,
            convertedFormat: AVAudioFormat,
            continuation: AsyncStream<AudioPCM16Frame>.Continuation
        ) {
            lock.lock()
            self.audioFile = audioFile
            self.converter = converter
            self.convertedFormat = convertedFormat
            self.continuation = continuation
            sequenceNumber = 0
            lock.unlock()
        }

        func finishAndReset() {
            lock.lock()
            let activeContinuation = continuation
            audioFile = nil
            converter = nil
            convertedFormat = nil
            continuation = nil
            sequenceNumber = 0
            lock.unlock()

            activeContinuation?.finish()
        }

        func writeAndEmit(buffer: AVAudioPCMBuffer) {
            lock.lock()
            defer { lock.unlock() }

            do {
                try audioFile?.write(from: buffer)
            } catch {
                // Ignore write failures at tap level; surface stop/transcription issues later.
            }

            guard let converter, let convertedFormat else {
                return
            }

            let targetFrameCapacity = AVAudioFrameCount(
                max(1, Int(Double(buffer.frameLength) * convertedFormat.sampleRate / buffer.format.sampleRate) + 64)
            )
            guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: convertedFormat, frameCapacity: targetFrameCapacity) else {
                return
            }

            do {
                try converter.convert(to: targetBuffer, from: buffer)
            } catch {
                return
            }
            guard targetBuffer.frameLength > 0 else { return }
            guard let pcm = targetBuffer.int16ChannelData else { return }

            let byteCount = Int(targetBuffer.frameLength) * Int(targetBuffer.format.channelCount) * MemoryLayout<Int16>.stride
            let frameData = Data(bytes: pcm[0], count: byteCount)

            sequenceNumber += 1
            continuation?.yield(
                AudioPCM16Frame(
                    sequenceNumber: sequenceNumber,
                    sampleRate: convertedFormat.sampleRate,
                    channelCount: Int(convertedFormat.channelCount),
                    samples: frameData
                )
            )
        }
    }

    private let engine = AVAudioEngine()
    private let recordingIOState = RecordingIOState()
    private var outputURL: URL?
    private var liveFrameStream: AsyncStream<AudioPCM16Frame>?
    private var tapInstalled = false
    private var isRecording = false

    deinit {}

    func startRecording() async throws -> AsyncStream<AudioPCM16Frame> {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let permitted = await requestMicrophonePermission()
        guard permitted else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let sourceFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.liveSampleRate,
            channels: Self.liveChannelCount,
            interleaved: true
        ) else {
            throw AudioRecorderError.conversionSetupFailed
        }

        let fileName = "verbatim_recording_\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        cleanup(fileURL)

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioRecorderError.conversionSetupFailed
        }

        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: sourceFormat.settings)
            let (stream, continuation) = makeLiveFrameStream()

            recordingIOState.configure(
                audioFile: audioFile,
                converter: converter,
                convertedFormat: targetFormat,
                continuation: continuation
            )
            outputURL = fileURL
            liveFrameStream = stream
        } catch {
            throw AudioRecorderError.fileCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [recordingIOState] buffer, _ in
            recordingIOState.writeAndEmit(buffer: buffer)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            if let liveFrameStream {
                return liveFrameStream
            }
            throw AudioRecorderError.fileCreationFailed
        } catch {
            if tapInstalled {
                inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            engine.reset()
            recordingIOState.finishAndReset()
            liveFrameStream = nil
            cleanup(outputURL)
            outputURL = nil
            throw error
        }
    }

    func stopRecording() async throws -> AudioRecordingArtifact? {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }

        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        engine.stop()
        engine.reset()
        isRecording = false

        let recordedURL = outputURL
        let stream = liveFrameStream

        recordingIOState.finishAndReset()
        liveFrameStream = nil
        outputURL = nil

        guard let recordedURL, let stream else {
            return nil
        }
        return AudioRecordingArtifact(audioFileURL: recordedURL, frameStream: stream)
    }

    func discardRecordingArtifact(_ artifact: AudioRecordingArtifact?) {
        guard let artifact else { return }
        cleanup(artifact.audioFileURL)
    }

    private func makeLiveFrameStream() -> (
        stream: AsyncStream<AudioPCM16Frame>,
        continuation: AsyncStream<AudioPCM16Frame>.Continuation
    ) {
        var continuationRef: AsyncStream<AudioPCM16Frame>.Continuation?
        let stream = AsyncStream<AudioPCM16Frame>(bufferingPolicy: .bufferingNewest(128)) { continuation in
            continuationRef = continuation
        }
        guard let continuationRef else {
            preconditionFailure("AsyncStream continuation was not initialized.")
        }
        return (stream, continuationRef)
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
