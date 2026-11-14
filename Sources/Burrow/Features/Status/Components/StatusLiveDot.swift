import SwiftUI

/// A small dot that pulses when a sample actually arrives, so it means "this is fresh".
struct StatusLiveDot: View {
    let sampleID: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduced = Motion.isReduced(reduceMotion)
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .keyframeAnimator(initialValue: PulseValues(), trigger: sampleID) { dot, values in
                dot
                    .background {
                        Circle()
                            .stroke(.green.opacity(values.ring), lineWidth: 1.5)
                            .scaleEffect(values.scale)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(reduced ? 1 : 2.6, duration: 0.9)
                }
                KeyframeTrack(\.ring) {
                    LinearKeyframe(reduced ? 0 : 0.7, duration: 0.01)
                    CubicKeyframe(0, duration: 0.9)
                }
            }
            // The slot is as wide as the ring at its largest, so the pulse never touches
            // the word beside it.
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private struct PulseValues {
        var scale: CGFloat = 1
        var ring: Double = 0
    }
}
