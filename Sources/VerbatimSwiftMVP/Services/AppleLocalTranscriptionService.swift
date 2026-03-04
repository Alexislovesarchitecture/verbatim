import Foundation
import Speech

@available(macOS 26.0, *)
@available(iOS 26.0, *)
protocol LocalTranscriptionServiceProtocol {
    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript
}

enum LocalTranscriptionError: LocalizedError {
    case missingAudioFile
    case unsupportedModel(LocalTranscriptionModel)
    case speechPermissionDenied
    case speechPermissionRestricted
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recognitionFailed(Error)
    case noTranscriptionResult

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "Recorded audio file is missing."
        case .unsupportedModel(let model):
            return "\(model.title) is coming soon and is not available yet."
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
        }
    }
}

@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class AppleLocalTranscriptionService: LocalTranscriptionServiceProtocol {
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }

        guard model.isImplemented else {
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
            let transcriptText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcriptText.isEmpty else {
                throw LocalTranscriptionError.noTranscriptionResult
            }

            let segments = result.bestTranscription.segments.map { segment in
                TranscriptSegment(
                    start: segment.timestamp,
                    end: segment.timestamp + segment.duration,
                    speaker: nil,
                    text: segment.substring
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

    private func recognize(request: SFSpeechURLRecognitionRequest, recognizer: SFSpeechRecognizer) async throws -> SFSpeechRecognitionResult {
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

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
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
                    continuation.resume(returning: result)
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
