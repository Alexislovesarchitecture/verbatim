import AppKit
import SwiftUI

@main
struct VerbumApp: App {
    @StateObject private var store = VerbumStore()

    var body: some Scene {
        WindowGroup("Verbum") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Label(store.listeningState.title, systemImage: "waveform")
                    .font(.headline)
                Text("Last capture backup is available from the clipboard fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Start listening") { store.startListening(lockMode: false) }
                Button("Lock listening") { store.startListening(lockMode: true) }
                Button("Copy last capture") { store.copyLastCaptureToClipboard() }
                Divider()
                Button("Open Verbum") { store.activeSection = .home }
                Button("Quit Verbum") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
            .frame(width: 280)
        } label: {
            Image(systemName: store.listeningState == .recording || store.listeningState == .recordingLocked ? "waveform.circle.fill" : "waveform.circle")
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 640, height: 520)
        }
    }
}
