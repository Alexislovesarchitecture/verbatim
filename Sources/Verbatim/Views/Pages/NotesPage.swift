import SwiftUI

struct NotesPage: View {
    @ObservedObject var viewModel: NotesViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(title: "Notes") {
                    Button("New note") {
                        viewModel.beginCreate()
                    }
                    .buttonStyle(.borderedProminent)

                    List {
                        ForEach(viewModel.notes) { note in
                            Button {
                                viewModel.beginEdit(note)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.headline)
                                    Text(verbatimDateFormatter.string(from: note.updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(note.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: viewModel.delete)
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 320)
                }
            }

            sectionCard(title: viewModel.editingNote == nil ? "Create note" : "Edit note") {
                TextField("Title", text: $viewModel.title)
                TextField("Body", text: $viewModel.body, axis: .vertical)
                    .lineLimit(10, reservesSpace: true)
                Button(viewModel.editingNote == nil ? "Save" : "Update") {
                    viewModel.save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear { viewModel.refresh() }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}
