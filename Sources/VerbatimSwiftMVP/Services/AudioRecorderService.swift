@preconcurrency import AVFoundation
import Foundation
import OSLog

private let audioRecorderLogger = Logger(subsystem: "VerbatimSwiftMVP", category: "AudioRecorder")

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
    case recordingWriteFailed(String)
    case emptyRecordingArtifact

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
        case .recordingWriteFailed(let message):
            return "Could not write recorded audio: \(message)"
        case .emptyRecordingArtifact:
            return "Recording finished without any usable audio. Try holding the key slightly longer and recording again."
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
        struct Snapshot {
            let didWriteAudio: Bool
            let writeErrorDescription: String?
        }

        private let lock = NSLock()
        private var audioFile: AVAudioFile?
        private var converter: AVAudioConverter?
        private var processingFormat: AVAudioFormat?
        private var continuation: AsyncStream<AudioPCM16Frame>.Continuation?
        private var sequenceNumber: UInt64 = 0
        private var didLogConversionFailure = false
        private var didLogWriteFailure = false
        private var didWriteAudio = false
        private var writeErrorDescription: String?

        func configure(
            audioFile: AVAudioFile,
            converter: AVAudioConverter,
            processingFormat: AVAudioFormat,
            continuation: AsyncStream<AudioPCM16Frame>.Continuation
        ) {
            lock.lock()
            self.audioFile = audioFile
            self.converter = converter
            self.processingFormat = processingFormat
            self.continuation = continuation
            sequenceNumber = 0
            didLogConversionFailure = false
            didLogWriteFailure = false
            didWriteAudio = false
            writeErrorDescription = nil
            lock.unlock()
        }

        func finishAndReset() -> Snapshot {
            lock.lock()
            let activeContinuation = continuation
            let snapshot = Snapshot(
                didWriteAudio: didWriteAudio,
                writeErrorDescription: writeErrorDescription
            )
            audioFile = nil
            converter = nil
            processingFormat = nil
            continuation = nil
            sequenceNumber = 0
            didLogConversionFailure = false
            didLogWriteFailure = false
            didWriteAudio = false
            writeErrorDescription = nil
            lock.unlock()

            activeContinuation?.finish()
            return snapshot
        }

        func writeAndEmit(buffer: AVAudioPCMBuffer) {
            lock.lock()
            defer { lock.unlock() }

            guard let converter, let processingFormat else {
                return
            }

            let convertedFrameEstimate = Int(
                Double(buffer.frameLength) * processingFormat.sampleRate / buffer.format.sampleRate
            ) + 64
            // AVAudioConverter.convert(to:from:) requires output capacity >= input frameLength.
            let targetFrameCapacity = AVAudioFrameCount(max(Int(buffer.frameLength), max(1, convertedFrameEstimate)))
            guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: targetFrameCapacity) else {
                return
            }

            do {
                try converter.convert(to: targetBuffer, from: buffer)
            } catch {
                if !didLogConversionFailure {
                    didLogConversionFailure = true
                    audioRecorderLogger.error("Live audio conversion failed: \(error.localizedDescription, privacy: .public)")
                }
                return
            }
            guard targetBuffer.frameLength > 0 else { return }
            guard let pcm = targetBuffer.floatChannelData else { return }

            do {
                try audioFile?.write(from: targetBuffer)
                didWriteAudio = true
            } catch {
                writeErrorDescription = error.localizedDescription
                if !didLogWriteFailure {
                    didLogWriteFailure = true
                    audioRecorderLogger.error("Recording file write failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            let frameData = encodePCM16(from: pcm[0], frameLength: Int(targetBuffer.frameLength))

            sequenceNumber += 1
            continuation?.yield(
                AudioPCM16Frame(
                    sequenceNumber: sequenceNumber,
                    sampleRate: processingFormat.sampleRate,
                    channelCount: Int(processingFormat.channelCount),
                    samples: frameData
                )
            )
        }

        private func encodePCM16(from samples: UnsafePointer<Float>, frameLength: Int) -> Data {
            var pcm16 = [Int16]()
            pcm16.reserveCapacity(frameLength)

            for index in 0..<frameLength {
                let clampedSample = max(-1.0, min(1.0, samples[index]))
                let scaledSample = clampedSample >= 0
                    ? clampedSample * Float(Int16.max)
                    : clampedSample * 32_768.0
                pcm16.append(Int16(scaledSample.rounded()))
            }

            return pcm16.withUnsafeBytes { Data($0) }
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

        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.liveSampleRate,
            channels: Self.liveChannelCount,
            interleaved: false
        ) else {
            throw AudioRecorderError.conversionSetupFailed
        }

        let fileName = "verbatim_recording_\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        cleanup(fileURL)

        guard let converter = AVAudioConverter(from: sourceFormat, to: processingFormat) else {
            throw AudioRecorderError.conversionSetupFailed
        }

        do {
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: processingFormat.settings,
                commonFormat: processingFormat.commonFormat,
                interleaved: processingFormat.isInterleaved
            )
            let (stream, continuation) = makeLiveFrameStream()

            recordingIOState.configure(
                audioFile: audioFile,
                converter: converter,
                processingFormat: processingFormat,
                continuation: continuation
            )
            outputURL = fileURL
            liveFrameStream = stream
            audioRecorderLogger.info(
                "Preparing recorder. sourceRate=\(sourceFormat.sampleRate, privacy: .public) sourceChannels=\(sourceFormat.channelCount, privacy: .public) targetRate=\(processingFormat.sampleRate, privacy: .public) targetChannels=\(processingFormat.channelCount, privacy: .public) file=\(fileURL.path, privacy: .public)"
            )
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
            audioRecorderLogger.info("Recorder engine started.")
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
            _ = recordingIOState.finishAndReset()
            liveFrameStream = nil
            cleanup(outputURL)
            outputURL = nil
            audioRecorderLogger.error("Recorder failed to start: \(error.localizedDescription, privacy: .public)")
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
        audioRecorderLogger.info("Recorder engine stopped.")

        let recordedURL = outputURL
        let stream = liveFrameStream

        let ioSnapshot = recordingIOState.finishAndReset()
        liveFrameStream = nil
        outputURL = nil

        guard let recordedURL, let stream else {
            return nil
        }

        if let writeErrorDescription = ioSnapshot.writeErrorDescription, ioSnapshot.didWriteAudio == false {
            cleanup(recordedURL)
            throw AudioRecorderError.recordingWriteFailed(writeErrorDescription)
        }

        do {
            let recordedFile = try AVAudioFile(forReading: recordedURL)
            guard recordedFile.length > 0 else {
                cleanup(recordedURL)
                throw AudioRecorderError.emptyRecordingArtifact
            }
        } catch let recorderError as AudioRecorderError {
            throw recorderError
        } catch {
            cleanup(recordedURL)
            throw AudioRecorderError.recordingWriteFailed(error.localizedDescription)
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
