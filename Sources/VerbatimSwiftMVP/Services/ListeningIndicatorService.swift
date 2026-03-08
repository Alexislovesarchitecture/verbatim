import Foundation
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif

enum ListeningIndicatorOutcome: Sendable, Equatable {
    case inserted
    case copiedOnly(String)
    case noSpeechDetected
    case failed(String)
}

@MainActor
protocol ListeningIndicatorServiceProtocol {
    func showListening()
    func showProcessing()
    func showCompletedBriefly()
    func showOutcome(_ outcome: ListeningIndicatorOutcome)
    func hideListening()
}

@MainActor
final class FloatingListeningIndicatorService: ListeningIndicatorServiceProtocol {
#if canImport(AppKit)
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ListeningIndicatorBubble>?
    private var hideTask: Task<Void, Never>?
#endif

    func showListening() {
#if canImport(AppKit)
        present(stage: .listening)
#endif
    }

    func showProcessing() {
#if canImport(AppKit)
        present(stage: .processing)
#endif
    }

    func showCompletedBriefly() {
#if canImport(AppKit)
        present(stage: .completed())
        scheduleHide(after: 0.55)
#endif
    }

    func showOutcome(_ outcome: ListeningIndicatorOutcome) {
#if canImport(AppKit)
        switch outcome {
        case .inserted:
            present(stage: .completed(message: "Inserted."))
            scheduleHide(after: 0.75)
        case .copiedOnly(let message):
            present(stage: .copiedOnly(message: message))
            scheduleHide(after: 1.35)
        case .noSpeechDetected:
            present(stage: .noSpeechDetected(message: "No speech detected. Nothing sent."))
            scheduleHide(after: 1.1)
        case .failed(let message):
            present(stage: .failed(message: message))
            scheduleHide(after: 1.1)
        }
#endif
    }

    func hideListening() {
#if canImport(AppKit)
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
#endif
    }

#if canImport(AppKit)
    private func present(stage: ListeningIndicatorBubble.Stage) {
        hideTask?.cancel()
        let panel = ensurePanel()
        let bubble = ListeningIndicatorBubble(stage: stage)

        if let hostingView {
            hostingView.rootView = bubble
        } else {
            let hostingView = NSHostingView(rootView: bubble)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hostingView
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            ])
            self.hostingView = hostingView
        }

        position(panel: panel)
        if panel.isVisible == false {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hideListening()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 324, height: 94),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSApp.keyWindow?.screen ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: frame.midX - (size.width / 2),
            y: frame.minY + 34
        )
        panel.setFrameOrigin(origin)
    }
#endif
}

#if canImport(AppKit)
private struct ListeningIndicatorBubble: View {
    let stage: Stage

    enum Stage {
        case listening
        case processing
        case completed(message: String = "Inserted.")
        case copiedOnly(message: String)
        case noSpeechDetected(message: String)
        case failed(message: String)

        var iconName: String {
            switch self {
            case .listening:
                return "mic.fill"
            case .processing:
                return "paperplane.fill"
            case .completed:
                return "checkmark"
            case .copiedOnly:
                return "doc.on.clipboard"
            case .noSpeechDetected:
                return "waveform.slash"
            case .failed:
                return "exclamationmark.triangle.fill"
            }
        }

        var accent: Color {
            switch self {
            case .listening:
                return Color(red: 0.30, green: 0.90, blue: 1.00)
            case .processing:
                return Color(red: 0.58, green: 0.50, blue: 1.00)
            case .completed:
                return Color(red: 0.32, green: 0.88, blue: 0.58)
            case .copiedOnly:
                return Color(red: 0.98, green: 0.78, blue: 0.30)
            case .noSpeechDetected:
                return Color(red: 0.86, green: 0.70, blue: 0.34)
            case .failed:
                return Color(red: 1.00, green: 0.43, blue: 0.38)
            }
        }

        var glow: Color {
            accent.opacity(isCompletedStyle ? 0.38 : 0.28)
        }

        var glassTint: Color {
            switch self {
            case .listening:
                return Color(red: 0.28, green: 0.42, blue: 0.76)
            case .processing:
                return Color(red: 0.35, green: 0.28, blue: 0.74)
            case .completed:
                return Color(red: 0.18, green: 0.42, blue: 0.32)
            case .copiedOnly:
                return Color(red: 0.56, green: 0.39, blue: 0.08)
            case .noSpeechDetected:
                return Color(red: 0.50, green: 0.36, blue: 0.10)
            case .failed:
                return Color(red: 0.55, green: 0.14, blue: 0.16)
            }
        }

