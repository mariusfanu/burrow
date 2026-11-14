import BurrowCore
import SwiftUI

struct CleanReportView: View {
    @Bindable var model: CleanModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [CleanReport.Section] {
        model.report.sections.filter { !$0.isEmpty }
    }

    private var empties: [CleanReport.Section] {
        model.report.sections.filter(\.isEmpty)
    }

    var body: some View {
        let largestBytes = groups.map(\.bytes).max() ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.group) {
                CleanTotalHeader(
                    bytes: model.report.potentialBytes,
                    isScanning: model.state == .scanning,
                    activity: model.scanActivity
                )
                if let errorMessage = model.errorMessage {
                    InlineNotice(text: errorMessage, tint: .red) { model.errorMessage = nil }
                }
                if !model.protectedThisSession.isEmpty {
                    InlineNotice(text: "Protected items are left alone from now on. Scan again to update the total.", symbol: "lock.shield.fill", tint: .blue)
                }
                ForEach(groups) { section in
                    CleanSectionCard(
                        section: section,
                        largestBytes: largestBytes,
                        model: model,
                        cli: cli,
                        isEditable: model.state == .review && !app.effectivePreview
                    )
                    .transition(Motion.rise(reduced: reduceMotion))
                }
                if !empties.isEmpty, model.state == .review {
                    Text("Nothing to clean in \(empties.map(\.name).formatted(.list(type: .and))).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(Theme.Space.page)
        }
        // Here rather than on the page, whose body would otherwise read the report on every
        // update of a scan. This question only comes up once the report is finished.
        .alert("Clean \(model.report.potentialBytes.fileSize) from This Mac?", isPresented: $model.isConfirming) {
            // Return mustn't be the way something permanent happens.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Clean") { model.clean(cli: cli, preview: false) }
        } message: {
            Text(model.confirmationMessage)
        }
    }
}
