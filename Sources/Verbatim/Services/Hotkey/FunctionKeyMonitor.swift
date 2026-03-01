import AppKit
import Foundation

final class FunctionKeyMonitor {
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
        functionIsDown = false
    }

    private func handle(_ event: NSEvent) {
        let isDown = event.modifierFlags.contains(.function)
        if isDown && !functionIsDown {
            functionIsDown = true
            let now = Date()
            if let last = lastReleaseDate, now.timeIntervalSince(last) <= doubleTapWindow {
                onDoubleTap?()
            } else {
                onPress?()
            }
        } else if !isDown && functionIsDown {
            functionIsDown = false
            lastReleaseDate = Date()
            onRelease?()
        }
    }
}
