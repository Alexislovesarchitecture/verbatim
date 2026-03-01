import SwiftUI

@main
struct VerbatimApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Verbatim") {
            ShellRootView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 760)
                .onAppear { appState.startRuntimeServices() }
                .onDisappear { appState.stopRuntimeServices() }
        }

        MenuBarExtra("Verbatim", systemImage: appState.coordinator.uiState.icon) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture")
                    .font(.headline)
                Button("Start listening") {
                    appState.coordinator.startListening()
                }
                Button("Lock listening") {
                    appState.coordinator.lockListening()
                }
                Button("Stop listening") {
                    appState.coordinator.stopListening()
                }
                Button("Copy last capture") {
                    appState.coordinator.copyLastCapture()
                }
                Divider()
                Button("Open Verbatim") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 220)
        }
    }
}
