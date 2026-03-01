import Foundation
import AppKit

@MainActor
final class CaptureCoordinator: ObservableObject, CaptureCoordinatorProtocol {
    @Published private(set) var uiState: CaptureUICue = .idle
    @Published private(set) var toastText: String?

    private let audioRecorder = AudioRecorder()
    private let insertionService: TextInsertionServicing
    private let hotkeyMonitor: FunctionKeyMonitor
    private let overlay: OverlayController
    private let formattingPipeline: FormattingPipelineProtocol
    private let captureRepository: CaptureRepository
    private let dictionaryRepository: DictionaryRepository
    private let snippetRepository: SnippetRepository
    private let styleRepository: StyleRepository
    private let noteRepository: NoteRepository
    let settingsRepository: SettingsRepository
    private let keyStore: OpenAIKeyStore
    private let whisperModelManager: WhisperModelManager
    private let whisperServerManager: WhisperServerManager
    private let localWhisperClient: LocalWhisperClient
    private let onRecordingSaved: (@MainActor () -> Void)?

    private var currentState: CaptureCoordinatorState = .idle
    private var wasLocked = false
    private var recorderStartDate: Date = .now

    init(
        insertionService: TextInsertionServicing,
        hotkeyMonitor: FunctionKeyMonitor,
        overlay: OverlayController,
        formattingPipeline: FormattingPipelineProtocol,
        captureRepository: CaptureRepository,
        dictionaryRepository: DictionaryRepository,
        snippetRepository: SnippetRepository,
        styleRepository: StyleRepository,
        noteRepository: NoteRepository,
        settingsRepository: SettingsRepository,
        keyStore: OpenAIKeyStore,
        whisperModelManager: WhisperModelManager = WhisperModelManager(),
        whisperServerManager: WhisperServerManager = WhisperServerManager(),
        localWhisperClient: LocalWhisperClient = LocalWhisperClient(),
        onRecordingSaved: @escaping @MainActor () -> Void = {}
    ) {
        self.insertionService = insertionService
        self.hotkeyMonitor = hotkeyMonitor
        self.overlay = overlay
        self.formattingPipeline = formattingPipeline
        self.captureRepository = captureRepository
        self.dictionaryRepository = dictionaryRepository
        self.snippetRepository = snippetRepository
        self.styleRepository = styleRepository
        self.noteRepository = noteRepository
        self.settingsRepository = settingsRepository
        self.keyStore = keyStore
        self.whisperModelManager = whisperModelManager
        self.whisperServerManager = whisperServerManager
        self.localWhisperClient = localWhisperClient
        self.onRecordingSaved = onRecordingSaved
        configureHotkeys()
    }

    func startListening() {
        guard currentState == .idle else {
            if currentState == .locked {
                return
            }
            if currentState == .recording {
                stopListening()
            }
            return
        }

        let settings = settingsRepository.settings()
        do {
            if settings.startSoundEnabled {
                NSSound.beep()
            }
            recorderStartDate = .now
            try audioRecorder.start { [weak self] level in
                guard let self else { return }
                guard self.currentState == .recording || self.currentState == .locked else { return }
                if settings.overlayMeterEnabled {
                    self.overlay.update(state: self.currentState == .recording ? .recording : .recordingLocked, level: level)
                }
            }
            currentState = .recording
            wasLocked = false
            uiState = .recording
            overlay.show(state: .recording, level: 0, message: "Hold Fn to dictate")
        } catch {
            uiState = .error
            currentState = .failed
            overlay.show(state: .error, level: 0, message: error.localizedDescription)
        }
    }

    func stopListening() {
        guard currentState == .recording || currentState == .locked else { return }
        guard let url = audioRecorder.stop() else {
            let settings = settingsRepository.settings()
            addFailedCapture(raw: "", formatted: "", status: .failed, errorMessage: "No captured audio")
            if settings.stopSoundEnabled {
                NSSound.beep()
            }
            currentState = .failed
            uiState = .error
            overlay.show(state: .error, level: 0, message: "Failed to stop capture")
            return
        }

        if settingsRepository.settings().stopSoundEnabled {
            NSSound.beep()
        }
        Task {
            await ingest(rawAudioURL: url, wasLocked: wasLocked)
        }
    }

    func lockListening() {
        guard currentState == .recording else { return }
        wasLocked = true
        currentState = .locked
        uiState = .recordingLocked
        overlay.show(state: .recordingLocked, level: 0, message: "Locked listening") { [weak self] in
            self?.unlockListening()
        }
    }

    func unlockListening() {
        guard currentState == .locked else { return }
        stopListening()
    }

