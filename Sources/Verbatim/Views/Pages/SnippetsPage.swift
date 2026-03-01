import SwiftUI

struct SnippetsPage: View {
    @ObservedObject var viewModel: SnippetsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snippets")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Expand trigger phrases into reusable content.")
                    .foregroundStyle(.secondary)
            }

            sectionCard(title: "Entries") {
                Picker("Scope", selection: $viewModel.scope) {
                    ForEach(SnippetScopeFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.scope) { _, value in
                    viewModel.setScope(value)
                }

                TextField("Search", text: $viewModel.searchText)
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.refresh()
                    }

                if viewModel.scope == .sharedStub {
                    Text("Shared tab is a local stub in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(viewModel.filteredSnippets) { snippet in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(snippet.trigger)
                                    .font(.headline)
                                Spacer()
                                Text(snippet.requireExactMatch ? "Exact" : "Contains")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(snippet.content)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack {
                                Button("Edit") { viewModel.edit(snippet) }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { snippet.enabled },
                                    set: { value in
                                        viewModel.setEnabled(snippet, enabled: value)
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
                    Button("Add") { viewModel.beginAdd() }
                        .buttonStyle(.borderedProminent)
                }
            }

            sectionCard(title: "Behavior") {
                Toggle("Enable snippet expansion", isOn: Binding(
                    get: { viewModel.behavior.enableSnippetExpansion },
                    set: viewModel.setSnippetExpansionEnabled
                ))
                Toggle("Require exact trigger match", isOn: Binding(
                    get: { viewModel.behavior.globalRequireExactMatch },
                    set: viewModel.setSnippetGlobalRequireExact
                ))
            }

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $viewModel.isShowingEditor) {
            VStack(spacing: 12) {
                Text(viewModel.editingSnippet == nil ? "Add snippet" : "Edit snippet")
                    .font(.title2.weight(.semibold))

                TextField("Trigger", text: $viewModel.trigger)
                TextField("Content", text: $viewModel.content)

                Toggle("Require exact match", isOn: $viewModel.requireExactMatch)
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
