import SwiftUI

struct SnippetsView: View {
    @EnvironmentObject private var store: VerbumStore
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Snippets")
                    .font(.largeTitle.weight(.bold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("The stuff you should not have to re-type.")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                Text("Speak a trigger phrase and Verbum expands it into the full text. Great for links, email blocks, meeting notes, or standard replies.")
                    .foregroundStyle(.secondary)
                TextField("Trigger", text: $trigger)
                TextField("Expansion", text: $expansion, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                Button("Add snippet") {
                    store.addSnippet(trigger: trigger, expansion: expansion)
                    trigger = ""
                    expansion = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            List {
                ForEach(store.snippetEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.trigger)
                            .font(.headline)
                        Text(entry.expansion)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: store.removeSnippets)
            }
            .listStyle(.inset)
        }
        .padding(32)
    }
}