    func ingest(rawAudioURL: URL, wasLocked: Bool) async {
        defer {
            if currentState != .failed {
                currentState = .idle
            } else {
                currentState = .idle
            }
            if currentState == .idle {
                uiState = .idle
            }
            overlay.hide()
            onRecordingSaved?()
        }

        let url = rawAudioURL
        let settings = settingsRepository.settings()
        let behavior = settingsRepository.behaviorSettings()

        let transcriptionEngine: TranscriptionEngineProtocol
        do {
            transcriptionEngine = try await buildTranscriptionEngine()
        } catch {
            currentState = .failed
            uiState = .error
            let message = transcriptionConfigErrorMessage(error, for: settings)
            overlay.show(state: .error, level: 0, message: message)
            addFailedCapture(raw: "", formatted: "", status: .failed, errorMessage: message)
            return
        }

        currentState = .transcribing
        uiState = .transcribing
        overlay.show(state: .transcribing, level: 0.9, message: "Transcribing")

        let category = insertionService.inferStyleCategory()
        let styleProfile = styleRepository.profile(for: category) ?? StyleProfile(category: category)
        let engineUsed = settings.provider == .openai ? EngineUsed.openai : .whispercpp

        do {
            let raw = try await transcriptionEngine.transcribe(
                fileURL: url,
                prompt: behavior.biasTranscriptionWithDictionary ? transcriptionPrompt() : nil,
                language: settings.language.isEmpty ? "en" : settings.language
            )

            let durationMs = max(Int(Date().timeIntervalSince(recorderStartDate) * 1000), 1)
            let durationSeconds = max(Double(durationMs) / 1000.0, 0.1)
            let dictionaryEntries = dictionaryRepository.all(scope: nil).filter { $0.enabled && ($0.scope == .personal || $0.scope == .sharedStub) }
            let snippetEntries = snippetRepository.all(scope: nil).filter { $0.enabled && ($0.scope == .personal || $0.scope == .sharedStub) }
            let formatted = formattingPipeline.apply(
                rawText: raw,
                styleProfile: styleProfile,
                dictionaryEntries: dictionaryEntries,
                snippetEntries: snippetEntries,
                applyDictionaryReplacements: behavior.applyReplacementsAfterTranscription,
                applySnippets: behavior.enableSnippetExpansion,
                snippetGlobalExactMatch: behavior.globalRequireExactMatch,
                removeFillers: styleProfile.removeFillers,
                interpretVoiceCommands: styleProfile.interpretVoiceCommands
            )
            let outputText = formatted.isEmpty ? raw : formatted

            let trimmed = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText = trimmed.isEmpty ? raw : trimmed
            let wordCount = max(finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count, 0)
            let wpm = wordCount > 0 ? Double(wordCount) / durationSeconds * 60.0 : 0
            let isSilent = audioRecorder.wasSilentThreshold(settings.silenceThreshold)
            let insertionResult = applyInsertionDecisionTree(text: finalText, settings: settings, engineUsed: engineUsed)

            let record = CaptureRecord(
                createdAt: .now,
                sourceAppName: insertionService.frontmostApplicationName(),
                sourceBundleId: insertionService.frontmostBundleIdentifier(),
                durationMs: durationMs,
                wordCount: wordCount,
                wpm: wpm,
                rawText: raw,
                formattedText: finalText,
                resultStatus: insertionResult.status,
                errorMessage: insertionResult.errorMessage,
                audioWasSilent: isSilent,
                engineUsed: engineUsed,
                wasLockedMode: wasLocked
            )

            captureRepository.add(record)

            if settings.autoSaveLongCapturesToNotes && wordCount >= settings.longCaptureThresholdWords {
                let prefix = String(finalText.prefix(52)).trimmingCharacters(in: .whitespacesAndNewlines)
                noteRepository.add(
                    NoteEntry(
                        title: prefix.isEmpty ? "Dictation note" : prefix,
                        body: finalText,
                        sourceCaptureId: record.id
                    )
                )
            }

            if settings.historyRetentionDays > 0 {
                let cutoff = Calendar.current.date(byAdding: .day, value: -settings.historyRetentionDays, to: .now) ?? .distantPast
                captureRepository.purge(before: cutoff)
            }

            currentState = insertionResult.status == .failed ? .failed : .idle
            uiState = insertionResult.status == .clipboard ? .clipboardReady : insertionResult.status == .inserted ? .idle : .error
            overlay.show(
                state: uiState == .clipboardReady ? .clipboardReady : (uiState == .error ? .error : .idle),
                level: 1,
                message: insertionResult.toast
            )

            if insertionResult.status == .clipboard && settings.showCapturedToastEnabled {
                showToast(insertionResult.toast)
            }
        } catch {
            currentState = .failed
            uiState = .error
            print("Transcription failed: \(error)")
            let message = transcriptionRuntimeErrorMessage(error, settings: settings)
            let status: CaptureStatus = .failed
            addFailedCapture(raw: "", formatted: "", status: status, errorMessage: message)
            overlay.show(state: .error, level: 0, message: message)
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // ignore cleanup failure
        }
    }

