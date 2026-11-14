import AppKit
import Combine

final class VisibilityView: NSView {
    var changed: (@MainActor (Bool) -> Void)?
    private var observation: AnyCancellable?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guard let window else {
            Task { @MainActor [weak self] in
                self?.publishVisibility()
            }
            return
        }
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
        Task { @MainActor [weak self] in
            self?.publishVisibility()
        }
    }

    private func publishVisibility() {
        guard let window else { changed?(false); return }
        changed?(!NSApp.isHidden && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
    }
}
