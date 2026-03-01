import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class AppState: ObservableObject {
    let persistence = PersistenceController.shared
    let captureRepository: CaptureRepository
    let dictionaryRepository: DictionaryRepository
    let snippetRepository: SnippetRepository
    let styleRepository: SwiftDataStyleRepository
    let noteRepository: NoteRepository
    let settingsRepository: SettingsRepository

    private let whisperModelManager = WhisperModelManager()
    private let whisperServerManager = WhisperServerManager()
    private let localWhisperClient = LocalWhisperClient()

    let coordinator: CaptureCoordinator
    private let insertionService: TextInsertionServicing

    lazy var homeViewModel = HomeViewModel(
        captureRepository: captureRepository,
        noteRepository: noteRepository,
        coordinator: coordinator,
        settingsRepository: settingsRepository
    )
    lazy var dictionaryViewModel = DictionaryViewModel(dictionaryRepository: dictionaryRepository, settingsRepository: settingsRepository)
    lazy var snippetsViewModel = SnippetsViewModel(snippetRepository: snippetRepository, settingsRepository: settingsRepository)
    lazy var styleViewModel = StyleViewModel(styleRepository: styleRepository)
    lazy var notesViewModel = NotesViewModel(noteRepository: noteRepository)
    lazy var settingsViewModel = SettingsViewModel(settingsRepository: settingsRepository, keyStore: OpenAIKeyStore())

    @Published var activeSection: SidebarSection = .home

    init() {
        self.captureRepository = SwiftDataCaptureRepository(context: persistence.modelContext)
        self.dictionaryRepository = SwiftDataDictionaryRepository(context: persistence.modelContext)
        self.snippetRepository = SwiftDataSnippetRepository(context: persistence.modelContext)
        self.styleRepository = SwiftDataStyleRepository(context: persistence.modelContext)
        self.noteRepository = SwiftDataNoteRepository(context: persistence.modelContext)
        self.settingsRepository = SwiftDataSettingsRepository(context: persistence.modelContext)

        styleRepository.ensureDefaults()

        let insertionService = TextInsertionService()
        self.insertionService = insertionService
        insertionService.requestAccessibilityIfNeeded()

        self.coordinator = CaptureCoordinator(
            insertionService: insertionService,
            hotkeyMonitor: FunctionKeyMonitor(),
            overlay: OverlayController(),
            formattingPipeline: FormattingPipeline(),
            captureRepository: captureRepository,
            dictionaryRepository: dictionaryRepository,
            snippetRepository: snippetRepository,
            styleRepository: styleRepository,
            noteRepository: noteRepository,
            settingsRepository: settingsRepository,
            keyStore: OpenAIKeyStore(),
            whisperModelManager: whisperModelManager,
            whisperServerManager: whisperServerManager,
            localWhisperClient: localWhisperClient
        )
    }

    func startRuntimeServices() {
        requestPermissions()
        coordinator.startListeningMonitoring()
        coordinator.startLocalWhisperServerIfNeeded()
    }

    func stopRuntimeServices() {
        coordinator.stopListeningMonitoring()
        coordinator.stopLocalWhisperServer()
    }

    private func requestPermissions() {
        insertionService.requestAccessibilityIfNeeded()
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
}
