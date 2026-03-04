import Foundation
import Speech

@available(macOS 26.0, *)
@available(iOS 26.0, *)
protocol LocalTranscriptionServiceProtocol {
    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> String
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

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> String {
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
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw LocalTranscriptionError.noTranscriptionResult
            }
            return text
        } catch {
            if let localError = error as? LocalTranscriptionError {
                throw localError
            }
            throw LocalTranscriptionError.recognitionFailed(error)
        }
    }

    private func recognize(request: SFSpeechURLRecognitionRequest, recognizer: SFSpeechRecognizer) async throws -> SFSpeechRecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            var didFinish = false
            var recognitionTask: SFSpeechRecognitionTask?
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if didFinish {
                    return
                }

                if let error {
                    didFinish = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: LocalTranscriptionError.recognitionFailed(error))
                    return
                }

                guard let result else {
                    return
                }

                if result.isFinal {
                    didFinish = true
                    continuation.resume(returning: result)
                }
            }
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
