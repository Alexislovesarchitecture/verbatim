import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: VerbatimStore

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $store.activeSection) { section in
                Label(section.rawValue, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                switch store.activeSection ?? .home {
                case .home:
                    HomeView()
                case .dictionary:
                    DictionaryView()
                case .snippets:
                    SnippetsView()
                case .style:
                    StyleView()
                case .notes:
                    NotesView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }
}