        var surfaceColors: [Color] {
            switch self {
            case .listening:
                return [
                    Color.white.opacity(0.16),
                    Color(red: 0.15, green: 0.20, blue: 0.31).opacity(0.88),
                    Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            case .processing:
                return [
                    Color.white.opacity(0.14),
                    Color(red: 0.18, green: 0.14, blue: 0.34).opacity(0.90),
                    Color(red: 0.06, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            case .completed:
                return [
                    Color.white.opacity(0.15),
                    Color(red: 0.11, green: 0.20, blue: 0.18).opacity(0.90),
                    Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            case .copiedOnly:
                return [
                    Color.white.opacity(0.15),
                    Color(red: 0.27, green: 0.20, blue: 0.06).opacity(0.92),
                    Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            case .noSpeechDetected:
                return [
                    Color.white.opacity(0.13),
                    Color(red: 0.22, green: 0.18, blue: 0.08).opacity(0.92),
                    Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            case .failed:
                return [
                    Color.white.opacity(0.14),
                    Color(red: 0.26, green: 0.10, blue: 0.12).opacity(0.92),
                    Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.94),
                ]
            }
        }

        var title: String {
            switch self {
            case .listening:
                return "Listening"
            case .processing:
                return "Transcribing"
            case .completed:
                return "Inserted"
            case .copiedOnly:
                return "Clipboard Ready"
            case .noSpeechDetected:
                return "No Speech"
            case .failed:
                return "Recovery Needed"
            }
        }

        var detail: String? {
            switch self {
            case .listening:
                return nil
            case .processing:
                return nil
            case .completed(let message),
                 .copiedOnly(let message),
                 .noSpeechDetected(let message),
                 .failed(let message):
                return message
            }
        }

        var isCompletedStyle: Bool {
            if case .completed = self {
                return true
            }
            return false
        }
    }

    var body: some View {
        VerbatimGlassGroup(spacing: 10) {
            HStack(spacing: 12) {
                ListeningIndicatorSideMotion(stage: stage, reverse: false)
                ListeningIndicatorOrb(stage: stage)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stage.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))

                    if let detail = stage.detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 292, height: 72)
            .background(bubbleSurface)
            .padding(8)
        }
    }

    @ViewBuilder
    private var bubbleSurface: some View {
        let shape = Capsule(style: .continuous)

        if #available(macOS 26.0, iOS 26.0, *) {
            shape
                .fill(
                    LinearGradient(
                        colors: stage.surfaceColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape
                        .strokeBorder(.white.opacity(stage.isCompletedStyle ? 0.22 : 0.16), lineWidth: 1)
                )
                .overlay(alignment: .bottom) {
                    Capsule(style: .continuous)
                        .fill(stage.glow)
                        .frame(width: 120, height: 10)
                        .blur(radius: 14)
                        .offset(y: 10)
                }
                .glassEffect(.regular.tint(stage.glassTint.opacity(0.26)), in: .capsule)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        } else {
            shape
                .fill(
                    LinearGradient(
                        colors: stage.surfaceColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: stage.glow, radius: 18, y: 10)
        }
    }
}

private struct ListeningIndicatorOrb: View {
    let stage: ListeningIndicatorBubble.Stage

    var body: some View {
        let shape = Circle()

        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                shape
                    .fill(.white.opacity(0.08))
                    .glassEffect(.regular.tint(stage.accent.opacity(0.22)), in: .circle)
            } else {
                shape
                    .fill(.white.opacity(0.12))
            }

            shape
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)

            Image(systemName: stage.iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
        }
        .frame(width: 34, height: 34)
        .shadow(color: stage.glow, radius: stage.isCompletedStyle ? 14 : 10, y: 0)
    }
}

private struct ListeningIndicatorSideMotion: View {
    let stage: ListeningIndicatorBubble.Stage
    let reverse: Bool
    @State private var phase = false

    var body: some View {
        Group {
            switch stage {
            case .listening:
                waveform
            case .processing:
                pulsingDots
            case .completed:
                completionGlow
            case .copiedOnly, .noSpeechDetected, .failed:
                pulsingDots
            }
        }
        .frame(width: 52, height: 24)
        .drawingGroup()
        .onAppear {
            phase = true
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(waveStrides.enumerated()), id: \.offset) { index, stride in
                Capsule(style: .continuous)
                    .fill(accentGradient)
                    .frame(width: 4, height: 6 + stride.height)
                    .scaleEffect(y: phase ? stride.scales.0 : stride.scales.1, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.52)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.07),
                        value: phase
                    )
            }
        }
    }

    private var pulsingDots: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(accentGradient)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase ? 1.0 : 0.55)
                    .opacity(phase ? 0.95 : 0.36)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(reverse ? (2 - index) : index) * 0.10),
                        value: phase
                    )
            }
        }
    }

    private var completionGlow: some View {
        Capsule(style: .continuous)
            .fill(accentGradient)
            .frame(width: 26, height: 4)
            .shadow(color: stage.glow, radius: 8, y: 0)
    }

    private var waveStrides: [(height: CGFloat, scales: (CGFloat, CGFloat))] {
        let values: [(height: CGFloat, scales: (CGFloat, CGFloat))] = [
            (4, (1.00, 0.40)),
            (8, (1.00, 0.72)),
            (12, (1.00, 0.32)),
            (7, (1.00, 0.86)),
            (5, (1.00, 0.52)),
        ]
        return reverse ? values.reversed() : values
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                stage.accent.opacity(0.98),
                stage.accent.opacity(0.60),
            ],
            startPoint: reverse ? .trailing : .leading,
            endPoint: reverse ? .leading : .trailing
        )
    }
}
#endif
