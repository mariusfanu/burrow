import SwiftUI

/// A refresh shows only its symbol and spins once when clicked. Cancel is spelled out.
struct SecondaryToolbarButton: View {
    let action: PageAction
    @State private var turns = 0

    var body: some View {
        Group {
            if let symbol = action.symbol {
                Button(action: refresh) {
                    Label(action.title, systemImage: symbol)
                        .symbolEffect(.rotate, options: .speed(2), value: turns)
                }
                .help(action.title)
            } else {
                Button(action.title, action: action.perform)
            }
        }
        .disabled(!action.isEnabled)
    }

    private func refresh() {
        if !Motion.isReduced { turns += 1 }
        action.perform()
    }
}
