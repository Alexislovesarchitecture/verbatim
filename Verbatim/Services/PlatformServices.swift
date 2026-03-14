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
    var onRefresh: (() -> Void)?

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
        onRefresh?()
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
    private let activeContextService: ActiveAppContextServiceProtocol
    private let restoreHandler: ((PasteTarget) -> Bool)?
    private let pasteEventHandler: (() -> Bool)?

    init(
        activeContextService: ActiveAppContextServiceProtocol = ActiveAppContextService(),
        restoreHandler: ((PasteTarget) -> Bool)? = nil,
        pasteEventHandler: (() -> Bool)? = nil
    ) {
        self.activeContextService = activeContextService
        self.restoreHandler = restoreHandler
        self.pasteEventHandler = pasteEventHandler
    }

    func captureTarget() -> PasteTarget? {
#if canImport(AppKit)
        let context = activeContextService.currentContext()
        return PasteTarget(
            appName: context.appName,
            bundleIdentifier: context.bundleID,
            processIdentifier: context.processIdentifier,
            windowTitle: context.windowTitle,
            focusedElementRole: context.focusedElementRole,
            focusedElementSubrole: context.focusedElementSubrole,
            focusedElementTitle: context.focusedElementTitle,
            focusedElementPlaceholder: context.focusedElementPlaceholder,
            focusedElementDescription: context.focusedElementDescription,
            focusedValueSnippet: context.focusedValueSnippet,
            isEditableTextInput: context.isEditableTextInput,
            isSecureTextInput: context.isSecureTextInput
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
    ) -> PasteOperationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return finish(
                result: .failed("Nothing to insert."),
                target: target,
                requestedMode: pasteMode,
                outcome: .failed,
                fallbackReason: .nothingToInsert
            )
        }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(trimmed, forType: .string) else {
            return finish(
                result: .failed("Could not copy text to the clipboard."),
                target: target,
                requestedMode: pasteMode,
                outcome: .failed,
                fallbackReason: .clipboardWriteFailed
            )
        }

        guard pasteMode == .autoPaste else {
            return finish(
                result: .copiedOnly("Copied to clipboard."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .autoPasteDisabled
            )
        }

        guard accessibilityGranted else {
            return finish(
                result: .copiedOnly("Copied to clipboard. Enable Accessibility for auto-paste."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .accessibilityUnavailable
            )
        }

        guard let target else {
            return finish(
                result: .copiedOnly("Copied to clipboard. The target field could not be recovered."),
                target: nil,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .fieldMismatch
            )
        }

        if restore(target: target) == false {
            return finish(
                result: .copiedOnly("Copied to clipboard. The target app could not be restored."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .appRestoreFailed
            )
        }

        let currentContext = activeContextService.currentContext()
        guard currentContext.isEditableTextInput else {
            return finish(
                result: .copiedOnly("Copied to clipboard. The target field is not editable."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .fieldNotEditable
            )
        }

        guard currentContext.isSecureTextInput == false else {
            return finish(
                result: .copiedOnly("Copied to clipboard. The target field is secure."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .fieldSecure
            )
        }

        guard targetMatchesCurrentContext(target: target, current: currentContext) else {
            return finish(
                result: .copiedOnly("Copied to clipboard. The target field no longer matched."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .fieldMismatch
            )
        }

        guard performPasteEvent() else {
            return finish(
                result: .copiedOnly("Copied to clipboard. Paste manually in the target app."),
                target: target,
                requestedMode: pasteMode,
                outcome: .copiedSilently,
                fallbackReason: .pasteEventFailed
            )
        }

        return finish(
            result: .pasted,
            target: target,
            requestedMode: pasteMode,
            outcome: .pasted,
            fallbackReason: nil
        )
    }

    private func restore(target: PasteTarget) -> Bool {
        if let restoreHandler {
            return restoreHandler(target)
        }
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
        if let pasteEventHandler {
            return pasteEventHandler()
        }
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

    private func finish(
        result: PasteResult,
        target: PasteTarget?,
        requestedMode: PasteMode,
        outcome: PasteInsertionOutcome,
        fallbackReason: PasteFallbackReason?
    ) -> PasteOperationResult {
        PasteOperationResult(
            result: result,
            diagnostic: PasteInsertionDiagnostic(
                requestedMode: requestedMode,
                targetAppName: target?.appName,
                targetWindowTitle: target?.windowTitle,
                targetFieldRole: target?.focusedElementRole,
                targetFieldTitle: target?.focusedElementTitle,
                targetFieldPlaceholder: target?.focusedElementPlaceholder,
                outcome: outcome,
                fallbackReason: fallbackReason
            )
        )
    }

    private func targetMatchesCurrentContext(target: PasteTarget, current: ActiveAppContext) -> Bool {
        guard let targetPID = target.processIdentifier, let currentPID = current.processIdentifier, targetPID == currentPID else {
            return false
        }
        guard target.isEditableTextInput, target.isSecureTextInput == false else {
            return false
        }
        guard current.editableRoleClass == target.editableRoleClass else {
            return false
        }

        let windowMatches = normalized(current.windowTitle) == normalized(target.windowTitle)
        let titleMatches = normalized(current.focusedElementTitle) == normalized(target.focusedElementTitle)
        let placeholderMatches = normalized(current.focusedElementPlaceholder) == normalized(target.focusedElementPlaceholder)
        let descriptionMatches = normalized(current.focusedElementDescription) == normalized(target.focusedElementDescription)
        let snippetMatches = snippetMatch(current.focusedValueSnippet, target.focusedValueSnippet)

        let hasTargetIdentity = [target.windowTitle, target.focusedElementTitle, target.focusedElementPlaceholder, target.focusedElementDescription]
            .contains { normalized($0) != nil }

        if titleMatches || placeholderMatches || descriptionMatches {
            return true
        }
        if windowMatches && snippetMatches {
            return true
        }
        if windowMatches && hasTargetIdentity == false {
            return true
        }
        return false
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func snippetMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else { return false }
        let leftPrefix = String(lhs.prefix(24))
        let rightPrefix = String(rhs.prefix(24))
        return leftPrefix == rightPrefix
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

enum HotkeyBackend: String, Codable, Sendable {
    case eventMonitor
    case functionKeySpecialCase
    case fallback
    case unavailable
}

struct ShellFallbackStatus: Equatable, Sendable {
    let used: Bool
    let reason: String?
    let suggestedBinding: HotkeyBinding?
}

struct ShellBindingResolution: Sendable {
    let backend: HotkeyBackend
    let effectiveBinding: HotkeyBinding
    let originalBinding: HotkeyBinding
    let fallback: ShellFallbackStatus
    let message: String?
    let recommendedFallback: HotkeyBinding?
    let permissionGranted: Bool
    let isActive: Bool

    var fallbackWasUsed: Bool { fallback.used }
}

typealias HotkeyStartResult = ShellBindingResolution

@MainActor
final class FunctionKeyHotkeyBackend {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var handler: ((InputEvent) -> Void)?
    private var isPressed = false

    func start(binding: HotkeyBinding, handler: @escaping (InputEvent) -> Void) -> Bool {
        stop()
        guard binding.isFunctionOnlyBinding else { return false }
        self.handler = handler
        isPressed = false

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let inputEvent = self.matchingFunctionEvent(for: event, binding: binding) else { return event }
            self.handler?(inputEvent)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self else { return }
            guard let inputEvent = self.matchingFunctionEvent(for: event, binding: binding) else { return }
            self.handler?(inputEvent)
        }

        return localMonitor != nil || globalMonitor != nil
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        handler = nil
        isPressed = false
    }

    private func matchingFunctionEvent(for event: NSEvent, binding: HotkeyBinding) -> InputEvent? {
        guard event.type == .flagsChanged else { return nil }
        guard UInt16(event.keyCode) == binding.keyCode else { return nil }
        guard let modifierKeyRawValue = binding.modifierKeyRawValue else { return nil }
        let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
        let activeWithoutPrimary = active & ~modifierKeyRawValue
        guard activeWithoutPrimary == binding.modifierFlagsRawValue else { return nil }
        let pressed = active & modifierKeyRawValue != 0
        if pressed == isPressed { return nil }
        isPressed = pressed
        return pressed ? .triggerDown : .triggerUp
    }
}

@MainActor
final class HotkeyManager {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activeBinding: HotkeyBinding?
    private var handler: ((InputEvent) -> Void)?
    private let eventMonitorStarter: ((HotkeyBinding, @escaping (InputEvent) -> Void) -> Bool)?
    private let functionKeyBackendStarter: ((HotkeyBinding, @escaping (InputEvent) -> Void) -> Bool)?
    private let functionKeyBackend = FunctionKeyHotkeyBackend()

    init(
        eventMonitorStarter: ((HotkeyBinding, @escaping (InputEvent) -> Void) -> Bool)? = nil,
        functionKeyBackendStarter: ((HotkeyBinding, @escaping (InputEvent) -> Void) -> Bool)? = nil
    ) {
        self.eventMonitorStarter = eventMonitorStarter
        self.functionKeyBackendStarter = functionKeyBackendStarter
    }

    func register(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        fallbackCandidates: [HotkeyBinding],
        onEvent: @escaping (InputEvent) -> Void
    ) -> HotkeyStartResult {
        unregister()

        let permissionGranted = AXIsProcessTrusted()
        let validation = binding.validationResult
        guard validation.isValid else {
            return HotkeyStartResult(
                backend: .unavailable,
                effectiveBinding: binding,
                originalBinding: binding,
                fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback(for: binding, candidates: fallbackCandidates)),
                message: validation.blockingMessage,
                recommendedFallback: recommendedFallback(for: binding, candidates: fallbackCandidates),
                permissionGranted: permissionGranted,
                isActive: false
            )
        }

        guard permissionGranted else {
            return HotkeyStartResult(
                backend: .unavailable,
                effectiveBinding: binding,
                originalBinding: binding,
                fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback(for: binding, candidates: fallbackCandidates)),
                message: "Accessibility permission is required for global hotkeys.",
                recommendedFallback: recommendedFallback(for: binding, candidates: fallbackCandidates),
                permissionGranted: false,
                isActive: false
            )
        }

        let recommendedFallback = recommendedFallback(for: binding, candidates: fallbackCandidates)

        if binding.isFunctionOnlyBinding {
            if startFunctionKeyBackend(binding: binding, handler: onEvent) {
                return HotkeyStartResult(
                    backend: .functionKeySpecialCase,
                    effectiveBinding: binding,
                    originalBinding: binding,
                    fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback),
                    message: "Fn / Globe monitoring is active.",
                    recommendedFallback: recommendedFallback,
                    permissionGranted: true,
                    isActive: true
                )
            }

            switch fallbackMode {
            case .automatic:
                if let fallback = firstAvailableFallback(candidates: fallbackCandidates, handler: onEvent) {
                    return HotkeyStartResult(
                        backend: .fallback,
                        effectiveBinding: fallback,
                        originalBinding: binding,
                        fallback: ShellFallbackStatus(used: true, reason: "Fn / Globe could not be activated globally. Using \(fallback.displayTitle) instead.", suggestedBinding: fallback),
                        message: "Fn / Globe could not be activated globally. Using \(fallback.displayTitle) instead.",
                        recommendedFallback: fallback,
                        permissionGranted: true,
                        isActive: true
                    )
                }
            case .ask:
                if startEventMonitorBackend(binding: binding, handler: onEvent) {
                    return HotkeyStartResult(
                        backend: .eventMonitor,
                        effectiveBinding: binding,
                        originalBinding: binding,
                        fallback: ShellFallbackStatus(used: false, reason: "Fn / Globe may not work globally. Recommended fallback: \(recommendedFallback?.displayTitle ?? "none").", suggestedBinding: recommendedFallback),
                        message: "Fn / Globe may not work globally. Recommended fallback: \(recommendedFallback?.displayTitle ?? "none").",
                        recommendedFallback: recommendedFallback,
                        permissionGranted: true,
                        isActive: true
                    )
                }
            case .disabled:
                if startEventMonitorBackend(binding: binding, handler: onEvent) {
                    return HotkeyStartResult(
                        backend: .eventMonitor,
                        effectiveBinding: binding,
                        originalBinding: binding,
                        fallback: ShellFallbackStatus(used: false, reason: "Fn / Globe may not work globally outside the app.", suggestedBinding: recommendedFallback),
                        message: "Fn / Globe may not work globally outside the app.",
                        recommendedFallback: recommendedFallback,
                        permissionGranted: true,
                        isActive: true
                    )
                }
            }

            return HotkeyStartResult(
                backend: .unavailable,
                effectiveBinding: binding,
                originalBinding: binding,
                fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback),
                message: "No global hotkey could be activated.",
                recommendedFallback: recommendedFallback,
                permissionGranted: true,
                isActive: false
            )
        }

        if startEventMonitorBackend(binding: binding, handler: onEvent) {
            return HotkeyStartResult(
                backend: .eventMonitor,
                effectiveBinding: binding,
                originalBinding: binding,
                fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback),
                message: "Hotkey active: \(binding.displayTitle)",
                recommendedFallback: recommendedFallback,
                permissionGranted: true,
                isActive: true
            )
        }

        return HotkeyStartResult(
            backend: .unavailable,
            effectiveBinding: binding,
            originalBinding: binding,
            fallback: ShellFallbackStatus(used: false, reason: nil, suggestedBinding: recommendedFallback),
            message: "No global hotkey could be activated.",
            recommendedFallback: recommendedFallback,
            permissionGranted: true,
            isActive: false
        )
    }

    func unregister() {
        functionKeyBackend.stop()
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        activeBinding = nil
        handler = nil
    }

    private func startEventMonitorBackend(
        binding: HotkeyBinding,
        handler: @escaping (InputEvent) -> Void
    ) -> Bool {
        if let eventMonitorStarter {
            let started = eventMonitorStarter(binding, handler)
            if started {
                activeBinding = binding
                self.handler = handler
            }
            return started
        }

        activeBinding = binding
        self.handler = handler

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let inputEvent = self.matchingInputEvent(for: event, binding: binding) else { return event }
            self.handler?(inputEvent)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return }
            guard let inputEvent = self.matchingInputEvent(for: event, binding: binding) else { return }
            self.handler?(inputEvent)
        }

        return localMonitor != nil || globalMonitor != nil
    }

    private func startFunctionKeyBackend(
        binding: HotkeyBinding,
        handler: @escaping (InputEvent) -> Void
    ) -> Bool {
        if let functionKeyBackendStarter {
            let started = functionKeyBackendStarter(binding, handler)
            if started {
                activeBinding = binding
                self.handler = handler
            }
            return started
        }
        let started = functionKeyBackend.start(binding: binding, handler: handler)
        if started {
            activeBinding = binding
            self.handler = handler
        }
        return started
    }

    private func firstAvailableFallback(candidates: [HotkeyBinding], handler: @escaping (InputEvent) -> Void) -> HotkeyBinding? {
        for fallback in candidates {
            if startEventMonitorBackend(binding: fallback, handler: handler) {
                return fallback
            }
        }
        return nil
    }

    private func recommendedFallback(for binding: HotkeyBinding, candidates: [HotkeyBinding]) -> HotkeyBinding? {
        candidates.first { $0 != binding }
    }

    private func matchingInputEvent(for event: NSEvent, binding: HotkeyBinding) -> InputEvent? {
        guard UInt16(event.keyCode) == binding.keyCode else { return nil }

        switch event.type {
        case .keyDown, .keyUp:
            guard binding.modifierKeyRawValue == nil else { return nil }
            if event.type == .keyDown, event.isARepeat {
                return nil
            }
            let required = binding.modifierFlagsRawValue & HotkeyBinding.relevantModifierMask
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            guard active == required else { return nil }
            return event.type == .keyDown ? .triggerDown : .triggerUp
        case .flagsChanged:
            guard let modifierKeyRawValue = binding.modifierKeyRawValue else { return nil }
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            let activeWithoutPrimary = active & ~modifierKeyRawValue
            guard activeWithoutPrimary == binding.modifierFlagsRawValue else { return nil }
            let isPressed = active & modifierKeyRawValue != 0
            return isPressed ? .triggerDown : .triggerUp
        default:
            return nil
        }
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

extension HotkeyBinding {
    static func from(event: NSEvent) -> HotkeyBinding? {
        switch event.type {
        case .flagsChanged:
            let modifiers = event.modifierFlags.intersection([.function])
            guard modifiers.contains(.function) else { return nil }
            return .defaultFunctionKey
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty == false else { return nil }

            var flags: UInt = 0
            if modifiers.contains(.command) { flags |= commandModifierRawValue }
            if modifiers.contains(.option) { flags |= optionModifierRawValue }
            if modifiers.contains(.control) { flags |= controlModifierRawValue }
            if modifiers.contains(.shift) { flags |= shiftModifierRawValue }

            return HotkeyBinding(
                keyCode: UInt16(event.keyCode),
                modifierFlagsRawValue: flags,
                keyDisplay: keyDisplay(for: UInt16(event.keyCode)),
                modifierKeyRawValue: nil
            )
        default:
            return nil
        }
    }
}
