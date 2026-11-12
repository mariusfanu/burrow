import SwiftUI

struct PageEffect: ViewModifier {
    let progress: Double
    let travel: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: travel * (1 - progress))
            .blur(radius: 5 * (1 - progress))
    }
}
