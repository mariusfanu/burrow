import BurrowCore
import SwiftUI

struct AnalyzeEntryRow: View {
    let entry: AnalyzeResult.Entry
    let tint: UInt32
    let total: Int64
    /// Read here, not in the list, so that moving the pointer only touches the rows.
    let model: AnalyzeModel
    let canTrash: Bool

    private var isHovered: Bool { model.hovered == entry.path }

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: entry.isDir ? "folder.fill" : "doc")
                .foregroundStyle(Color(hex: tint))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                HStack(spacing: Theme.Space.snug) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.cleanable == true {
                        FactTag(text: "Cleanable", tint: .green)
                    }
                    if !canTrash {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Protected")
                    }
                }
                LevelBar(
                    part: entry.size,
                    of: total,
                    tint: Color(hex: tint),
                    height: 3
                )
            }
            Text(entry.size.fileSize)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.micro)
        .opacity(isHovered ? 1 : 0.94)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(entry.size.fileSize)
    }

    private var accessibilityLabel: String {
        var parts = [entry.isDir ? "Folder" : "File", entry.name]
        if entry.cleanable == true { parts.append("Cleanable") }
        if !canTrash { parts.append("Protected") }
        return parts.joined(separator: ", ")
    }
}
