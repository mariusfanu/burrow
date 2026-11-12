import SwiftUI

struct RiseEffect: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: 8 * (1 - progress))
    }
}
