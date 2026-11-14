import BurrowCore
import SwiftUI

struct AnalyzeContent: View {
    let model: AnalyzeModel
    let cli: CLIInfo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HSplitView {
            TreemapStage(model: model, cli: cli)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { model.mapSize = $0 }
                .overlay(alignment: .top) {
                    AnalyzeNotices(model: model, cli: cli)
                        .padding(Theme.Space.item)
                }
                .animation(Motion.settle(reduced: reduceMotion), value: model.noticeMessage)
                .animation(Motion.settle(reduced: reduceMotion), value: model.errorMessage)
                .padding([.horizontal, .bottom], Theme.Space.item)
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            AnalyzeEntryList(model: model, cli: cli)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
        }
    }
}
