import BurrowCore
import SwiftUI

struct AnalyzeReadout: View {
    let model: AnalyzeModel

    private var hoveredEntry: AnalyzeResult.Entry? {
        model.entries.first { $0.path == model.hovered }
    }

    var body: some View {
        HStack(spacing: Theme.Space.row) {
            if let entry = hoveredEntry {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.size.fileSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let total = model.result?.totalSize, total > 0 {
                    Text(Double(entry.size) / Double(total), format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if let total = model.result?.totalSize {
                Text(total.fileSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(total)))
            }
            if model.result?.isPartial == true {
                FactTag(text: "Partial Scan", tint: .orange)
                    .help("Some folders took too long and weren’t measured")
            }
        }
        .font(.callout)
        .animation(Motion.snap, value: model.hovered)
    }
}
