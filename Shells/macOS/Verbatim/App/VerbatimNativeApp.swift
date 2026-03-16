import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

final class VerbatimApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct VerbatimNativeApp: App {
    @NSApplicationDelegateAdaptor(VerbatimApplicationDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
                .task {
                    await appModel.prepare()
                }
                .frame(minWidth: 900, minHeight: 720)
                .applyWindowChrome()
        }
        .defaultSize(width: 1260, height: 860)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}
