import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum RecorderState: Equatable {
    case idle
    case recording
    case transcribing
    case ready
    case error(String)
}

@MainActor
@available(macOS 26.0, *)
@available(iOS 26.0, *)
final class TranscriptionViewModel: ObservableObject {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var transcript: String = ""
    @Published var apiKey: String = ""
    @Published var selectedModel: TranscriptionModel = .gpt4oMiniTranscribe {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.savedModelDefaultsKey)
        }
    }

    private let recorder = AudioRecorderService()
    private let transcriptionService: TranscriptionServiceProtocol

    private static let savedApiKeyDefaultsKey = "VerbatimSwiftMVP.OpenAIAPIKey"
    private static let savedModelDefaultsKey = "VerbatimSwiftMVP.TranscriptionModel"

    init(transcriptionService: TranscriptionServiceProtocol = OpenAITranscriptionService()) {
        self.transcriptionService = transcriptionService
        apiKey = UserDefaults.standard.string(forKey: Self.savedApiKeyDefaultsKey) ?? ""
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedModel = UserDefaults.standard.string(forKey: Self.savedModelDefaultsKey),
           let model = TranscriptionModel(rawValue: savedModel) {
            selectedModel = model
        }
    }

    var statusMessage: String {
        if case .idle = state, effectiveApiKey == nil {
            return "Set an OpenAI API key to start recording."
        }
        switch state {
        case .idle:
            return "Ready to record."
        case .recording:
            return "Recording… click again to stop."
        case .transcribing:
            return "Transcribing with OpenAI..."
        case .ready:
            return "Transcription complete."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording:
            return "Stop"
        case .transcribing:
            return "Transcribing..."
        case .error, .ready, .idle:
            return "Start recording"
        }
    }

    var canToggleRecording: Bool {
        if case .recording = state {
            return true
        }
        if case .transcribing = state { return false }
        return effectiveApiKey != nil
    }

    var canSaveApiKey: Bool {
        !sanitizedApiKey.isEmpty
    }

    var canClearApiKey: Bool {
        !sanitizedApiKey.isEmpty
    }

    var keyStatusMessage: String {
        if !sanitizedApiKey.isEmpty {
            return "Using API key from app."
        }
        if let env = environmentApiKey, !env.isEmpty {
            return "Using OPENAI_API_KEY from environment."
        }
        if hasStoredApiKey {
            return "Using saved app key."
        }
        return "No API key configured."
    }

    var hasApiKeyConfigured: Bool {
        effectiveApiKey != nil
    }

    var hasStoredApiKey: Bool {
        !storedApiKey.isEmpty
    }

    func start() {
        guard effectiveApiKey != nil else {
            state = .error("No OpenAI API key is configured. Paste it in the field above and click Save (or set OPENAI_API_KEY).")
            return
        }
        if case .recording = state {
            return
        }
        if case .transcribing = state {
            return
        }

        Task {
            state = .recording
            do {
                try await recorder.startRecording()
            } catch {
                if let err = error as? AudioRecorderError {
                    state = .error(err.localizedDescription)
                } else {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        guard case .recording = state else { return }

        Task {
            state = .transcribing
            var tempAudioURL: URL?
            do {
            tempAudioURL = try await recorder.stopRecording()
                guard let audioURL = tempAudioURL else {
                    state = .error("No recording file to transcribe.")
                    return
                }

                let text = try await transcriptionService.transcribe(
                    audioFileURL: audioURL,
                    apiKey: effectiveApiKey,
                    model: selectedModel
                )
                if text.isEmpty {
                    state = .error("No transcription returned.")
                } else {
                    transcript = text
                    state = .ready
                }
            } catch {
                if let err = error as? AudioRecorderError {
                    state = .error(err.localizedDescription)
                } else if let err = error as? OpenAITranscriptionError {
                    state = .error(err.localizedDescription)
                } else {
                    state = .error(error.localizedDescription)
                }
            }

            if let audioURL = tempAudioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    func saveApiKey() {
        let trimmed = sanitizedApiKey
        guard !trimmed.isEmpty else {
            return
        }
        UserDefaults.standard.set(trimmed, forKey: Self.savedApiKeyDefaultsKey)
    }

    func clearStoredApiKey() {
        UserDefaults.standard.removeObject(forKey: Self.savedApiKeyDefaultsKey)
        if sanitizedApiKey.isEmpty {
            return
        }
        apiKey = ""
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }

#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
#elseif canImport(UIKit)
        UIPasteboard.general.string = transcript
#endif
    }

    func clearTranscript() {
        transcript = ""
        if case .ready = state {
            state = .idle
        }
    }

    private var sanitizedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var environmentApiKey: String? {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var storedApiKey: String {
        UserDefaults.standard.string(forKey: Self.savedApiKeyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var effectiveApiKey: String? {
        if !sanitizedApiKey.isEmpty {
            return sanitizedApiKey
        }
        if let env = environmentApiKey, !env.isEmpty {
            return env
        }
        if !storedApiKey.isEmpty {
            return storedApiKey
        }
        return nil
    }
}
