import Foundation
import AppKit

final class FunctionKeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isFunctionDown = false

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isFunctionDown = false
    }

    private func handle(_ event: NSEvent) {
        let currentlyDown = event.modifierFlags.contains(.function)
        guard currentlyDown != isFunctionDown else { return }
        isFunctionDown = currentlyDown
        if currentlyDown {
            onPress?()
        } else {
            onRelease?()
        }
    }
}
