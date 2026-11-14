import SwiftUI

/// What the panel shows in place of the terminal: the result, the log, or both.
struct RunPanelContent: View {
    let run: RunController
    @Binding var showsDetails: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isFinished, !showsLogByDefault {
            CompletionHero(run: run, showsDetails: $showsDetails)
                .transition(Motion.materialize(reduced: reduceMotion))
        } else {
            VStack(spacing: 0) {
                if isFinished {
                    CompletionBanner(run: run, showsDetails: $showsDetails)
                        .transition(Motion.materialize(reduced: reduceMotion))
                } else {
                    RunProgressHeader(run: run)
                        .transition(.opacity)
                }
                RunLogList(run: run)
            }
        }
    }

    private var isFinished: Bool {
        switch run.phase {
        case .finished, .failedToStart: true
        case .idle, .running: false
        }
    }

    /// A failure keeps its log in view, because that's where the reason is.
    private var showsLogByDefault: Bool {
        showsDetails || run.keepsLogAtEnd || (!run.didSucceed && !run.wasCancelled && !run.wasDeclined)
    }
}
