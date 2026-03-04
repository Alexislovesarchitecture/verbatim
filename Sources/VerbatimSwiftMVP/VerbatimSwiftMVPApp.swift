import SwiftUI

@available(macOS 26.0, *)
@available(iOS 26.0, *)
@main
struct VerbatimSwiftMVPApp: App {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .containerBackground(.regularMaterial, for: .window)
                .frame(minWidth: 760, minHeight: 680)
        }
#if os(macOS)
        .defaultSize(width: 920, height: 760)
        .windowResizability(.contentMinSize)
#endif
    }
}
