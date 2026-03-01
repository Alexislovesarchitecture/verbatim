import SwiftUI

struct DictionaryPage: View {
    @ObservedObject var viewModel: DictionaryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            sectionCard(title: "Dictionary entries") {
                if viewModel.scope == .sharedStub {
                    Text("Shared tab is a local stub in this build.")
                        .foregroundStyle(.secondary)
                }

                Picker("Scope", selection: $viewModel.scope) {
                    ForEach(DictionaryScopeFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.scope) { _, value in
                    viewModel.setScope(value)
                }

                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.refresh()
                    }

                List {
                    ForEach(viewModel.filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.input)
                                    .font(.headline)
                                Spacer()
                                Text(entry.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let output = entry.output, !output.isEmpty {
                                Text(output)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Edit") { viewModel.edit(entry) }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { entry.enabled },
                                    set: { value in
                                        viewModel.setEnabled(entry, enabled: value)
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: viewModel.delete)
                }
                .listStyle(.plain)

                if viewModel.scope != .sharedStub {
                    Button("Add") {
                        viewModel.beginAdd()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Shared editing is stubbed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            sectionCard(title: "Behavior") {
                Toggle("Bias transcription with dictionary terms", isOn: Binding(
                    get: { viewModel.behavior.biasTranscriptionWithDictionary },
                    set: viewModel.setBiasTranscription
                ))
                Toggle("Apply replacements after transcription", isOn: Binding(
                    get: { viewModel.behavior.applyReplacementsAfterTranscription },
                    set: viewModel.setApplyReplacements
                ))
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $viewModel.isShowingEditor) {
            VStack(spacing: 12) {
                Text(viewModel.editingEntry == nil ? "Add term" : "Edit term")
                    .font(.title2.weight(.semibold))

                Picker("Kind", selection: $viewModel.selectedKind) {
                    ForEach(DictionaryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Input", text: $viewModel.input)
                if viewModel.selectedKind != .term {
                    TextField("Output", text: $viewModel.output)
                }

                Toggle("Enabled", isOn: $viewModel.enabled)

                HStack {
                    Button("Cancel") { viewModel.hideEditor() }
                    Button("Save") { viewModel.saveEditor() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dictionary")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text("Terms, replacements, and expansions used by the pipeline.")
                .foregroundStyle(.secondary)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}
