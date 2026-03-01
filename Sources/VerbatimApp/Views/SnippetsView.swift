import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Snippets")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add new") {
                    controller.addSnippet()
                }
                .buttonStyle(.borderedProminent)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The stuff you should not have to retype")
                        .font(.title2)
                    Text("Speak a trigger phrase and Verbatim expands it instantly. Keep this deterministic at first. Static snippets give you most of the value before you add variables or AI transforms.")
                        .foregroundStyle(.secondary)
                }
            }

            Table(controller.snippets) {
                TableColumn("Trigger") { snippet in
                    TextField("Trigger", text: binding(for: snippet).trigger)
                }
                TableColumn("Expansion") { snippet in
                    TextField("Expansion", text: binding(for: snippet).expansion)
                }
            }
            .onChange(of: controller.snippets) { _, _ in
                controller.persistSnippets()
            }
        }
    }

    private func binding(for snippet: SnippetEntry) -> Binding<SnippetEntry> {
        guard let index = controller.snippets.firstIndex(where: { $0.id == snippet.id }) else {
            fatalError("Snippet missing")
        }
        return $controller.snippets[index]
    }
}
