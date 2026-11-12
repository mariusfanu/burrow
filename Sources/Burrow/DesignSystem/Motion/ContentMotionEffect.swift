import SwiftUI

/// Content transitions fade without spatial movement when Reduce Motion is enabled.
struct ContentMotionEffect: ViewModifier {
    let progress: CGFloat
    let scale: CGFloat
    let y: CGFloat
    let isReduced: Bool

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(isReduced ? 1 : scale + (1 - scale) * progress)
            .offset(y: isReduced ? 0 : y * (1 - progress))
    }
}
