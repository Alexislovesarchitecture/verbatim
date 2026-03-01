import SwiftUI

struct ShellRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(SidebarSection.allCases) { section in
                    Button {
                        appState.activeSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.symbolName)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .listRowBackground(appState.activeSection == section ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .listStyle(.plain)
            .frame(minWidth: 190)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [Color(NSColor.windowBackgroundColor), Color(NSColor.controlBackgroundColor).opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                contentView
                    .padding(26)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.activeSection {
        case .home:
            HomePage(viewModel: appState.homeViewModel)
        case .dictionary:
            DictionaryPage(viewModel: appState.dictionaryViewModel)
        case .snippets:
            SnippetsPage(viewModel: appState.snippetsViewModel)
        case .style:
            StylePage(viewModel: appState.styleViewModel)
        case .notes:
            NotesPage(viewModel: appState.notesViewModel)
        case .settings:
            SettingsPage(viewModel: appState.settingsViewModel)
        }
    }
}
