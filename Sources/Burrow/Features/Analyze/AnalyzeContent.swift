import BurrowCore
import SwiftUI

struct AnalyzeContent: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        HSplitView {
            TreemapStage(model: model, cli: cli)
                .overlay(alignment: .top) {
                    AnalyzeNotices(model: model, cli: cli)
                        .padding(Theme.Space.item)
                }
                .animation(Motion.settle, value: model.noticeMessage)
                .animation(Motion.settle, value: model.errorMessage)
                .padding([.horizontal, .bottom], Theme.Space.item)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            AnalyzeEntryList(model: model, cli: cli)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
        }
    }
}
