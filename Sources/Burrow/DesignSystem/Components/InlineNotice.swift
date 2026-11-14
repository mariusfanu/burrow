import SwiftUI

/// One-line messages near the content they're about.
struct InlineNotice: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var dismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Dismiss this message")
            }
        }
        .padding(.horizontal, Theme.Space.cluster)
        .padding(.vertical, Theme.Space.row)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.notice))
        .transition(Motion.rise(reduced: reduceMotion))
    }
}
