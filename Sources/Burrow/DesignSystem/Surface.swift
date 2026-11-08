import SwiftUI

/// A grouped area in the content layer. It's deliberately not Liquid Glass: glass is for the
/// controls that float above content, and cards are content.
struct Surface<Content: View>: View {
    var padding: CGFloat = Theme.Space.group
    @ViewBuilder var content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.fill.quinary, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(.separator.opacity(contrast == .increased ? 1 : 0.5))
            }
    }
}

/// A light that follows the pointer across a surface and fades when it leaves.
struct PointerGlow: ViewModifier {
    var color: Color = .white
    var strength: Double = 0.14
    var radius: CGFloat = 170

    @State private var location: CGPoint?
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if let location, !Motion.isReduced {
                    GeometryReader { proxy in
                        // The gradient fills the surface and centers on the pointer, so it
                        // never shows an edge of its own.
                        RadialGradient(
                            colors: [color.opacity(strength), .clear],
                            center: UnitPoint(
                                x: location.x / max(proxy.size.width, 1),
                                y: location.y / max(proxy.size.height, 1)
                            ),
                            startRadius: 0,
                            endRadius: radius
                        )
                    }
                    .opacity(opacity)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    location = point
                    if opacity == 0 { withAnimation(Motion.snap) { opacity = 1 } }
                case .ended:
                    withAnimation(Motion.glide) { opacity = 0 }
                }
            }
    }
}

/// The press and hover behavior for content surfaces that act as buttons.
struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SurfaceButtonBody(configuration: configuration)
    }
}

private struct SurfaceButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
            .scaleEffect(scale)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .shadow(color: .black.opacity(isHovered ? 0.14 : 0), radius: 12, y: 5)
            .animation(Motion.snap, value: configuration.isPressed)
            .animation(Motion.snap, value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var scale: CGFloat {
        guard !Motion.isReduced else { return 1 }
        if configuration.isPressed { return 0.985 }
        return isHovered ? 1.008 : 1
    }
}
