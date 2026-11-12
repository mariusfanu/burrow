import SwiftUI

/// A menu item that stays in place and dims when the page has nothing to offer.
struct ActionMenuItem: View {
    let action: PageAction?
    let placeholder: String
    let key: KeyEquivalent
    let modifiers: EventModifiers

    var body: some View {
        Button(action?.title ?? placeholder) { action?.perform() }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(action == nil || action?.isEnabled == false)
    }
}
