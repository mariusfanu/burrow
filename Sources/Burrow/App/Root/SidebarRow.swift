import SwiftUI

/// One sidebar row. Its icon answers a selection, and its trailing edge shows that a page
/// has work under way or a result waiting.
struct SidebarRow: View {
    let screen: Screen
    let isSelected: Bool
    let isWorking: Bool
    let needsAttention: Bool
    let badge: String?

    @State private var selectionCount = 0

    var body: some View {
        HStack {
            Label {
                Text(screen.title)
            } icon: {
                Image(systemName: screen.symbol)
                    .symbolEffect(.bounce, options: .speed(1.5), value: selectionCount)
            }
            Spacer(minLength: 4)
            if needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs Attention")
                    .help("This command is waiting for your answer")
            } else if isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .transition(Motion.materialize)
                    .accessibilityLabel("Working")
            } else if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.settle, value: isWorking)
        .animation(Motion.settle, value: badge)
        .onChange(of: isSelected) {
            if isSelected, !Motion.isReduced { selectionCount += 1 }
        }
    }
}
