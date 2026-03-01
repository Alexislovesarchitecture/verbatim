import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        NavigationSplitView {
            List(SidebarRoute.allCases, selection: $controller.selectedRoute) { route in
                Label(route.title, systemImage: route.systemImage)
                    .tag(route)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            ZStack(alignment: .top) {
                contentView
                    .padding(28)

                if controller.phase == .recordingPush || controller.phase == .recordingLocked || controller.phase == .transcribing || controller.phase == .clipboardReady {
                    ListeningOverlayView()
                        .environmentObject(controller)
                        .padding(.top, 8)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch controller.selectedRoute {
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

struct ListeningOverlayView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if controller.phase == .recordingLocked {
                Button("Stop") {
                    controller.stopLockedRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if controller.phase == .clipboardReady {
                Button("Paste last capture") {
                    controller.pasteLastCapture()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8)
    }

    private var icon: String {
        switch controller.phase {
        case .recordingPush, .recordingLocked: return "mic.fill"
        case .transcribing: return "hourglass"
        case .clipboardReady: return "clipboard.fill"
        default: return "waveform"
        }
    }

    private var title: String {
        switch controller.phase {
        case .recordingPush: return "Listening"
        case .recordingLocked: return "Listening locked"
        case .transcribing: return "Transcribing"
        case .clipboardReady: return "Ready to paste"
        default: return "Verbatim"
        }
    }

    private var subtitle: String {
        switch controller.phase {
        case .recordingPush:
            return "Hold Fn to talk. Release to stop. Tap again quickly to lock."
        case .recordingLocked:
            return "Recording stays on until you press Stop."
        case .transcribing:
            return "Running speech-to-text and formatting."
        case .clipboardReady:
            return "No editable field was detected. Cmd+V will paste the capture."
        default:
            return ""
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var controller: VerbatimController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verbatim")
                .font(.headline)

            Text(statusText)
                .foregroundStyle(.secondary)

            Divider()

            Button("Simulate capture") {
                controller.simulateMockCapture()
            }

            if controller.lastCapture != nil {
                Button("Paste last capture") {
                    controller.pasteLastCapture()
                }
            }

            Divider()

            Button("Open Home") {
                controller.selectedRoute = .home
            }
            Button("Open Settings") {
                controller.selectedRoute = .settings
            }
        }
        .padding(16)
    }

    private var statusText: String {
        switch controller.phase {
        case .idle: return "Idle"
        case .recordingPush: return "Listening"
        case .recordingLocked: return "Listening locked"
        case .transcribing: return "Transcribing"
        case .inserting: return "Inserting"
        case .clipboardReady: return "Clipboard ready"
        case .failed: return controller.errorMessage ?? "Error"
        }
    }
}
