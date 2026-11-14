import SwiftUI

struct PrimaryToolbarButton: View {
    let action: PageAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action.perform) {
            Text(action.title)
                .contentTransition(.numericText())
                .animation(Motion.snap(reduced: reduceMotion), value: action.title)
        }
        .buttonStyle(.glassProminent)
        .disabled(!action.isEnabled)
    }
}
