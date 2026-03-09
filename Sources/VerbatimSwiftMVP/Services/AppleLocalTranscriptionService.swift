import Foundation
import Speech

protocol LocalTranscriptionServiceProtocol: TranscriptionEngine {
    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript
}

enum LocalTranscriptionError: LocalizedError {
    case missingAudioFile
    case invalidAudioFile(String)
    case unsupportedModel(LocalTranscriptionModel)
    case speechPermissionDenied
    case speechPermissionRestricted
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recognitionFailed(Error)
    case noTranscriptionResult
    case whisperRuntimeUnavailable(String)
    case whisperModelNotInstalled(LocalTranscriptionModel)
    case whisperModelNeedsInstall(LocalTranscriptionModel)
    case whisperTranscriptionFailed(String)
    case unsupportedHardware(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Recorded audio file is missing."
        case .invalidAudioFile(let message):
            return message
        case .unsupportedModel(let model):
            return "\(model.title) is not available for the current local backend."
        case .speechPermissionDenied:
            return "Speech recognition permission is denied. Enable it in System Settings > Privacy & Security."
        case .speechPermissionRestricted:
            return "Speech recognition is restricted on this device."
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the current locale."
        case .onDeviceRecognitionUnavailable:
            return "On-device transcription is unavailable on this device."
        case .recognitionFailed(let error):
            return "Local transcription failed: \(error.localizedDescription)"
        case .noTranscriptionResult:
            return "No text was returned from local transcription."
        case .whisperRuntimeUnavailable(let message):
            return "Whisper runtime is unavailable: \(message)"
        case .whisperModelNotInstalled(let model):
            return "\(model.title) is not installed yet. Download the model in Settings."
        case .whisperModelNeedsInstall(let model):
            return "\(model.title) is downloaded but not installed yet. Install the model in Settings."
        case .whisperTranscriptionFailed(let message):
            return "Whisper transcription failed: \(message)"
        case .unsupportedHardware(let message):
            return message
        }
    }
}
final class AppleLocalTranscriptionService: LocalTranscriptionServiceProtocol, @unchecked Sendable {
    let engineID = "apple-speech-ondevice"
    let capabilities = EngineCapabilities(
        supportsStreamingEvents: false,
        supportsLiveAudioFrames: false,
        supportsDiarization: false,
        supportsLogprobs: false,
        supportsTimestamps: true,
        supportsPrompt: false
    )

    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let selectedModel = LocalTranscriptionModel(rawValue: options.modelID) ?? .appleOnDevice
        return try await transcribeLocally(audioFileURL: audioURL, model: selectedModel)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }

        guard model.backend == .appleSpeech else {
            throw LocalTranscriptionError.unsupportedModel(model)
        }

        let authorizationStatus = await requestSpeechAuthorization()
        switch authorizationStatus {
        case .authorized:
            break
        case .denied:
            throw LocalTranscriptionError.speechPermissionDenied
        case .restricted:
            throw LocalTranscriptionError.speechPermissionRestricted
        case .notDetermined:
            throw LocalTranscriptionError.speechPermissionDenied
        @unknown default:
            throw LocalTranscriptionError.speechPermissionDenied
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw LocalTranscriptionError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw LocalTranscriptionError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioFileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        do {
            let result = try await recognize(request: request, recognizer: recognizer)
            let transcriptText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcriptText.isEmpty else {
                throw LocalTranscriptionError.noTranscriptionResult
            }

            let segments = result.segments.map { segment in
                TranscriptSegment(
                    start: segment.start,
                    end: segment.end,
                    speaker: nil,
                    text: segment.text
                )
            }

            return Transcript(
                rawText: transcriptText,
                segments: segments,
                tokenLogprobs: nil,
                lowConfidenceSpans: [],
                modelID: model.rawValue,
                responseFormat: "text"
            )
        } catch {
            if let localError = error as? LocalTranscriptionError {
                throw localError
            }
            throw LocalTranscriptionError.recognitionFailed(error)
        }
    }

    private struct RecognitionSnapshot: Sendable {
        struct Segment: Sendable {
            let start: TimeInterval
            let end: TimeInterval
            let text: String
        }

        let text: String
        let segments: [Segment]
    }

    private func recognize(request: SFSpeechURLRecognitionRequest, recognizer: SFSpeechRecognizer) async throws -> RecognitionSnapshot {
        final class RecognitionState {
            private let lock = NSLock()
            private var didFinish = false
            private var task: SFSpeechRecognitionTask?

            func setTask(_ task: SFSpeechRecognitionTask) {
                lock.lock()
                self.task = task
                lock.unlock()
            }

            func finishIfNeeded() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if didFinish { return false }
                didFinish = true
                return true
            }

            func cancelTask() {
                lock.lock()
                let activeTask = task
                task = nil
                lock.unlock()
                activeTask?.cancel()
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecognitionSnapshot, Error>) in
            let state = RecognitionState()

            let recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard state.finishIfNeeded() else { return }
                    state.cancelTask()
                    continuation.resume(throwing: LocalTranscriptionError.recognitionFailed(error))
                    return
                }

                guard let result else {
                    return
                }

                if result.isFinal {
                    guard state.finishIfNeeded() else { return }
                    state.cancelTask()

                    let transcription = result.bestTranscription
                    let snapshot = RecognitionSnapshot(
                        text: transcription.formattedString,
                        segments: transcription.segments.map { segment in
                            RecognitionSnapshot.Segment(
                                start: segment.timestamp,
                                end: segment.timestamp + segment.duration,
                                text: segment.substring
                            )
                        }
                    )
                    continuation.resume(returning: snapshot)
                }
            }

            state.setTask(recognitionTask)
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
