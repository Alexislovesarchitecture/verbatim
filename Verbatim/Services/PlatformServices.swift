import AVFoundation
import ApplicationServices
import Carbon
#if canImport(Combine)
import Combine
#endif
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

private var verbatimHotkeyCallback: (() -> Void)?

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var microphoneAuthorized = false
    @Published private(set) var accessibilityAuthorized = false

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAuthorized = AXIsProcessTrusted()
    }

    func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAuthorized = true
            return true
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            microphoneAuthorized = granted
            return granted
        default:
            microphoneAuthorized = false
            return false
        }
    }

    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        accessibilityAuthorized = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

final class PasteService: PasteServiceProtocol, @unchecked Sendable {
    func captureTarget() -> PasteTarget? {
#if canImport(AppKit)
        let app = NSWorkspace.shared.frontmostApplication
        return PasteTarget(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            processIdentifier: app?.processIdentifier
        )
#else
        return nil
#endif
    }

    func paste(
        text: String,
        to target: PasteTarget?,
        pasteMode: PasteMode,
        accessibilityGranted: Bool
    ) -> PasteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failed("Nothing to insert.")
        }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(trimmed, forType: .string) else {
            return .failed("Could not copy text to the clipboard.")
        }

        guard pasteMode == .autoPaste else {
            return .copiedOnly("Copied to clipboard.")
        }

        guard accessibilityGranted else {
            return .copiedOnly("Copied to clipboard. Enable Accessibility for auto-paste.")
        }

        if let target, restore(target: target) == false {
            return .copiedOnly("Copied to clipboard. The target app could not be restored.")
        }

        guard performPasteEvent() else {
            return .copiedOnly("Copied to clipboard. Paste manually in the target app.")
        }

        return .pasted
    }

    private func restore(target: PasteTarget) -> Bool {
        guard let pid = target.processIdentifier, pid > 0,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        if app.isActive { return true }
        let didActivate = app.activate(options: [.activateAllWindows])
        Thread.sleep(forTimeInterval: 0.12)
        return didActivate
    }

    private func performPasteEvent() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayBubbleView>?
    private var hideTask: Task<Void, Never>?

    func update(_ status: OverlayStatus) {
        guard status != .idle else {
            hide()
            return
        }

        let panel = ensurePanel()
        let bubble = OverlayBubbleView(status: status)
        if let hostingView {
            hostingView.rootView = bubble
        } else {
            let hostingView = NSHostingView(rootView: bubble)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = hostingView
            if let contentView = panel.contentView {
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                ])
            }
            self.hostingView = hostingView
        }

        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        switch status {
        case .success, .error:
            scheduleHide(after: 1.0)
        case .recording, .processing, .idle:
            hideTask?.cancel()
        }
    }

    func hide() {
        hideTask?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.hide()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 36
        )
        panel.setFrameOrigin(origin)
    }
}

struct OverlayBubbleView: View {
    let status: OverlayStatus

    private var accent: Color {
        switch status {
        case .recording: return AppSectionAccent.cobalt.tint
        case .processing: return AppSectionAccent.violet.tint
        case .success: return AppSectionAccent.mint.tint
        case .error: return Color(red: 0.92, green: 0.35, blue: 0.30)
        case .idle: return .secondary
        }
    }

    private var title: String {
        switch status {
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .success(let message): return message
        case .error(let message): return message
        case .idle: return ""
        }
    }

    private var symbol: String {
        switch status {
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        case .success: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "circle"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Verbatim")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VerbatimPalette.mutedInk)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(VerbatimPalette.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .applyLiquidCardStyle(cornerRadius: 28, tone: .shell, padding: 18)
        .frame(width: 320, height: 90)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let openItem = NSMenuItem(title: "Open Verbatim", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Start Dictation", action: nil, keyEquivalent: "")
    private let providerItem = NSMenuItem(title: "Provider: --", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")

    var onOpen: (() -> Void)?
    var onToggle: (() -> Void)?

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = VerbatimBrandAssets.nsImage(for: .menuGlyph)
            button.image?.isTemplate = true
            button.toolTip = "Verbatim"
        }

        openItem.target = self
        openItem.action = #selector(openApp)
        toggleItem.target = self
        toggleItem.action = #selector(toggleDictation)
        quitItem.target = self
        quitItem.action = #selector(quitApp)
        providerItem.isEnabled = false

        menu.addItem(openItem)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(providerItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func setVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }

    func update(state: OverlayStatus, providerName: String) {
        providerItem.title = "Provider: \(providerName)"
        switch state {
        case .recording:
            toggleItem.title = "Stop Dictation"
        case .processing:
            toggleItem.title = "Processing..."
        case .idle, .success, .error:
            toggleItem.title = "Start Dictation"
        }
        toggleItem.isEnabled = state != .processing
    }

    @objc private func openApp() {
        onOpen?()
    }

    @objc private func toggleDictation() {
        onToggle?()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    func register(shortcut: KeyboardShortcut, onTrigger: @escaping () -> Void) {
        unregister()
        guard shortcut.isEmpty == false else { return }
        self.onTrigger = onTrigger
        verbatimHotkeyCallback = onTrigger

        let hotKeyID = EventHotKeyID(signature: OSType(0x56524254), id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    verbatimHotkeyCallback?()
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKeyRef = nil
        eventHandler = nil
        onTrigger = nil
        verbatimHotkeyCallback = nil
    }
}

extension KeyboardShortcut {
    var displayTitle: String {
        let modifiersTitle = KeyboardShortcut.displayTitle(forModifiers: modifiers)
        let keyTitle = KeyboardShortcut.displayTitle(forKeyCode: keyCode)
        return modifiersTitle + keyTitle
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty == false else { return nil }
        return KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: carbonFlags(from: modifiers))
    }

    static func carbonFlags(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static func displayTitle(forModifiers modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts
    }

    private static func displayTitle(forKeyCode keyCode: UInt32) -> String {
        let table: [UInt32: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Escape",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z"
        ]
        return table[keyCode] ?? "Key \(keyCode)"
    }
}
