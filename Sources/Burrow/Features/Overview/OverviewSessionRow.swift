import BurrowCore
import SwiftUI

struct OverviewSessionRow: View {
    let session: HistoryReport.Session

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: session.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(session.title)
                .bold()
            Text(session.startedText)
                .foregroundStyle(.secondary)
                .help(session.startedAt ?? "")
            Spacer(minLength: Theme.Space.item)
            if let items = session.itemsText {
                Text(items)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Sessions that freed nothing still say what they did.
            Text(session.sizeText ?? session.actionSummary)
                .foregroundStyle(session.sizeText == nil ? .secondary : .primary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.card)
        .padding(.vertical, Theme.Space.item)
        .accessibilityElement(children: .combine)
    }
}
