import SwiftUI

/// A ring that draws itself to its value.
struct RingGauge<Label: View>: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .animation(Motion.lift(reduced: reduceMotion), value: fraction)
    }
}
