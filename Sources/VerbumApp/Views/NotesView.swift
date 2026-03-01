import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var controller: VerbumController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Notes")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add new") {
                    controller.addNote()
                }
                .buttonStyle(.borderedProminent)
            }

            List {
                ForEach($controller.notes) { $note in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Title", text: $note.title)
                            .font(.headline)
                        TextEditor(text: $note.body)
                            .frame(minHeight: 120)
                        Text(DateFormatter.verbumDate.string(from: note.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: controller.notes) { _, _ in
                controller.persistNotes()
            }
        }
    }
}
