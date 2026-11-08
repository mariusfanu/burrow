import Foundation

/// A command a page offers. One definition feeds both the toolbar and the menu bar, so the
/// two can't disagree, as the HIG asks of toolbar items.
struct PageAction {
    let title: String
    var symbol: String?
    var isEnabled = true
    /// False when the page already shows this as its one central button.
    var showsInToolbar = true
    /// True when this stops work under way, which a Reload shortcut must never do.
    var isCancellation = false
    let perform: @MainActor () -> Void
}
