import SwiftUI

@main
struct VerbumApp: App {
    @StateObject private var controller = VerbumController(
        audioCapture: AudioCaptureService(),
        inserter: TextInsertionService(),
        soundService: SystemSoundService()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear { controller.start() }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Verbum", systemImage: menuBarSymbol) {
            MenuBarView()
                .environmentObject(controller)
                .frame(width: 320)
        }
    }

    private var menuBarSymbol: String {
        switch controller.phase {
        case .idle: return "waveform"
        case .recordingPush, .recordingLocked: return "mic.fill"
        case .transcribing: return "hourglass"
        case .inserting: return "arrow.down.doc.fill"
        case .clipboardReady: return "clipboard.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
