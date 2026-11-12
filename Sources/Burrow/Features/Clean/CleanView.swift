import BurrowCore
import SwiftUI

/// One continuous page: the results fill in during the scan and are already in place when it
/// ends, so there's no jump between scanning and reviewing.
struct CleanView: View {
    @Bindable var model: CleanModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                CleanIntro(model: model, cli: cli)
                    .transition(Motion.materialize)
            case .scanning, .review:
                CleanReportView(model: model, cli: cli)
                    .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .onChange(of: model.state) { _, state in
            if state == .review { Announcer.say("Scan finished. \(model.summaryLine).") }
        }
        .sheet(isPresented: $model.isChoosingVolume) {
            ExternalVolumeSheet(model: model, cli: cli, isPreview: app.effectivePreview)
        }
    }
}
