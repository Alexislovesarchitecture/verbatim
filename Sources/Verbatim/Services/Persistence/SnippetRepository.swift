import Foundation
import SwiftData

@MainActor
final class SwiftDataSnippetRepository: SnippetRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all(scope: SnippetScope?) -> [SnippetEntry] {
        applyFilters(query: nil, scope: scope)
    }

    func search(_ query: String, scope: SnippetScope?) -> [SnippetEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return all(scope: scope) }
        return applyFilters(query: trimmed.lowercased(), scope: scope)
    }

    func add(_ entry: SnippetEntry) {
        context.insert(entry)
        save()
    }

    func update(_ entry: SnippetEntry) {
        entry.updatedAt = .now
        save()
    }

    func delete(_ entry: SnippetEntry) {
        context.delete(entry)
        save()
    }

    private func applyFilters(query: String?, scope: SnippetScope?) -> [SnippetEntry] {
        let predicate: Predicate<SnippetEntry>?
        if let scope {
            predicate = #Predicate<SnippetEntry> { $0.scope == scope }
        } else {
            predicate = nil
        }

        let descriptor = FetchDescriptor<SnippetEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []

        guard let query, !query.isEmpty else {
            return all
        }

        return all.filter {
            $0.trigger.lowercased().contains(query) || $0.content.lowercased().contains(query)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save snippet entry: \(error)")
        }
    }
}
