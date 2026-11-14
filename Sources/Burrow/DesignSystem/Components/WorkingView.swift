import SwiftUI

/// A spinner with the task's name and what it's doing right now.
struct WorkingView: View {
    let title: String
    var detail: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.cluster) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3)
                .bold()
            Text(detail.isEmpty ? " " : detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(Motion.snap(reduced: reduceMotion), value: detail)
                .frame(maxWidth: 480)
                .accessibilityHidden(detail.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(Motion.materialize(reduced: reduceMotion))
    }
}
