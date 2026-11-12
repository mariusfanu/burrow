import SwiftUI

/// A ring that draws itself to its value.
struct RingGauge<Label: View>: View {
    let fraction: Double
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .animation(Motion.lift, value: fraction)
    }
}
