import SwiftUI

/// Large figures in the rounded system face, used where a number is the point of the page.
struct HeroNumber: View {
    let text: String
    var size: CGFloat = 44
    /// Drives the rolling digit transition.
    var value: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(Motion.settle, value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
