import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
final class VerbatimApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
#endif

@main
struct VerbatimSwiftMVPApp: App {
#if canImport(AppKit)
    @NSApplicationDelegateAdaptor(VerbatimApplicationDelegate.self) private var applicationDelegate
#endif
    @StateObject private var viewModel: TranscriptionViewModel

    init() {
        _ = WhisperKitManagedHelperRunner.runIfNeeded(arguments: CommandLine.arguments)
        _viewModel = StateObject(wrappedValue: TranscriptionViewModel())
    }

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
