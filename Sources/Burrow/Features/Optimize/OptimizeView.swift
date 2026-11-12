import BurrowCore
import SwiftUI

struct OptimizeView: View {
    @Bindable var model: OptimizeModel
    let cli: CLIInfo

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                ToolIntro(
                    symbol: "wrench.and.screwdriver",
                    title: "Refresh Caches and Services",
                    message: "Bounded maintenance such as rebuilding icon caches, refreshing DNS and repairing preferences. See the plan before anything runs.",
                    errorMessage: model.errorMessage
                ) {
                    Button("Check This Mac", action: check)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(Motion.materialize)
            case .previewing:
                WorkingView(title: "Checking This Mac", detail: model.activity)
            case .review:
                VStack(spacing: 0) {
                    if let message = model.errorMessage {
                        InlineNotice(text: message)
                            .padding(.horizontal, Theme.Space.page)
                            .padding(.top, Theme.Space.page)
                    }
                    OptimizePlan(lines: model.lines)
                }
                .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .alert("Run Maintenance Now?", isPresented: $model.isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Run", action: run)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Some tasks ask for your password. Tasks you’ve turned off in Settings are skipped.")
        }
    }

    private func check() {
        model.preview(cli: cli)
    }

    private func run() {
        model.runMaintenance(cli: cli, preview: false)
    }
}
