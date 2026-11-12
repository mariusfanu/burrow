import SwiftUI

struct RateTile: View {
    let label: String
    let symbol: String
    let rate: Double

    var body: some View {
        let bytes = bytesPerSecond(rate)
        let formatted = bytes?.rate ?? "—"
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
            Text(formatted)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(bytes == nil ? .opacity : .numericText(value: rate))
                .animation(Motion.snap, value: formatted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