    func copyLastCapture() {
        guard let last = captureRepository.latest() else { return }
        let text = !last.formattedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? last.formattedText : last.rawText
        insertionService.copyToClipboard(text)
    }

    func getLastCaptureText() -> String? {
        guard let last = captureRepository.latest() else { return nil }
        let text = !last.formattedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? last.formattedText : last.rawText
        return text
    }

    func startListeningMonitoring() {
        hotkeyMonitor.start()
    }

    func stopListeningMonitoring() {
        hotkeyMonitor.stop()
    }

    func startLocalWhisperServerIfNeeded() {
        Task {
            let settings = settingsRepository.settings()
            guard settings.provider == .whispercpp,
                  (settings.whisperBackend ?? .server) == .server,
                  settings.whisperServerAutoStart ?? true else {
                return
            }
            _ = await ensureServerRunningForCurrentSettings()
        }
    }

    func stopLocalWhisperServer() {
        Task {
            await whisperServerManager.stop()
        }
    }

    private func configureHotkeys() {
        hotkeyMonitor.onPress = { [weak self] in
            guard let self else { return }
            if self.currentState == .locked {
                return
            }
            self.startListening()
        }

        hotkeyMonitor.onDoubleTap = { [weak self] in
            guard let self else { return }
            self.lockListening()
        }

        hotkeyMonitor.onRelease = { [weak self] in
            guard let self else { return }
            if self.currentState == .recording {
                self.stopListening()
            }
        }
    }

    private func transcriptionPrompt() -> String {
        let dictionaryTerms = dictionaryRepository
            .all(scope: nil)
            .filter { $0.enabled && !$0.output.isNilOrEmpty }
            .map { "\($0.input)=\($0.output ?? "")" }
            .joined(separator: ", ")
        return dictionaryTerms.isEmpty ? "" : "Prefer these terms: \(dictionaryTerms)"
    }

    func buildTranscriptionEngine() async throws -> TranscriptionEngineProtocol {
        let settings = settingsRepository.settings()
        switch settings.provider {
        case .openai:
            do {
                guard let key = try keyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else {
                    throw TranscriptionEngineError.missingAPIKey
                }
                return OpenAITranscriptionEngine(
                    apiKey: key,
                    model: (settings.openAIModel ?? .gpt4oMiniTranscribe).rawValue
                )
            } catch {
                if error is TranscriptionEngineError {
                    throw error
                }
                throw TranscriptionEngineError.missingAPIKey
            }
        case .whispercpp:
            let modelId = whisperModelManager.normalizeModelId(settings.whisperModelId ?? WhisperLocalModel.defaultId.rawValue)
            if (settings.whisperBackend ?? .server) == .cli {
                return try buildLegacyWhisperEngine(from: settings)
            }

            guard whisperModelManager.isModelDownloaded(
                modelId,
                modelsDirectory: settings.whisperModelsDir ?? WhisperModelDirectory.defaultPath
            ) else {
                throw TranscriptionEngineError.missingModel
            }

            do {
                _ = try await whisperServerManager.ensureServerBinaryPath(overridePath: settings.whisperCppPath)
                return LocalWhisperServerTranscriptionEngine(
                    settings: settings,
                    modelManager: whisperModelManager,
                    serverManager: whisperServerManager,
                    client: localWhisperClient
                )
            } catch {
                print("Local whisper server unavailable: \(error)")
                throw mapWhisperManagerError(error)
            }
        }
    }

    private func buildLegacyWhisperEngine(from settings: AppSettings) throws -> WhisperCppTranscriptionEngine {
        let rawCliPath = settings.whisperCppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawModelPath = settings.whisperModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawCliPath.isEmpty else {
            throw TranscriptionEngineError.missingExecutable
        }
        guard !rawModelPath.isEmpty else {
            throw TranscriptionEngineError.missingModel
        }

        let cliPath = (rawCliPath as NSString).expandingTildeInPath
        let modelPath = (rawModelPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: cliPath) else {
            throw TranscriptionEngineError.missingExecutable
        }
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            throw TranscriptionEngineError.executableNotRunnable
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranscriptionEngineError.missingModel
        }

