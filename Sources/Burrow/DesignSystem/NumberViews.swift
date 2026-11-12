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

/// A file size that counts up from zero, for the moment a result lands.
@Animatable
struct CountingBytes: View {
    var bytes: Double

    var body: some View {
        // Double(Int64.max) rounds up to 2^63, which cannot be converted back to Int64.
        let count = bytes < Double(Int64.max) ? Int64(bytes) : Int64.max
        Text(count.countedSize)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A small meter whose fill glides to each new value and never leaves its track.
struct LevelBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: fillWidth(in: proxy.size.width))
                }
        }
        .frame(height: height)
        .animation(Motion.lift, value: fraction)
        .accessibilityHidden(true)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        return clamped > 0 ? max(width * clamped, height) : 0
    }
}

extension LevelBar {
    /// A bar showing `part` as a share of `whole`, empty when there's no whole to compare with.
    init(part: Int64, of whole: Int64, tint: Color = .accentColor, height: CGFloat = 6) {
        self.init(fraction: whole > 0 ? Double(part) / Double(whole) : 0, tint: tint, height: height)
    }
}

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
