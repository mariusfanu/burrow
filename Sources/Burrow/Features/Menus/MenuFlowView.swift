import BurrowCore
import SwiftUI

struct MenuFlowView: View {
    let model: MenuFlowModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                MenuFlowIntro(model: model, cli: cli)
                    .transition(Motion.materialize(reduced: reduceMotion))
            case .scanning:
                WorkingView(
                    title: model.configuration.scanTitle,
                    detail: model.readProgress.isEmpty ? model.run.activity : model.readProgress
                )
            case .choosing:
                MenuFlowList(model: model)
                    .transition(Motion.materialize(reduced: reduceMotion))
            case .applying:
                WorkingView(title: "Applying Your Selection", detail: "Checking each row")
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize(reduced: reduceMotion))
            }
        }
        .animation(Motion.glide(reduced: reduceMotion), value: model.state)
        .onChange(of: app.effectivePreview) { abandonIfPreviewChanged() }
        .onAppear(perform: abandonIfPreviewChanged)
    }

    /// A menu started in one mode must not be confirmed in the other.
    private func abandonIfPreviewChanged() {
        guard model.state == .choosing, model.isPreviewRun != app.effectivePreview else { return }
        model.abandon(because: MenuFlowModel.previewChangedReason)
    }
}