        return WhisperCppTranscriptionEngine(
            cliPath: settings.whisperCppPath,
            modelPath: settings.whisperModelPath
        )
    }

    private func mapWhisperManagerError(_ error: Error) -> TranscriptionEngineError {
        if let serverError = error as? WhisperServerManagerError {
            switch serverError {
            case .binaryNotFound, .binaryNotExecutable:
                return .missingServerBinary
            case .startupTimeout:
                return .serverTimeout
            case .processExited:
                return .requestFailed(error.localizedDescription)
            }
        }
        if let engineError = error as? TranscriptionEngineError {
            return engineError
        }
        return TranscriptionEngineError.requestFailed(error.localizedDescription)
    }

    private func transcriptionConfigErrorMessage(_ error: Error, for settings: AppSettings) -> String {
        let transcriptError = error as? TranscriptionEngineError ?? .requestFailed("Unknown error")
        switch transcriptError {
        case .missingAPIKey:
            return "No OpenAI API key found. Add one in Settings."
        case .missingModel:
            return settings.provider == .openai
                ? "Missing OpenAI model configuration."
                : "Local whisper model not downloaded. Select a model and click Download model."
        case .missingExecutable:
            return "Local whisper CLI executable is missing."
        case .executableNotRunnable:
            return "Local whisper CLI executable is not runnable."
        case .missingServerBinary:
            return "Local whisper server binary is not available. Download it from Settings."
        case .missingServerEndpoint:
            return "Local whisper server endpoint is unavailable."
        case .serverTimeout:
            return "Local whisper server did not start in time."
        case .invalidResponse, .requestFailed:
            return "Failed to initialize transcription."
        case .emptyTranscript:
            return "Transcription was empty."
        }
    }

    private func transcriptionRuntimeErrorMessage(_ error: Error, settings: AppSettings) -> String {
        if let transcriptError = error as? TranscriptionEngineError {
            return transcriptionConfigErrorMessage(transcriptError, for: settings)
        }

        if let serverError = error as? WhisperServerManagerError {
            switch serverError {
            case .binaryNotFound, .binaryNotExecutable:
                return "Local whisper server binary is unavailable."
            case .startupTimeout:
                return "Local whisper server did not start in time."
            case .processExited(let reason):
                return "Local whisper server exited unexpectedly: \(reason)"
            }
        }

        return error.localizedDescription
    }

    func ensureServerRunningForCurrentSettings() async -> URL? {
        let settings = settingsRepository.settings()
        guard settings.provider == .whispercpp, (settings.whisperBackend ?? .server) == .server else { return nil }
        let modelId = whisperModelManager.normalizeModelId(settings.whisperModelId ?? WhisperLocalModel.defaultId.rawValue)
        guard whisperModelManager.isModelDownloaded(
            modelId,
            modelsDirectory: settings.whisperModelsDir ?? WhisperModelDirectory.defaultPath
        ) else {
            return nil
        }
        let modelPath = whisperModelManager.modelPath(
            for: modelId,
            modelsDirectory: settings.whisperModelsDir ?? WhisperModelDirectory.defaultPath
        )
        do {
            let binaryURL = try await whisperServerManager.ensureServerBinaryPath(overridePath: settings.whisperCppPath)
            return try await whisperServerManager.ensureServerRunning(
                modelPath: modelPath.path,
                binaryPath: binaryURL,
                config: .init(
                    threads: max(1, settings.whisperLocalThreads ?? 4),
                    language: settings.language.isEmpty ? "auto" : settings.language
                )
            )
        }
        catch {
            print("Failed to prewarm whisper server: \(error)")
            return nil
        }
    }

    func applyInsertionDecisionTree(
        text: String,
        settings: AppSettings,
        engineUsed: EngineUsed
    ) -> (status: CaptureStatus, errorMessage: String?, toast: String) {
        _ = engineUsed
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return (.failed, "No transcript content", "No transcript content")
        }

        let shouldTryInsertion = settings.autoInsertEnabled && settings.insertionModePreferred == .accessibilityFirst
        if shouldTryInsertion && insertionService.hasEditableTarget() {
            if insertionService.insert(content) {
                return (.inserted, nil, "Inserted.")
            }
        }

        guard settings.clipboardFallbackEnabled else {
            return (.failed, "No editable target and clipboard fallback is disabled.", "Capture failed.")
        }

        insertionService.copyToClipboard(content)
        return (.clipboard, nil, "Captured. Cmd+V to paste.")
    }

    private func addFailedCapture(raw: String, formatted: String, status: CaptureStatus, errorMessage: String?) {
        let durationMs = max(Int(Date().timeIntervalSince(recorderStartDate) * 1000), 1)
        let settings = settingsRepository.settings()
        let record = CaptureRecord(
            createdAt: .now,
            sourceAppName: insertionService.frontmostApplicationName(),
            sourceBundleId: insertionService.frontmostBundleIdentifier(),
            durationMs: durationMs,
            wordCount: 0,
            wpm: 0,
            rawText: raw,
            formattedText: formatted,
            resultStatus: status,
            errorMessage: errorMessage,
            audioWasSilent: false,
            engineUsed: settings.provider == .openai ? .openai : .whispercpp,
            wasLockedMode: wasLocked
        )
        captureRepository.add(record)
    }

    private func showToast(_ message: String) {
        toastText = message
        guard let window = NSApplication.shared.windows.first else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
