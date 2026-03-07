import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
protocol ListeningIndicatorServiceProtocol {
    func showListening()
    func hideListening()
}

@MainActor
final class MenuBarListeningIndicatorService: ListeningIndicatorServiceProtocol {
#if canImport(AppKit)
    private var statusItem: NSStatusItem?
#endif

    func showListening() {
#if canImport(AppKit)
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = VerbatimBrandAssets.nsImage(for: .menuGlyph)
            ?? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Verbatim Listening")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.contentTintColor = .systemRed
        item.button?.toolTip = "Verbatim is listening"
        statusItem = item
#endif
    }

    func hideListening() {
#if canImport(AppKit)
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
#endif
    }
}
