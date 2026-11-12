import BurrowCore
import SwiftUI

struct UninstallView: View {
    let model: UninstallModel
    let cli: CLIInfo

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                ToolIntro(
                    symbol: "trash",
                    title: "Uninstall Apps Completely",
                    message: model.errorMessage ?? "See your apps with their sizes, then remove them along with the files they leave behind."
                ) {
                    Button("Load Apps", action: load)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(Motion.materialize)
            case .loading:
                WorkingView(title: "Listing Installed Apps")
            case .list:
                UninstallList(model: model)
                    .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .task(loadIfNeeded)
    }

    private func load() {
        model.load(cli: cli)
    }

    @Sendable
    private func loadIfNeeded() async {
        model.loadIfNeeded(cli: cli)
    }
}
