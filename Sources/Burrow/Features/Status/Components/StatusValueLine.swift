import SwiftUI

struct StatusValueLine: View {
    let value: String
    let unit: String
    var number: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The unit sits snug against the figure in the same rounded face, so "27%" reads
        // as one value rather than a number and a stray sign.
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: number))
                .animation(Motion.snap(reduced: reduceMotion), value: value)
            Text(unit)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
