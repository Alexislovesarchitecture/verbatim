import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var store: VerbumStore
    @State private var phrase = ""
    @State private var replacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Dictionary")
                    .font(.largeTitle.weight(.bold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Verbum speaks the way you speak.")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                Text("Add personal words, client names, jargon, abbreviations, and common corrections. These terms are used for prompt bias and post-format cleanup.")
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Phrase", text: $phrase)
                    TextField("Replacement (optional)", text: $replacement)
                    Button("Add") {
                        store.addDictionaryEntry(phrase: phrase, replacement: replacement.isEmpty ? nil : replacement)
                        phrase = ""
                        replacement = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(22)
            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            List {
                ForEach(store.dictionaryEntries) { entry in
                    HStack {
                        Text(entry.phrase)
                        Spacer()
                        if let replacement = entry.replacement, !replacement.isEmpty {
                            Text("→ \(replacement)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: store.removeDictionaryEntries)
            }
            .listStyle(.inset)
        }
        .padding(32)
    }
}
