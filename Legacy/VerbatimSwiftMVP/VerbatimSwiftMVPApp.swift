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
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else {
            return
        }

        ensureWindowIsVisible(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindowIsVisible(_ window: NSWindow) {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if visibleFrames.contains(where: { $0.intersects(window.frame) }) {
            return
        }

        let fallbackFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        guard let fallbackFrame else { return }

        var nextFrame = window.frame
        nextFrame.size.width = min(nextFrame.width, fallbackFrame.width)
        nextFrame.size.height = min(nextFrame.height, fallbackFrame.height)
        nextFrame.origin.x = fallbackFrame.origin.x + max(0, (fallbackFrame.width - nextFrame.width) / 2)
        nextFrame.origin.y = fallbackFrame.origin.y + max(0, (fallbackFrame.height - nextFrame.height) / 2)
        window.setFrame(nextFrame, display: true)
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
                .task {
                    viewModel.prepareApplicationPermissions()
                }
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
