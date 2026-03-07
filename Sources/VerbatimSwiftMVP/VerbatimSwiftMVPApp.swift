import SwiftUI

@main
struct VerbatimSwiftMVPApp: App {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(viewModel.appearanceMode.preferredColorScheme)
                .applyWindowChrome()
                .frame(minWidth: 1024, minHeight: 720)
        }
#if os(macOS)
        .defaultSize(width: 1260, height: 860)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
#endif

#if os(macOS)
        Settings {
            SettingsWindowView()
                .environmentObject(viewModel)
                .preferredColorScheme(viewModel.appearanceMode.preferredColorScheme)
                .applyWindowChrome()
                .frame(minWidth: 940, minHeight: 700)
        }
        .defaultSize(width: 980, height: 740)
        .windowResizability(.contentMinSize)
#endif
    }
}
