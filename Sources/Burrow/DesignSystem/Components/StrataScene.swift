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
