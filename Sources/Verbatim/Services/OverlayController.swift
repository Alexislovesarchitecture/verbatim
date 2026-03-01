import AppKit
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var state: ListeningState = .idle
    @Published var level: Float = 0
    @Published var message: String = ""
    var stopAction: (() -> Void)?
}

@MainActor
final class OverlayController {
    private let viewModel = OverlayViewModel()
    private var panel: NSPanel?

    func show(state: ListeningState, level: Float, message: String = "", stopAction: (() -> Void)? = nil) {
        if panel == nil {
            panel = makePanel()
        }
        viewModel.state = state
        viewModel.level = level
        viewModel.message = message
        viewModel.stopAction = stopAction
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func update(state: ListeningState, level: Float, message: String = "") {
        viewModel.state = state
        viewModel.level = level
        viewModel.message = message
        positionPanel()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 96),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ListeningOverlayView().environmentObject(viewModel))
        return panel
    }

    private func positionPanel() {
        guard let panel,
              let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - (panel.frame.width / 2)
        let y = frame.maxY - 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ListeningOverlayView: View {
    @EnvironmentObject var model: OverlayViewModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.state == .recording || model.state == .recordingLocked ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.state.title)
                    .font(.headline)
                ProgressView(value: Double(model.level))
                    .progressViewStyle(.linear)
                    .frame(width: 180)
                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if model.state == .recordingLocked {
                Button("Stop") {
                    model.stopAction?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))
        )
        .padding(6)
    }

    private var iconName: String {
        switch model.state {
        case .recording, .recordingLocked:
            return "waveform"
        case .transcribing:
            return "ellipsis"
        case .inserting:
            return "cursorarrow.rays"
        case .clipboardReady:
            return "doc.on.clipboard"
        case .error:
            return "exclamationmark.triangle"
        case .idle:
            return "mic"
        }
    }
}
