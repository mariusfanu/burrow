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

private struct LogIcon: View {
    let kind: LogLine.Kind
    @State private var isDrawn = false

    var body: some View {
        Group {
            if kind == .plain {
                Color.clear
            } else {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
                    .symbolEffect(.drawOn, isActive: kind == .success && !isDrawn)
                    .accessibilityLabel(label)
            }
        }
        .frame(width: 14, height: 12)
        .onAppear {
            withAnimation(.easeOut(duration: Motion.isReduced ? 0 : 0.35)) { isDrawn = true }
        }
    }

    private var symbol: String {
        switch kind {
        case .section, .plain: "minus"
        case .success: "checkmark.circle.fill"
        case .preview: "circle"
        case .note: "exclamationmark.circle"
        case .review: "info.circle"
        case .meta: "gearshape"
        case .failure: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .success: .green
        case .preview: .accentColor
        case .note: .orange
        case .failure: .red
        default: .secondary
        }
    }

    private var label: String {
        switch kind {
        case .success: "Done"
        case .preview: "Would change"
        case .note: "Note"
        case .failure: "Failed"
        default: ""
        }
    }
}
