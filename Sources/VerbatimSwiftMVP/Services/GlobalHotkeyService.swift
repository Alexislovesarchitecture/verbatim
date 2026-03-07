import Foundation
#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

enum GlobalHotkeyEvent {
    case keyDown
    case keyUp
}

struct GlobalHotkeyConfig {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt
    let modifierKeyRawValue: UInt?
}

protocol GlobalHotkeyServiceProtocol {
    func startMonitoring(config: GlobalHotkeyConfig, handler: @escaping (GlobalHotkeyEvent) -> Void)
    func stopMonitoring()
    func hasAccessibilityPermission() -> Bool
}

final class GlobalHotkeyService: GlobalHotkeyServiceProtocol {
#if canImport(AppKit)
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var config: GlobalHotkeyConfig?
    private var handler: ((GlobalHotkeyEvent) -> Void)?
#endif

    func startMonitoring(config: GlobalHotkeyConfig, handler: @escaping (GlobalHotkeyEvent) -> Void) {
#if canImport(AppKit)
        stopMonitoring()
        self.config = config
        self.handler = handler

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let hotkeyEvent = self.matchingHotkeyEvent(for: event) else { return event }
            if event.type == .keyDown, event.isARepeat {
                return nil
            }
            self.handler?(hotkeyEvent)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return }
            guard let hotkeyEvent = self.matchingHotkeyEvent(for: event) else { return }
            self.handler?(hotkeyEvent)
        }
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
        config = nil
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

#if canImport(AppKit)
    private func matchingHotkeyEvent(for event: NSEvent) -> GlobalHotkeyEvent? {
        guard let config else { return nil }
        guard event.keyCode == config.keyCode else { return nil }

        switch event.type {
        case .keyDown, .keyUp:
            guard config.modifierKeyRawValue == nil else { return nil }
            if event.type == .keyDown, event.isARepeat {
                return nil
            }
            let required = config.modifierFlagsRawValue & HotkeyBinding.relevantModifierMask
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            guard active == required else { return nil }
            return event.type == .keyDown ? .keyDown : .keyUp
        case .flagsChanged:
            guard let modifierKeyRawValue = config.modifierKeyRawValue else { return nil }
            let active = event.modifierFlags.rawValue & HotkeyBinding.relevantModifierMask
            let activeWithoutPrimary = active & ~modifierKeyRawValue
            guard activeWithoutPrimary == config.modifierFlagsRawValue else { return nil }
            let isPressed = active & modifierKeyRawValue != 0
            return isPressed ? .keyDown : .keyUp
        default:
            return nil
        }
    }
#endif
}
