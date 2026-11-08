import AppKit
import Combine
import SwiftUI

/// The window owns visibility; the model owns the monitoring policy.
struct WindowVisibilityObserver: NSViewRepresentable {
    var changed: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.changed = changed
    }
}

final class VisibilityView: NSView {
    var changed: (@MainActor (Bool) -> Void)?
    private var observation: AnyCancellable?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else { changed?(false); return }
        let center = NotificationCenter.default
        observation = center.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
            .merge(with: center.publisher(for: NSWindow.didMiniaturizeNotification, object: window),
                   center.publisher(for: NSWindow.didDeminiaturizeNotification, object: window),
                   center.publisher(for: NSApplication.didHideNotification),
                   center.publisher(for: NSApplication.didUnhideNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.publishVisibility() }
            }
        publishVisibility()
    }

    private func publishVisibility() {
        guard let window else { changed?(false); return }
        changed?(!NSApp.isHidden && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
    }
}
