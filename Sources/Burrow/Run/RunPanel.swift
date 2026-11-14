import SwiftUI

/// A command at work. While it runs, the page shows what it's doing and how far along it is.
/// When it ends, the result takes over and the log folds away behind Details.
struct RunPanel: View {
    @Bindable var run: RunController
    /// Sheets have no window toolbar, so they carry their own controls.
    var isSheet = false
    var close: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if run.isTerminalVisible, let terminal = run.terminal {
                TerminalPanel(terminal: terminal, revision: run.screenRevision, run: run)
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                    .padding(Theme.Space.item)
                    .transition(Motion.materialize(reduced: reduceMotion))
            } else {
                RunPanelContent(run: run, showsDetails: $showsDetails)
            }
            if isSheet {
                RunSheetControls(run: run, close: close)
            }
        }
        .animation(Motion.glide(reduced: reduceMotion), value: run.isTerminalVisible)
        .animation(Motion.glide(reduced: reduceMotion), value: showsDetails)
        .toolbar {
            if !isSheet {
                ToolbarItem(placement: .automatic) {
                    RunTerminalToggle(run: run)
                }
            }
        }
        .sheet(item: $run.promptRequest) { request in
            PromptSheet(request: request, run: run)
        }
        .sensoryFeedback(.levelChange, trigger: run.didSucceed) { _, succeeded in succeeded }
        .onChange(of: run.phase) { Announcer.say(run.completionAnnouncement) }
        .onChange(of: run.startDate) { showsDetails = false }
    }
}
