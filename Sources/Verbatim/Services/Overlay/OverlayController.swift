import AppKit
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var state: CaptureUICue = .idle
    @Published var level: Float = 0
    @Published var message: String = ""
    var stopAction: (() -> Void)?
}

@MainActor
final class OverlayController {
    private let viewModel = OverlayViewModel()
    private var panel: NSPanel?

    nonisolated func show(state: CaptureUICue, level: Float, message: String = "", stopAction: (() -> Void)? = nil) {
        Task { @MainActor [weak self] in
            self?.showOnMain(state: state, level: level, message: message, stopAction: stopAction)
        }
    }

    nonisolated func update(state: CaptureUICue, level: Float, message: String = "") {
        Task { @MainActor [weak self] in
            self?.updateOnMain(state: state, level: level, message: message)
        }
    }

    nonisolated func hide() {
        Task { @MainActor [weak self] in
            self?.hideOnMain()
        }
    }

    private func showOnMain(state: CaptureUICue, level: Float, message: String = "", stopAction: (() -> Void)? = nil) {
        if panel == nil {
            panel = buildPanel()
        }

        viewModel.state = state
        viewModel.level = level
        viewModel.message = message
        viewModel.stopAction = stopAction
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func updateOnMain(state: CaptureUICue, level: Float, message: String = "") {
        viewModel.state = state
        viewModel.level = level
        viewModel.message = message
        positionPanel()
    }

    private func hideOnMain() {
        panel?.orderOut(nil)
    }

    private func buildPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 104),
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
        panel.contentView = NSHostingView(rootView: OverlayContentView().environmentObject(viewModel))
        return panel
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 120))
    }
}

private struct OverlayContentView: View {
    @EnvironmentObject var model: OverlayViewModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.state == .recording || model.state == .recordingLocked ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.state.title)
                    .font(.headline)
                ProgressView(value: Double(model.level))
                    .progressViewStyle(.linear)
                    .frame(width: 210)
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
        .padding(14)
        .frame(height: 96)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1))
        )
        .padding(6)
    }

    private var icon: String {
        switch model.state {
        case .idle: return "mic"
        case .recording: return "waveform"
        case .recordingLocked: return "lock.fill"
        case .transcribing: return "ellipsis"
        case .inserting: return "arrow.down.doc"
        case .clipboardReady: return "doc.on.doc"
        case .error: return "exclamationmark.triangle"
        }
    }
}
