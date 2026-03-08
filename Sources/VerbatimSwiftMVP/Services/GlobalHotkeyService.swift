import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

enum GlobalHotkeyEvent: String, Sendable {
    case keyDown
    case keyUp
}

enum HotkeyBackend: String, Sendable {
    case eventMonitor
    case functionKeySpecialCase
    case fallback
    case unavailable
}

struct HotkeyStartResult: Sendable {
    let backend: HotkeyBackend
    let effectiveBinding: HotkeyBinding
    let originalBinding: HotkeyBinding
    let fallbackWasUsed: Bool
    let message: String?
    let recommendedFallback: HotkeyBinding?
    let permissionGranted: Bool
    let isActive: Bool
}

protocol GlobalHotkeyServiceProtocol {
    func startMonitoring(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        handler: @escaping (GlobalHotkeyEvent) -> Void
    ) -> HotkeyStartResult
    func stopMonitoring()
    func hasAccessibilityPermission() -> Bool
    func requestAccessibilityPermissionPrompt() -> Bool
}

final class GlobalHotkeyService: GlobalHotkeyServiceProtocol {
#if canImport(AppKit)
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activeBinding: HotkeyBinding?
    private var handler: ((GlobalHotkeyEvent) -> Void)?

    private let eventMonitorStarter: ((HotkeyBinding, @escaping (GlobalHotkeyEvent) -> Void) -> Bool)?
    private let functionKeyBackendStarter: ((HotkeyBinding, @escaping (GlobalHotkeyEvent) -> Void) -> Bool)?

    init(
        eventMonitorStarter: ((HotkeyBinding, @escaping (GlobalHotkeyEvent) -> Void) -> Bool)? = nil,
        functionKeyBackendStarter: ((HotkeyBinding, @escaping (GlobalHotkeyEvent) -> Void) -> Bool)? = nil
    ) {
        self.eventMonitorStarter = eventMonitorStarter
        self.functionKeyBackendStarter = functionKeyBackendStarter
    }
#else
    init() {}
#endif

    func startMonitoring(
        binding: HotkeyBinding,
        fallbackMode: FunctionKeyFallbackMode,
        handler: @escaping (GlobalHotkeyEvent) -> Void
    ) -> HotkeyStartResult {
#if canImport(AppKit)
        stopMonitoring()

        let permissionGranted = hasAccessibilityPermission()
        let recommendedFallback = recommendedFallback(for: binding)

        if binding.isFunctionOnlyBinding {
            if startFunctionKeyBackend(binding: binding, handler: handler) {
                return HotkeyStartResult(
                    backend: .functionKeySpecialCase,
                    effectiveBinding: binding,
                    originalBinding: binding,
                    fallbackWasUsed: false,
                    message: "Function key monitoring is active.",
                    recommendedFallback: recommendedFallback,
                    permissionGranted: permissionGranted,
                    isActive: true
                )
            }

            switch fallbackMode {
            case .automatic:
                if let fallback = firstAvailableFallback(handler: handler) {
                    return HotkeyStartResult(
                        backend: .fallback,
                        effectiveBinding: fallback,
                        originalBinding: binding,
                        fallbackWasUsed: true,
                        message: "Function key could not be used globally. Using \(fallback.displayTitle) instead.",
                        recommendedFallback: fallback,
                        permissionGranted: permissionGranted,
                        isActive: true
                    )
                }
            case .ask:
                if startEventMonitorBackend(binding: binding, handler: handler) {
                    return HotkeyStartResult(
                        backend: .eventMonitor,
                        effectiveBinding: binding,
                        originalBinding: binding,
                        fallbackWasUsed: false,
                        message: "Function key may not work globally. Recommended fallback: \(recommendedFallback?.displayTitle ?? "none").",
                        recommendedFallback: recommendedFallback,
                        permissionGranted: permissionGranted,
                        isActive: true
                    )
                }
            case .disabled:
                if startEventMonitorBackend(binding: binding, handler: handler) {
                    return HotkeyStartResult(
                        backend: .eventMonitor,
                        effectiveBinding: binding,
                        originalBinding: binding,
                        fallbackWasUsed: false,
                        message: "Function key may not work globally outside the app.",
                        recommendedFallback: recommendedFallback,
                        permissionGranted: permissionGranted,
                        isActive: true
                    )
                }
            }

            return HotkeyStartResult(
                backend: .unavailable,
                effectiveBinding: binding,
                originalBinding: binding,
                fallbackWasUsed: false,
                message: "No global hotkey could be activated.",
                recommendedFallback: recommendedFallback,
                permissionGranted: permissionGranted,
                isActive: false
            )
        }

        if startEventMonitorBackend(binding: binding, handler: handler) {
            return HotkeyStartResult(
                backend: .eventMonitor,
                effectiveBinding: binding,
                originalBinding: binding,
                fallbackWasUsed: false,
                message: "Hotkey active: \(binding.displayTitle)",
                recommendedFallback: recommendedFallback,
                permissionGranted: permissionGranted,
                isActive: true
            )
        }

        return HotkeyStartResult(
            backend: .unavailable,
            effectiveBinding: binding,
            originalBinding: binding,
            fallbackWasUsed: false,
            message: "No global hotkey could be activated.",
            recommendedFallback: recommendedFallback,
            permissionGranted: permissionGranted,
            isActive: false
        )
#else
        HotkeyStartResult(
            backend: .unavailable,
            effectiveBinding: binding,
            originalBinding: binding,
            fallbackWasUsed: false,
            message: "Global hotkeys require macOS.",
            recommendedFallback: nil,
            permissionGranted: true,
            isActive: false
        )
#endif
    }

