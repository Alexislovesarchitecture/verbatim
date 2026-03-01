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

        guard let transcriptionEngine = await buildTranscriptionEngine() else {
            currentState = .failed
            uiState = .error
            let message = settings.provider == .openai
                ? "No transcription engine configured. Add an OpenAI key in Settings."
                : "No transcription engine configured. Check whisper.cpp path/model in Settings."
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
            let status: CaptureStatus = .failed
            addFailedCapture(raw: "", formatted: "", status: status, errorMessage: error.localizedDescription)
            overlay.show(state: .error, level: 0, message: error.localizedDescription)
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

    private func buildTranscriptionEngine() async -> TranscriptionEngineProtocol? {
        let settings = settingsRepository.settings()
        switch settings.provider {
        case .openai:
            do {
                guard let key = try keyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !key.isEmpty else {
                    print("OpenAI engine not configured: no API key found in keychain.")
                    return nil
                }
                return OpenAITranscriptionEngine(apiKey: key, model: settings.openAIModel.rawValue)
            } catch {
                print("OpenAI engine not configured: failed reading keychain (\(error))")
                return nil
            }
        case .whispercpp:
            return WhisperCppTranscriptionEngine(
                cliPath: settings.whisperCppPath,
                modelPath: settings.whisperModelPath
            )
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
