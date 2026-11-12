import SwiftUI

struct PrimaryToolbarButton: View {
    let action: PageAction

    var body: some View {
        Button(action: action.perform) {
            Text(action.title)
                .contentTransition(.numericText())
                .animation(Motion.snap, value: action.title)
        }
        .buttonStyle(.glassProminent)
        .disabled(!action.isEnabled)
    }
}
