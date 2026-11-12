import SwiftUI

struct MaterializeEffect: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.97 + 0.03 * progress)
            .blur(radius: 8 * (1 - progress))
    }
}
