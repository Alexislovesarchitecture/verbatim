import Foundation
import SwiftUI

@MainActor
final class VerbumController: ObservableObject {
    @Published var selectedRoute: SidebarRoute = .home
    @Published var phase: DictationPhase = .idle
    @Published var history: [TranscriptRecord]
    @Published var dictionaryEntries: [DictionaryEntry]
    @Published var snippets: [SnippetEntry]
    @Published var styleProfiles: [StyleProfile]
    @Published var notes: [NoteItem]
    @Published var settings: UserSettings
    @Published var lastCapture: LastCapture?
    @Published var errorMessage: String?
    @Published var activeStyleCategory: StyleCategory = .personal
    @Published var selectedStyleProfileID: UUID?

    private let audioCapture: AudioCaptureServicing
    private let inserter: TextInsertionServicing
    private let soundService: SoundServicing
    private let store: LocalStore
    private let formatter = SmartFormatter()
    private let hotkeyMonitor = FunctionKeyMonitor()

    private var pendingStopTask: Task<Void, Never>?
    private var currentAudioStart: Date?
    private var isPrimedForLock = false

    init(
        audioCapture: AudioCaptureServicing,
        inserter: TextInsertionServicing,
        soundService: SoundServicing,
        store: LocalStore = LocalStore()
    ) {
        self.audioCapture = audioCapture
        self.inserter = inserter
        self.soundService = soundService
        self.store = store
        self.history = store.loadOrSeed([TranscriptRecord].self, filename: "history.json", seed: SeedData.history)
        self.dictionaryEntries = store.loadOrSeed([DictionaryEntry].self, filename: "dictionary.json", seed: SeedData.dictionary)
        self.snippets = store.loadOrSeed([SnippetEntry].self, filename: "snippets.json", seed: SeedData.snippets)
        self.styleProfiles = store.loadOrSeed([StyleProfile].self, filename: "styles.json", seed: SeedData.styles)
        self.notes = store.loadOrSeed([NoteItem].self, filename: "notes.json", seed: SeedData.notes)
        self.settings = store.loadOrSeed(UserSettings.self, filename: "settings.json", seed: .default)
        self.lastCapture = store.loadOrSeed(LastCapture?.self, filename: "last-capture.json", seed: nil)
        self.selectedStyleProfileID = styleProfiles.first(where: { $0.category == activeStyleCategory })?.id

        hotkeyMonitor.onPress = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFunctionPress()
            }
        }
        hotkeyMonitor.onRelease = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFunctionRelease()
            }
        }
    }

    func start() {
        PermissionManager.requestAccessibilityIfNeeded()
        Task { await PermissionManager.requestMicrophone() }
        hotkeyMonitor.start()
    }

    func stop() {
        hotkeyMonitor.stop()
        pendingStopTask?.cancel()
    }

    var selectedStyleProfile: StyleProfile? {
        styleProfiles.first(where: { $0.id == selectedStyleProfileID })
    }

    var activeCategoryStyles: [StyleProfile] {
        styleProfiles.filter { $0.category == activeStyleCategory }
    }

    var streakText: String {
        "2 weeks"
    }

    func chooseStyle(_ profile: StyleProfile) {
        activeStyleCategory = profile.category
        selectedStyleProfileID = profile.id
    }

    func addDictionaryEntry() {
        dictionaryEntries.insert(.init(source: "new term", replacement: "New Term"), at: 0)
        persistDictionary()
    }

    func addSnippet() {
        snippets.insert(.init(trigger: "new snippet", expansion: "Expanded text goes here."), at: 0)
        persistSnippets()
    }

    func addNote() {
        notes.insert(.init(title: "New note", body: ""), at: 0)
        persistNotes()
    }

    func pasteLastCapture() {
        guard let transcript = lastCapture?.transcript else { return }
        inserter.pasteLastCapture(transcript)
    }

    func stopLockedRecording() {
        guard phase == .recordingLocked else { return }
        Task { await finalizeRecording() }
    }

    func simulateMockCapture() {
        Task {
            do {
                phase = .transcribing
                try await Task.sleep(for: .milliseconds(500))
                let mockText = "i like the fn press to talk loop and the clipboard fallback if there is no text field"
                try await ingestTranscription(rawText: mockText, engine: .mock, durationSeconds: 6)
            } catch {
                phase = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleFunctionPress() {
        switch phase {
        case .idle, .clipboardReady, .failed:
            startRecording()
        case .recordingPush:
            if isPrimedForLock {
                pendingStopTask?.cancel()
                isPrimedForLock = false
                phase = .recordingLocked
            }
        case .recordingLocked, .transcribing, .inserting:
            break
        }
    }

    private func handleFunctionRelease() {
        switch phase {
        case .recordingPush:
            schedulePossibleStop()
        case .recordingLocked:
            break
        default:
            break
        }
    }

    private func startRecording() {
        do {
            try audioCapture.startRecording()
            currentAudioStart = .now
            phase = .recordingPush
            errorMessage = nil
            if settings.playStartSound {
                soundService.playStart()
            }
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func schedulePossibleStop() {
        isPrimedForLock = true
        pendingStopTask?.cancel()
        pendingStopTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(settings.doubleTapLockWindowSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard self.isPrimedForLock, self.phase == .recordingPush else { return }
                self.isPrimedForLock = false
                Task { await self.finalizeRecording() }
            }
        }
    }

    private func finalizeRecording() async {
        pendingStopTask?.cancel()
        isPrimedForLock = false
        phase = .transcribing
        if settings.playStopSound {
            soundService.playStop()
        }

        do {
            let captured = try await audioCapture.stopRecording()
            let service = transcriptionService(for: settings.selectedEngine)
            let request = TranscriptionRequest(
                audioURL: captured.fileURL,
                languageCode: settings.selectedLanguageCode,
                customTerms: dictionaryEntries.map(\.replacement)
            )
            let result = try await service.transcribe(request)
            try await ingestTranscription(rawText: result.rawText, engine: result.engine, durationSeconds: captured.durationSeconds)
            try? FileManager.default.removeItem(at: captured.fileURL)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func ingestTranscription(rawText: String, engine: TranscriptOrigin, durationSeconds: Double) async throws {
        let formatted = formatter.format(
            rawText: rawText,
            dictionary: dictionaryEntries,
            snippets: snippets,
            style: selectedStyleProfile
        )

        phase = .inserting
        let outcome = settings.autoInsertWhenEditable ? inserter.insertOrFallback(formatted) : .clipboardReady
        let appName = inserter.focusedAppName()
        let wordCount = max(1, formatted.split(separator: " ").count)
        let wpm = Int((Double(wordCount) / max(durationSeconds, 0.1)) * 60.0)

        let record = TranscriptRecord(
            activeAppName: appName,
            rawTranscript: rawText,
            formattedTranscript: formatted,
            engine: engine,
            outcome: outcome,
            durationSeconds: durationSeconds,
            wordsPerMinute: wpm,
            notes: outcome == .clipboardReady ? "No editable field detected. Copied to clipboard." : nil
        )

        history.insert(record, at: 0)
        persistHistory()

        if outcome == .clipboardReady {
            let capture = LastCapture(transcript: formatted, createdAt: .now)
            lastCapture = capture
            try? store.save(lastCapture, filename: "last-capture.json")
            phase = .clipboardReady
        } else {
            phase = .idle
        }
    }

    private func transcriptionService(for origin: TranscriptOrigin) -> TranscriptionServicing {
        switch origin {
        case .mock:
            return MockTranscriptionService()
        case .openAI:
            return OpenAITranscriptionService(
                apiKeyProvider: { [weak self] in self?.settings.openAIAPIKey ?? "" },
                modelProvider: { [weak self] in self?.settings.openAIModel ?? "gpt-4o-mini-transcribe" }
            )
        case .whisperCPP:
            return WhisperCPPTranscriptionService(
                binaryPathProvider: { [weak self] in self?.settings.whisperBinaryPath ?? "" },
                modelPathProvider: { [weak self] in self?.settings.whisperModelPath ?? "" }
            )
        }
    }

    func saveSettings() {
        try? store.save(settings, filename: "settings.json")
    }

    func persistDictionary() {
        try? store.save(dictionaryEntries, filename: "dictionary.json")
    }

    func persistSnippets() {
        try? store.save(snippets, filename: "snippets.json")
    }

    func persistNotes() {
        try? store.save(notes, filename: "notes.json")
    }

    func persistHistory() {
        try? store.save(history, filename: "history.json")
    }

    func persistStyles() {
        try? store.save(styleProfiles, filename: "styles.json")
    }
}
