import Foundation

@MainActor
final class NotesViewModel: ObservableObject {
    @Published private(set) var notes: [NoteEntry] = []
    @Published var title = ""
    @Published var body = ""
    @Published var editingNote: NoteEntry?

    private let noteRepository: NoteRepository

    init(noteRepository: NoteRepository) {
        self.noteRepository = noteRepository
        refresh()
    }

    func refresh() {
        notes = noteRepository.all()
    }

    func beginCreate() {
        title = ""
        body = ""
        editingNote = nil
    }

    func beginEdit(_ note: NoteEntry) {
        editingNote = note
        title = note.title
        body = note.body
    }

    func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty else { return }

        if let editing = editingNote {
            editing.title = cleanTitle.isEmpty ? "Untitled" : cleanTitle
            editing.body = cleanBody
            editing.updatedAt = .now
            noteRepository.update(editing)
        } else {
            noteRepository.add(
                NoteEntry(
                    title: cleanTitle.isEmpty ? "Untitled" : cleanTitle,
                    body: cleanBody
                )
            )
        }

        title = ""
        body = ""
        editingNote = nil
        refresh()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.reversed() {
            if index < notes.count {
                noteRepository.delete(notes[index])
            }
        }
        refresh()
    }
}
