import BurrowCore
import SwiftUI

struct HistoryDeletionRow: View {
    let row: HistoryReport.Deletion

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: row.mode == "trash" ? "trash" : "xmark.bin")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityLabel(row.mode ?? "")
            VStack(alignment: .leading, spacing: 1) {
                Text(row.path?.abbreviatingHome ?? "")
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(row.timestampText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status = row.status, status != "ok" {
                FactTag(text: status, tint: .red)
            }
            if let bytes = row.bytes {
                Text(bytes.fileSize)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
