import AppKit
import Foundation

final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var functionIsDown = false
    private var lastReleaseDate: Date?
    private let doubleTapWindow: TimeInterval = 0.32

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
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
    }

    private func handle(event: NSEvent) {
        let functionDown = event.modifierFlags.contains(.function)

        if functionDown && !functionIsDown {
            functionIsDown = true
            let now = Date()
            if let lastReleaseDate, now.timeIntervalSince(lastReleaseDate) <= doubleTapWindow {
                onDoubleTap?()
            } else {
                onPress?()
            }
        } else if !functionDown && functionIsDown {
            functionIsDown = false
            lastReleaseDate = Date()
            onRelease?()
        }
    }
}
