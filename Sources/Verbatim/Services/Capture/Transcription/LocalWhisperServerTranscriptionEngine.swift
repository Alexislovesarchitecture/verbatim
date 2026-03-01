import Foundation

final class LocalWhisperServerTranscriptionEngine: TranscriptionEngineProtocol {
    private let settings: AppSettings
    private let modelManager: WhisperModelManager
    private let serverManager: WhisperServerManager
    private let client: LocalWhisperClient

    init(
        settings: AppSettings,
        modelManager: WhisperModelManager = WhisperModelManager(),
        serverManager: WhisperServerManager,
        client: LocalWhisperClient = LocalWhisperClient()
    ) {
        self.settings = settings
        self.modelManager = modelManager
        self.serverManager = serverManager
        self.client = client
    }

    func transcribe(fileURL: URL, prompt: String?, language: String) async throws -> String {
        let modelId = modelManager.normalizeModelId(settings.whisperModelId)
        guard modelManager.isModelDownloaded(modelId, modelsDirectory: settings.whisperModelsDir) else {
            throw TranscriptionEngineError.missingModel
        }

        let model = modelManager.modelPath(for: modelId, modelsDirectory: settings.whisperModelsDir)
        let binaryPath = try await serverManager.ensureServerBinaryPath(overridePath: settings.whisperCppPath)
        let serverURL = try await serverManager.ensureServerRunning(
            modelPath: model.path,
            binaryPath: binaryPath,
            config: .init(threads: max(1, settings.whisperLocalThreads), language: language.isEmpty ? "auto" : language)
        )

        let transcript = try await client.transcribe(
            fileURL: fileURL,
            prompt: prompt,
            language: language.isEmpty ? "auto" : language,
            serverURL: serverURL
        )
        let clean = transcript
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.isEmpty || isBlankAudioMarker(clean) {
            throw TranscriptionEngineError.emptyTranscript
        }
        return clean
    }

    private func isBlankAudioMarker(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "[blank_audio]" || normalized == "[blank audio]"
    }
}
