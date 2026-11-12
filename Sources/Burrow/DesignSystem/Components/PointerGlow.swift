import SwiftUI

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
