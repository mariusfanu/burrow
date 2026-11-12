import SwiftUI

struct ShakeEffect: ViewModifier {
    let trigger: Int
    let isReduced: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { [isReduced] view, offset in
            view.offset(x: isReduced ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                SpringKeyframe(-9, duration: 0.07)
                SpringKeyframe(8, duration: 0.09)
                SpringKeyframe(-5, duration: 0.08)
                SpringKeyframe(3, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}
