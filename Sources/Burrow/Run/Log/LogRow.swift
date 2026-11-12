import BurrowCore
import SwiftUI

/// One classified line of CLI output. Icons and color repeat what the line says, so nothing
/// depends on color alone.
struct LogRow: View {
    let line: LogLine

    var body: some View {
        // One view per row, so that a long log's list doesn't evaluate every row to count them.
        VStack(alignment: .leading, spacing: 0) {
            if line.kind == .section {
                Text(line.title)
                    .font(.headline)
                    .padding(.top, Theme.Space.item)
                    .accessibilityAddTraits(.isHeader)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
                    LogIcon(kind: line.kind)
                    Text(line.title)
                        .font(.callout)
                        .foregroundStyle(line.kind == .review ? .secondary : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let detail = line.detail {
                        Text(detail)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
