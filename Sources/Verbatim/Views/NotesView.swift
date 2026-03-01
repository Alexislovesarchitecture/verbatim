import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var store: VerbatimStore
    @State private var title = ""
    @State private var noteBody = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Notes")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $title)
                TextField("Body", text: $noteBody, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                Button("Save note") {
                    store.addNote(title: title, body: noteBody)
                    title = ""
                    noteBody = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            List {
                ForEach(store.noteEntries) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: store.removeNotes)
            }
            .listStyle(.inset)
        }
        .padding(32)
    }
}
