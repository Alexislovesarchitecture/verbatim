import Foundation

enum DictionaryScopeFilter: String, CaseIterable, Identifiable {
    case all
    case personal
    case sharedStub

    var id: String { rawValue }

    var repositoryScope: DictionaryScope? {
        switch self {
        case .all: return nil
        case .personal: return .personal
        case .sharedStub: return .sharedStub
        }
    }

    var title: String {
        switch self {
        case .all: return "All"
        case .personal: return "Personal"
        case .sharedStub: return "Shared"
        }
    }
}

@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []
    @Published var scope: DictionaryScopeFilter = .all
    @Published var searchText: String = ""
    @Published var editingEntry: DictionaryEntry?
    @Published var isShowingEditor = false

    @Published var input = ""
    @Published var output = ""
    @Published var selectedKind: DictionaryKind = .replacement
    @Published var enabled = true

    private let dictionaryRepository: DictionaryRepository
    private let settingsRepository: SettingsRepository

    init(dictionaryRepository: DictionaryRepository, settingsRepository: SettingsRepository) {
        self.dictionaryRepository = dictionaryRepository
        self.settingsRepository = settingsRepository
        refresh()
    }

    var behavior: LocalBehaviorSettings {
        settingsRepository.behaviorSettings()
    }

    var filteredEntries: [DictionaryEntry] {
        if searchText.isEmpty {
            return entries
        }
        return dictionaryRepository.search(searchText, scope: scope.repositoryScope)
    }

    func refresh() {
        entries = dictionaryRepository.all(scope: scope.repositoryScope)
        if !searchText.isEmpty {
            entries = dictionaryRepository.search(searchText, scope: scope.repositoryScope)
        }
    }

    func setScope(_ scope: DictionaryScopeFilter) {
        self.scope = scope
        refresh()
    }

    func beginAdd() {
        input = ""
        output = ""
        selectedKind = .replacement
        enabled = true
        editingEntry = nil
        isShowingEditor = true
    }

    func edit(_ entry: DictionaryEntry) {
        editingEntry = entry
        input = entry.input
        output = entry.output ?? ""
        selectedKind = entry.kind
        enabled = entry.enabled
        isShowingEditor = true
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.reversed() {
            if index < filteredEntries.count {
                dictionaryRepository.delete(filteredEntries[index])
            }
        }
        refresh()
    }

    func saveEditor() {
        let cleanedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty else { return }

        if let existing = editingEntry {
            existing.input = cleanedInput
            existing.output = selectedKind == .term ? nil : cleanedOutput
            existing.kind = selectedKind
            existing.enabled = enabled
            existing.updatedAt = .now
            dictionaryRepository.update(existing)
        } else {
            let entry = DictionaryEntry(
                scope: scope.repositoryScope ?? .personal,
                kind: selectedKind,
                input: cleanedInput,
                output: selectedKind == .term ? nil : cleanedOutput,
                enabled: enabled,
                createdAt: .now,
                updatedAt: .now
            )
            dictionaryRepository.add(entry)
        }

        isShowingEditor = false
        editingEntry = nil
        refresh()
    }

    func hideEditor() {
        editingEntry = nil
        isShowingEditor = false
    }

    func setEnabled(_ entry: DictionaryEntry, enabled: Bool) {
        entry.enabled = enabled
        dictionaryRepository.update(entry)
        refresh()
    }

    func setBiasTranscription(enabled: Bool) {
        behavior.biasTranscriptionWithDictionary = enabled
        settingsRepository.save(behavior: behavior)
    }

    func setApplyReplacements(enabled: Bool) {
        behavior.applyReplacementsAfterTranscription = enabled
        settingsRepository.save(behavior: behavior)
    }
}
