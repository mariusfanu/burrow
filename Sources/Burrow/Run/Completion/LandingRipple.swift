import SwiftUI

/// One ring that leaves the checkmark as it lands, then is gone. It's hidden at rest, so it
/// shows only while its keyframes play.
struct LandingRipple: View {
    let tint: Color
    let trigger: Int

    var body: some View {
        Circle()
            .strokeBorder(tint, lineWidth: 2)
            .frame(width: 64, height: 64)
            .keyframeAnimator(initialValue: Values(), trigger: trigger) { ring, values in
                ring
                    .scaleEffect(values.scale)
                    .opacity(values.opacity)
            } keyframes: { _ in
                // It fades faster than it grows, so it's gone before it reaches the figure below.
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(1.75, duration: 0.9)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.7, duration: 0.01)
                    CubicKeyframe(0, duration: 0.7)
                }
            }
            .accessibilityHidden(true)
    }

    private struct Values {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}
