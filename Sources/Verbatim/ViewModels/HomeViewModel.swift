import Foundation
import AppKit
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var captures: [CaptureRecord] = []
    @Published var filter: HomeHistoryFilter = .all
    @Published var expandedRecordIds: Set<UUID> = []

    @Published var autoInsertEnabled: Bool = true
    @Published var clipboardFallbackEnabled: Bool = true
    @Published var historyRetentionDays: Int = 30

    private let captureRepository: CaptureRepository
    private let noteRepository: NoteRepository
    private let coordinator: CaptureCoordinator
    private let settingsRepository: SettingsRepository


    init(
        captureRepository: CaptureRepository,
        noteRepository: NoteRepository,
        coordinator: CaptureCoordinator,
        settingsRepository: SettingsRepository
    ) {
        self.captureRepository = captureRepository
        self.noteRepository = noteRepository
        self.coordinator = coordinator
        self.settingsRepository = settingsRepository

        let settings = settingsRepository.settings()
        autoInsertEnabled = settings.autoInsertEnabled
        clipboardFallbackEnabled = settings.clipboardFallbackEnabled
        historyRetentionDays = settings.historyRetentionDays

        refresh()
    }

    var filteredCaptures: [CaptureRecord] {
        let records = captureRepository.filtered(status: filter.status)
        return records
    }

    func refresh() {
        captures = captureRepository.all()
        captures = captureRepository.filtered(status: filter.status)
    }

    func refreshHistory() {
        refresh()
    }

    func saveToNotes(_ record: CaptureRecord) {
        let text = !record.formattedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? record.formattedText : record.rawText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let title = String(text.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        noteRepository.add(NoteEntry(title: title.isEmpty ? "Dictation capture" : title, body: text, sourceCaptureId: record.id))
        refresh()
    }

    func toggleExpanded(_ id: UUID) {
        if expandedRecordIds.contains(id) {
            expandedRecordIds.remove(id)
        } else {
            expandedRecordIds.insert(id)
        }
    }

    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyLastCapture() {
        coordinator.copyLastCapture()
    }

    func startListening() {
        coordinator.startListening()
    }

    func lockListening() {
        coordinator.lockListening()
    }

    func setAutoInsertEnabled(_ value: Bool) {
        autoInsertEnabled = value
        let settings = settingsRepository.settings()
        settings.autoInsertEnabled = value
        settingsRepository.save(settings: settings)
    }

    func setClipboardFallbackEnabled(_ value: Bool) {
        clipboardFallbackEnabled = value
        let settings = settingsRepository.settings()
        settings.clipboardFallbackEnabled = value
        settingsRepository.save(settings: settings)
    }

    func setHistoryRetentionDays(_ value: Int) {
        historyRetentionDays = value
        let settings = settingsRepository.settings()
        settings.historyRetentionDays = value
        settingsRepository.save(settings: settings)
        refresh()
    }
}