    func stopMonitoring() {
#if canImport(AppKit)
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
#endif
    }

    func hasAccessibilityPermission() -> Bool {
#if canImport(AppKit)
        AXIsProcessTrusted()
#else
        true
#endif
    }

    func requestAccessibilityPermissionPrompt() -> Bool {
#if canImport(AppKit)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
#else
        true
#endif
    }

#if canImport(AppKit)
    private func startEventMonitorBackend(
        binding: HotkeyBinding,
        handler: @escaping (GlobalHotkeyEvent) -> Void
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
        installLocalAndGlobalMonitors(binding: binding)
        return localMonitor != nil || globalMonitor != nil
    }

    private func startFunctionKeyBackend(
        binding: HotkeyBinding,
        handler: @escaping (GlobalHotkeyEvent) -> Void
    ) -> Bool {
        guard let functionKeyBackendStarter else {
            return false
        }
        let started = functionKeyBackendStarter(binding, handler)
        if started {
            activeBinding = binding
            self.handler = handler
        }
        return started
    }

    private func firstAvailableFallback(handler: @escaping (GlobalHotkeyEvent) -> Void) -> HotkeyBinding? {
        for fallback in HotkeyBinding.recommendedFallbacks {
            if startEventMonitorBackend(binding: fallback, handler: handler) {
                return fallback
            }
        }
        return nil
    }

    private func recommendedFallback(for binding: HotkeyBinding) -> HotkeyBinding? {
        HotkeyBinding.recommendedFallbacks.first { $0 != binding }
    }

    private func installLocalAndGlobalMonitors(binding: HotkeyBinding) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let hotkeyEvent = self.matchingHotkeyEvent(for: event, binding: binding) else { return event }
            self.handler?(hotkeyEvent)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return }
            guard let hotkeyEvent = self.matchingHotkeyEvent(for: event, binding: binding) else { return }
            self.handler?(hotkeyEvent)
        }
    }

    private func matchingHotkeyEvent(for event: NSEvent, binding: HotkeyBinding) -> GlobalHotkeyEvent? {
        guard event.keyCode == binding.keyCode else { return nil }

        switch event.type {
        case .keyDown, .keyUp:
            guard binding.modifierKeyRawValue == nil else { return nil }
            if event.type == .keyDown, event.isARepeat {
                return nil
            }
            let required = binding.modifierFlagsRawValue & HotkeyBinding.relevantModifierMask
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            guard active == required else { return nil }
            return event.type == .keyDown ? .keyDown : .keyUp
        case .flagsChanged:
            guard let modifierKeyRawValue = binding.modifierKeyRawValue else { return nil }
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            let activeWithoutPrimary = active & ~modifierKeyRawValue
            guard activeWithoutPrimary == binding.modifierFlagsRawValue else { return nil }
            let isPressed = active & modifierKeyRawValue != 0
            return isPressed ? .keyDown : .keyUp
        default:
            return nil
        }
    }
#endif
}
