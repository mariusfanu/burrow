import BurrowCore
import SwiftUI

struct HistorySessionRow: View {
    let session: HistoryReport.Session

    var body: some View {
        Surface(padding: Theme.Space.cluster) {
            HStack(spacing: Theme.Space.cluster) {
                Image(systemName: session.symbol)
                    .font(.title3)
                    .foregroundStyle(session.isPreview ? Color.secondary : Color.accentColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.micro) {
                    HStack(spacing: Theme.Space.snug) {
                        Text(session.title)
                            .font(.body)
                            .bold()
                        if session.isPreview {
                            FactTag(text: "Preview", tint: .blue)
                        }
                        if session.hadFailures {
                            FactTag(text: "Had Failures", tint: .red)
                        }
                    }
                    Text(session.startedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(session.startedAt ?? "")
                }
                Spacer()
                Text(session.actionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                VStack(alignment: .trailing, spacing: 1) {
                    if let size = session.sizeText {
                        Text(size)
                            .font(.body)
                            .bold()
                            .monospacedDigit()
                    }
                    if let items = session.itemsText {
                        Text(items)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 92, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
