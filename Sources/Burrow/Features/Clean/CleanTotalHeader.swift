import SwiftUI

/// The running total, which rolls upward as the scan finds more.
struct CleanTotalHeader: View {
    let bytes: Int64
    let isScanning: Bool
    let activity: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HeroNumber(text: bytes.countedSize, value: Double(bytes))
            HStack(spacing: Theme.Space.row) {
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .transition(Motion.materialize(reduced: reduceMotion))
                }
                Text(isScanning ? activity : "can be reclaimed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .animation(Motion.snap(reduced: reduceMotion), value: activity)
        }
        .padding(.bottom, Theme.Space.tight)
        .accessibilityElement(children: .combine)
    }
}
