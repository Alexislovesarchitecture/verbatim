import Foundation
import SwiftData

@MainActor
final class SwiftDataDictionaryRepository: DictionaryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all(scope: DictionaryScope?) -> [DictionaryEntry] {
        applyFilters(query: nil, scope: scope)
    }

    func search(_ query: String, scope: DictionaryScope?) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return all(scope: scope) }
        return applyFilters(query: trimmed.lowercased(), scope: scope)
    }

    func add(_ entry: DictionaryEntry) {
        context.insert(entry)
        save()
    }

    func update(_ entry: DictionaryEntry) {
        entry.updatedAt = .now
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        context.delete(entry)
        save()
    }

    private func applyFilters(query: String?, scope: DictionaryScope?) -> [DictionaryEntry] {
        let predicate: Predicate<DictionaryEntry>?
        if let scope {
            if let query, !query.isEmpty {
                predicate = #Predicate<DictionaryEntry> {
                    $0.scope == scope && ($0.input.lowercased().contains(query) || ($0.output?.lowercased().contains(query) ?? false))
                }
            } else {
                predicate = #Predicate<DictionaryEntry> { $0.scope == scope }
            }
        } else if let query, !query.isEmpty {
            predicate = #Predicate<DictionaryEntry> {
                $0.input.lowercased().contains(query) || ($0.output?.lowercased().contains(query) ?? false)
            }
        } else {
            predicate = nil
        }

        let descriptor = FetchDescriptor<DictionaryEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save dictionary entry: \(error)")
        }
    }
}
