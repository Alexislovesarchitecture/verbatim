import AppKit
import Combine
import Foundation

@MainActor
final class VerbumStore: ObservableObject {
    @Published var activeSection: SidebarSection? = .home
    @Published var listeningState: ListeningState = .idle
    @Published var inputLevel: Float = 0
    @Published var settings: AppSettings
    @Published var entries: [DictationEntry]
    @Published var dictionaryEntries: [DictionaryEntry]
    @Published var snippetEntries: [SnippetEntry]
    @Published var noteEntries: [NoteEntry]
    @Published var lastError: String?

    private let recorder = AudioRecorder()
    private let hotkeyMonitor = HotkeyMonitor()
    private let formatter = FormatterPipeline()
    private let insertionService = InsertionService()
    private let overlay = OverlayController()
    private let dataStore = DataStore()

    init() {
        let persisted = dataStore.load()
        self.settings = persisted.settings
        self.entries = persisted.entries
        self.dictionaryEntries = persisted.dictionaryEntries
        self.snippetEntries = persisted.snippetEntries
        self.noteEntries = persisted.noteEntries
        configureHotkeyMonitor()
        hotkeyMonitor.start()
        insertionService.promptForAccessibilityIfNeeded()
    }

    var totalWordCount: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    var averageWPM: Int {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.wordsPerMinute } / entries.count
    }

    func configureHotkeyMonitor() {
        hotkeyMonitor.onPress = { [weak self] in
            guard let self else { return }
            if self.listeningState == .recordingLocked {
                return
            }
            self.startListening(lockMode: false)
        }
        hotkeyMonitor.onDoubleTap = { [weak self] in
            guard let self else { return }
            self.startListening(lockMode: true)
        }
        hotkeyMonitor.onRelease = { [weak self] in
            guard let self else { return }
            if self.listeningState == .recordingLocked {
                return
            }
            if self.listeningState == .recording {
                self.stopListening()
            }
        }
    }

    func startListening(lockMode: Bool) {
        guard listeningState == .idle || listeningState == .clipboardReady || listeningState == .error else {
            if lockMode, listeningState == .recording {
                listeningState = .recordingLocked
                overlay.show(state: .recordingLocked, level: inputLevel, message: "Locked listening", stopAction: { [weak self] in
                    self?.stopLockedListening()
                })
            }
            return
        }

        do {
            if settings.playStartSound {
                NSSound.beep()
            }
            try recorder.start { [weak self] level in
                Task { @MainActor in
                    self?.inputLevel = level
                    if let state = self?.listeningState, state == .recording || state == .recordingLocked {
                        self?.overlay.update(state: state, level: level)
                    }
                }
            }
            listeningState = lockMode ? .recordingLocked : .recording
            overlay.show(state: listeningState, level: 0, message: lockMode ? "Locked listening" : "Hold Fn to talk", stopAction: { [weak self] in
                self?.stopLockedListening()
            })
        } catch {
            listeningState = .error
            lastError = error.localizedDescription
            overlay.show(state: .error, level: 0, message: error.localizedDescription)
        }
    }

    func stopListening() {
        guard listeningState == .recording || listeningState == .recordingLocked else { return }
        let fileURL = recorder.stop()
        processAudioFile(fileURL)
    }

    func stopLockedListening() {
        guard listeningState == .recordingLocked else { return }
        let fileURL = recorder.stop()
        processAudioFile(fileURL)
    }

    func cancelListening() {
        recorder.cancel()
        listeningState = .idle
        overlay.hide()
    }

    func copyLastCaptureToClipboard() {
        insertionService.copyLastCaptureToClipboard()
    }

    func addDictionaryEntry(phrase: String, replacement: String?) {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dictionaryEntries.insert(DictionaryEntry(phrase: phrase, replacement: replacement), at: 0)
        persist()
    }

    func removeDictionaryEntries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            dictionaryEntries.remove(at: offset)
        }
        persist()
    }

    func addSnippet(trigger: String, expansion: String) {
        guard !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snippetEntries.insert(SnippetEntry(trigger: trigger, expansion: expansion), at: 0)
        persist()
    }

    func removeSnippets(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            snippetEntries.remove(at: offset)
        }
        persist()
    }

    func addNote(title: String, body: String) {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
        noteEntries.insert(NoteEntry(title: finalTitle, body: body), at: 0)
        persist()
    }

    func removeNotes(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            noteEntries.remove(at: offset)
        }
        persist()
    }

    func persist() {
        let state = PersistedState(
            settings: settings,
            entries: entries,
            dictionaryEntries: dictionaryEntries,
            snippetEntries: snippetEntries,
            noteEntries: noteEntries
        )
        dataStore.save(state)
    }

    private func processAudioFile(_ fileURL: URL?) {
        guard let fileURL else {
            listeningState = .idle
            overlay.hide()
            return
        }

        listeningState = .transcribing
        overlay.show(state: .transcribing, level: 0, message: "Transcribing")

        let appName = insertionService.frontmostAppName()
        let styleCategory = insertionService.appCategory()
        let startedAt = Date()

        Task {
            do {
                let raw = try await makeTranscriptionEngine().transcribe(
                    fileURL: fileURL,
                    prompt: transcriptionPrompt(),
                    language: settings.languageCode
                )
                let duration = Date().timeIntervalSince(startedAt)
                let cleaned = formatter.format(raw, context: FormattingContext(
                    settings: settings,
                    styleCategory: styleCategory,
                    dictionaryEntries: dictionaryEntries,
                    snippets: snippetEntries
                ))

                listeningState = .inserting
                overlay.show(state: .inserting, level: 0, message: "Sending to \(appName)")
                let result = insertionService.insert(text: cleaned, autoInsert: settings.autoInsert, autoPasteFallback: settings.autoPasteFallback, keepClipboardBackup: settings.keepClipboardBackup)

                if settings.keepHistory {
                    entries.insert(
                        DictationEntry(
                            rawText: raw,
                            formattedText: cleaned,
                            destinationApp: appName,
                            durationSeconds: duration,
                            result: result,
                            inputWasSilent: raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ),
                        at: 0
                    )
                }

                if cleaned.count > 120 {
                    noteEntries.insert(NoteEntry(title: String(cleaned.prefix(36)), body: cleaned), at: 0)
                }

                listeningState = (result == .clipboardOnly || result == .pastedViaClipboard) ? .clipboardReady : .idle
                let message = result == .clipboardOnly ? "Captured. Press Command-V to paste." : result == .pastedViaClipboard ? "Pasted via clipboard fallback." : "Inserted"
                overlay.show(state: listeningState == .idle ? .inserting : .clipboardReady, level: 0, message: message)
                persist()
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                listeningState = .idle
                overlay.hide()
            } catch {
                listeningState = .error
                lastError = error.localizedDescription
                overlay.show(state: .error, level: 0, message: error.localizedDescription)
                persist()
            }

            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func makeTranscriptionEngine() -> TranscriptionEngine {
        switch settings.provider {
        case .openAI:
            return OpenAITranscriptionEngine(apiKey: settings.openAIAPIKey, model: settings.openAIModel)
        case .whisperCLI:
            return WhisperCLITranscriptionEngine(executablePath: settings.whisperCLIPath, modelPath: settings.whisperModelPath)
        }
    }

    private func transcriptionPrompt() -> String {
        let terms = dictionaryEntries.map { $0.replacement ?? $0.phrase }
        guard !terms.isEmpty else { return "" }
        return "Prefer these terms when relevant: " + terms.joined(separator: ", ")
    }
}
