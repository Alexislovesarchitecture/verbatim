import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var controller: VerbumController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Dictionary")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add new") {
                    controller.addDictionaryEntry()
                }
                .buttonStyle(.borderedProminent)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Flow-like accuracy, but local-first")
                        .font(.title2)
                    Text("Store names, jargon, replacements, and common fixes here. Verbum feeds them into formatting and, when you use OpenAI mode, into transcription hints.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        chip("Verbum")
                        chip("open-wispr")
                        chip("FreeFlow")
                        chip("project name")
                    }
                }
            }

            Table(controller.dictionaryEntries) {
                TableColumn("Spoken / detected") { entry in
                    TextField("Source", text: binding(for: entry).source)
                }
                TableColumn("Replace with") { entry in
                    TextField("Replacement", text: binding(for: entry).replacement)
                }
                TableColumn("Type") { entry in
                    Text(entry.learnedAutomatically ? "Learned" : "Manual")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: controller.dictionaryEntries) { _, _ in
                controller.persistDictionary()
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func binding(for entry: DictionaryEntry) -> Binding<DictionaryEntry> {
        guard let index = controller.dictionaryEntries.firstIndex(where: { $0.id == entry.id }) else {
            fatalError("Dictionary entry missing")
        }
        return $controller.dictionaryEntries[index]
    }
}
