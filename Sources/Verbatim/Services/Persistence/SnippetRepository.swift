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
            if let query, !query.isEmpty {
                predicate = #Predicate<SnippetEntry> {
                    $0.scope == scope && ($0.trigger.lowercased().contains(query) || $0.content.lowercased().contains(query))
                }
            } else {
                predicate = #Predicate<SnippetEntry> { $0.scope == scope }
            }
        } else if let query, !query.isEmpty {
            predicate = #Predicate<SnippetEntry> {
                $0.trigger.lowercased().contains(query) || $0.content.lowercased().contains(query)
            }
        } else {
            predicate = nil
        }

        let descriptor = FetchDescriptor<SnippetEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save snippet entry: \(error)")
        }
    }
}
