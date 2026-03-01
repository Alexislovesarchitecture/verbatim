import Foundation
import SwiftData

@MainActor
final class SwiftDataNoteRepository: NoteRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [NoteEntry] {
        let descriptor = FetchDescriptor<NoteEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func add(_ note: NoteEntry) {
        context.insert(note)
        save()
    }

    func update(_ note: NoteEntry) {
        note.updatedAt = .now
        save()
    }

    func delete(_ note: NoteEntry) {
        context.delete(note)
        save()
    }

    func find(_ id: UUID) -> NoteEntry? {
        let descriptor = FetchDescriptor<NoteEntry>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save note: \(error)")
        }
    }
}
