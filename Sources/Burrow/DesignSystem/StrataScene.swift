import SwiftUI

/// Burrow's one illustration: a level under an open sky, in the colors of the system accent.
/// The level rises as the disk fills, so freeing space visibly lowers it. Its layers drift for
/// a few seconds as they settle, then hold still, so that leaving this page open costs nothing.
struct StrataScene: View {
    /// Fraction of the disk in use.
    let usedFraction: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var shownFraction = 0.0
    @State private var drift = 0.0

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45], [0.6, 0.5], [1, 0.42],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: Theme.skyMesh(colorScheme)
            )
            AnimatedGround(level: shownFraction, drift: drift, layers: Theme.levelLayers(colorScheme))
        }
        .onAppear { settle(toward: usedFraction) }
        .onChange(of: isMeaningfulChange) { settle(toward: usedFraction) }
        .accessibilityHidden(true)
    }

    /// Tiny changes between samples don't move the ground. Only real ones do, in 0.2% steps.
    private var isMeaningfulChange: Int {
        Int(usedFraction * 500)
    }

    private func settle(toward fraction: Double) {
        withAnimation(Motion.lift) { shownFraction = fraction }
        guard !Motion.isReduced else { return }
        withAnimation(.easeOut(duration: 3.5)) { drift += 1 }
    }
}

/// Ground whose level eases between values while its layers drift.
@Animatable
private struct AnimatedGround: View {
    var level: Double
    var drift: Double
    @AnimatableIgnored var layers: [Gradient]

    var body: some View {
        Canvas { context, size in
            // The ground stays below the page's text, even on a full disk.
            let surface = size.height * (1 - 0.1 - 0.3 * min(max(level, 0), 1))
            for (index, gradient) in layers.enumerated() {
                let depth = CGFloat(index) / CGFloat(layers.count)
                let top = surface + (size.height - surface) * depth
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                let amplitude = 5 + CGFloat(index) * 2.5
                let travel = 0.6 + Double(index) * 0.22
                for step in 0...60 {
                    let x = size.width * CGFloat(step) / 60
                    let angle = Double(step) / 60 * .pi * 2.4 + Double(index) * 1.7 + drift * travel
                    let y = top + amplitude * CGFloat(sin(angle)) + amplitude * 0.4 * CGFloat(sin(angle * 2.3 + 1))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: top - amplitude * 1.4),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}
