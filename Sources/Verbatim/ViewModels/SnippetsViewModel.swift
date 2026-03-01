import Foundation

enum SnippetScopeFilter: String, CaseIterable, Identifiable {
    case all
    case personal
    case sharedStub

    var id: String { rawValue }

    var repositoryScope: SnippetScope? {
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
final class SnippetsViewModel: ObservableObject {
    @Published private(set) var snippets: [SnippetEntry] = []
    @Published var scope: SnippetScopeFilter = .all
    @Published var searchText: String = ""
    @Published var editingSnippet: SnippetEntry?

    @Published var trigger = ""
    @Published var content = ""
    @Published var enabled = true
    @Published var requireExactMatch = false
    @Published var isShowingEditor = false

    private let snippetRepository: SnippetRepository
    private let settingsRepository: SettingsRepository

    init(snippetRepository: SnippetRepository, settingsRepository: SettingsRepository) {
        self.snippetRepository = snippetRepository
        self.settingsRepository = settingsRepository
        refresh()
    }

    var behavior: LocalBehaviorSettings {
        settingsRepository.behaviorSettings()
    }

    var filteredSnippets: [SnippetEntry] {
        if searchText.isEmpty {
            return snippets
        }
        return snippetRepository.search(searchText, scope: scope.repositoryScope)
    }

    func refresh() {
        snippets = snippetRepository.all(scope: scope.repositoryScope)
        if !searchText.isEmpty {
            snippets = snippetRepository.search(searchText, scope: scope.repositoryScope)
        }
    }

    func setScope(_ scope: SnippetScopeFilter) {
        self.scope = scope
        refresh()
    }

    func beginAdd() {
        editingSnippet = nil
        trigger = ""
        content = ""
        requireExactMatch = false
        enabled = true
        isShowingEditor = true
    }

    func edit(_ snippet: SnippetEntry) {
        editingSnippet = snippet
        trigger = snippet.trigger
        content = snippet.content
        requireExactMatch = snippet.requireExactMatch
        enabled = snippet.enabled
        isShowingEditor = true
    }

    func saveEditor() {
        let cleanedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTrigger.isEmpty, !cleanedContent.isEmpty else { return }

        if let existing = editingSnippet {
            existing.trigger = cleanedTrigger
            existing.content = cleanedContent
            existing.requireExactMatch = requireExactMatch
            existing.enabled = enabled
            existing.updatedAt = .now
            snippetRepository.update(existing)
        } else {
            let entry = SnippetEntry(
                scope: scope.repositoryScope ?? .personal,
                trigger: cleanedTrigger,
                content: cleanedContent,
                requireExactMatch: requireExactMatch,
                enabled: enabled,
                createdAt: .now,
                updatedAt: .now
            )
            snippetRepository.add(entry)
        }

        isShowingEditor = false
        editingSnippet = nil
        refresh()
    }

    func hideEditor() {
        editingSnippet = nil
        isShowingEditor = false
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.reversed() {
            if index < filteredSnippets.count {
                snippetRepository.delete(filteredSnippets[index])
            }
        }
        refresh()
    }

    func setEnabled(_ snippet: SnippetEntry, enabled: Bool) {
        snippet.enabled = enabled
        snippetRepository.update(snippet)
        refresh()
    }

    func setSnippetExpansionEnabled(_ enabled: Bool) {
        behavior.enableSnippetExpansion = enabled
        settingsRepository.save(behavior: behavior)
    }

    func setSnippetGlobalRequireExact(_ enabled: Bool) {
        behavior.globalRequireExactMatch = enabled
        settingsRepository.save(behavior: behavior)
    }
}
