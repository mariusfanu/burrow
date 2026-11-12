import BurrowCore
import SwiftUI

/// The path to the current folder. Each step carries its branch's color, and on the far side
/// sits a readout of whatever the pointer is over.
struct AnalyzePathBar: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            ForEach(model.levels.enumerated(), id: \.element.id) { depth, level in
                if depth > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                AnalyzePathStep(level: level, isCurrent: depth == model.levels.count - 1) {
                    model.jump(toDepth: depth, cli: cli)
                }
                .transition(Motion.rise)
            }
            Spacer(minLength: 12)
            AnalyzeReadout(model: model)
        }
        .animation(Motion.settle, value: model.levels)
        // Lines up with the treemap's edge and the list's sizes below, not the page margin.
        .padding(.leading, Theme.Space.cluster)
        .padding(.trailing, Theme.Space.group)
        .padding(.vertical, Theme.Space.item)
        .frame(minHeight: 40)
    }
}
