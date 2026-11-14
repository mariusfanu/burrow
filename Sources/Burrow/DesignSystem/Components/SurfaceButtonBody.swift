import SwiftUI

struct SurfaceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
            .scaleEffect(scale)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .shadow(color: .black.opacity(isHovered ? 0.14 : 0), radius: 12, y: 5)
            .animation(Motion.snap(reduced: reduceMotion), value: configuration.isPressed)
            .animation(Motion.snap(reduced: reduceMotion), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var scale: CGFloat {
        guard !Motion.isReduced(reduceMotion) else { return 1 }
        if configuration.isPressed { return 0.985 }
        return isHovered ? 1.008 : 1
    }
}
