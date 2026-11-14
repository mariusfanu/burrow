import SwiftUI

/// The top of a running command: its name, its current step, and a bar that moves only when
/// the command really advances.
struct RunProgressHeader: View {
    let run: RunController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.item) {
            HStack(spacing: Theme.Space.item) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(run.title)
                    .font(.title2)
                    .bold()
                Spacer()
                if let progress = run.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                }
            }
            Text(stepText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(Motion.snap(reduced: reduceMotion), value: stepText)
            if let progress = run.progress {
                LevelBar(fraction: progress)
            }
        }
        .padding([.horizontal, .top], Theme.Space.page)
        .padding(.bottom, Theme.Space.group)
    }

    private var stepText: String {
        if !run.activity.isEmpty { return run.activity }
        if !run.currentSection.isEmpty { return run.currentSection }
        return run.commandLine
    }
}
