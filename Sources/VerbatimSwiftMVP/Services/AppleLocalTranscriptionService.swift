import Foundation
import Speech

protocol LocalTranscriptionServiceProtocol: TranscriptionEngine {
    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript
}

enum LocalTranscriptionError: LocalizedError {
    case missingAudioFile
    case invalidAudioFile(String)
    case unsupportedModel(LocalTranscriptionModel)
    case missingSpeechUsageDescription(String)
    case speechPermissionDenied
    case speechPermissionRestricted
    case unsupportedLocale(String)
    case appleSpeechAssetsNotInstalled(String)
    case appleSpeechAssetsInstalling(String)
    case appleSpeechInstallFailed(String)
    case appleSpeechRuntimeUnavailable(String)
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
        case .missingSpeechUsageDescription(let message):
            return message
        case .speechPermissionDenied:
            return "Speech recognition permission is denied. Enable it in System Settings > Privacy & Security."
        case .speechPermissionRestricted:
            return "Speech recognition is restricted on this device."
        case .unsupportedLocale(let message),
                .appleSpeechAssetsNotInstalled(let message),
                .appleSpeechAssetsInstalling(let message),
                .appleSpeechInstallFailed(let message),
                .appleSpeechRuntimeUnavailable(let message),
                .whisperRuntimeUnavailable(let message),
                .whisperTranscriptionFailed(let message),
                .unsupportedHardware(let message):
            return message
        case .recognitionFailed(let error):
            return "Local transcription failed: \(error.localizedDescription)"
        case .noTranscriptionResult:
            return "No text was returned from local transcription."
        case .whisperModelNotInstalled(let model):
            return "\(model.title) is not installed yet. Download the model in Settings."
        case .whisperModelNeedsInstall(let model):
            return "\(model.title) is downloaded but not installed yet. Install the model in Settings."
        }
    }
}

struct AppleSpeechAuthorizationController: Sendable {
    let currentStatus: @Sendable () -> SFSpeechRecognizerAuthorizationStatus
    let requestStatus: @Sendable () async -> SFSpeechRecognizerAuthorizationStatus

    static let live = AppleSpeechAuthorizationController(
        currentStatus: { SFSpeechRecognizer.authorizationStatus() },
        requestStatus: {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    )
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
    private let runtimeManager: AppleSpeechRuntimeManaging
    private let authorizationController: AppleSpeechAuthorizationController
    private let missingUsageDescription: @Sendable (AppPrivacyUsageDescription) -> String?

    init(
        locale: Locale = .current,
        runtimeManager: AppleSpeechRuntimeManaging = AppleSpeechRuntimeManager(),
        authorizationController: AppleSpeechAuthorizationController = .live,
        missingUsageDescription: @escaping @Sendable (AppPrivacyUsageDescription) -> String? = {
            AppPrivacyUsageDescriptionValidator.missingUsageDescription($0)
        }
    ) {
        self.locale = locale
        self.runtimeManager = runtimeManager
        self.authorizationController = authorizationController
        self.missingUsageDescription = missingUsageDescription
    }

    func transcribeBatch(audioURL: URL, options: TranscriptionOptions) async throws -> Transcript {
        let selectedModel = LocalTranscriptionModel(rawValue: options.modelID) ?? .appleOnDevice
        return try await transcribeLocally(audioFileURL: audioURL, model: selectedModel)
    }

    func runtimeStatus() async -> AppleSpeechRuntimeStatus {
        await runtimeManager.status(for: locale)
    }

    func transcribeLocally(audioFileURL: URL, model: LocalTranscriptionModel) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw LocalTranscriptionError.missingAudioFile
        }

        guard model.backend == .appleSpeech else {
            throw LocalTranscriptionError.unsupportedModel(model)
        }

        if let missingUsageDescription = missingUsageDescription(.speechRecognition) {
            throw LocalTranscriptionError.missingSpeechUsageDescription(missingUsageDescription)
        }

        let authorizationStatus = authorizationController.currentStatus()
        let resolvedAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            resolvedAuthorizationStatus = await authorizationController.requestStatus()
        default:
            resolvedAuthorizationStatus = authorizationStatus
        }

        switch resolvedAuthorizationStatus {
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

        do {
            let snapshot = try await runtimeManager.transcribe(audioFileURL: audioFileURL, preferredLocale: locale)
            let transcriptText = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard transcriptText.isEmpty == false else {
                throw LocalTranscriptionError.noTranscriptionResult
            }

            let segments = snapshot.segments.map { segment in
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
        } catch let error as LocalTranscriptionError {
            throw error
        } catch let error as AppleSpeechRuntimeError {
            throw mapRuntimeError(error)
        } catch {
            throw LocalTranscriptionError.recognitionFailed(error)
        }
    }

    private func mapRuntimeError(_ error: AppleSpeechRuntimeError) -> LocalTranscriptionError {
        switch error {
        case .unsupportedLocale(let message):
            return .unsupportedLocale(message)
        case .assetsNotInstalled(let message):
            return .appleSpeechAssetsNotInstalled(message)
        case .assetsInstalling(let message):
            return .appleSpeechAssetsInstalling(message)
        case .installationFailed(let message):
            return .appleSpeechInstallFailed(message)
        case .runtimeUnavailable(let message):
            return .appleSpeechRuntimeUnavailable(message)
        case .analyzerFailed(let message):
            return .recognitionFailed(NSError(domain: "AppleSpeechRuntime", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ]))
        }
    }
}
