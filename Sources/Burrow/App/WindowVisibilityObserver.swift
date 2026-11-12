import AppKit
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
