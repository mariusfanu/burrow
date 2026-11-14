import AppKit
import SwiftUI

/// Controls presenting the dedicated About panel.
@MainActor
final class AboutPanelController {
    static let shared = AboutPanelController()
    private var window: NSPanel?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Burrow"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()

        let hosting = NSHostingView(rootView: AboutWindowContent())
        panel.contentView = hosting
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
