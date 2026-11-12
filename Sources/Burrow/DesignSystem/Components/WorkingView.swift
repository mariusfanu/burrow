import SwiftUI

/// A spinner with the task's name and what it's doing right now.
struct WorkingView: View {
    let title: String
    var detail: String = ""

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
                .animation(Motion.snap, value: detail)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(Motion.materialize)
    }
}
