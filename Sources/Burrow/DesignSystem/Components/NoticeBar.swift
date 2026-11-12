import SwiftUI

/// A notice pinned to the edge of a page.
///
/// Unlike `InlineNotice`, its height is capped. A window measures its minimum size by proposing
/// a very narrow width, and text that insists on its full height would wrap into a column taller
/// than the window, which pushes the whole window's content out of view.
struct NoticeBar: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            if !symbol.isEmpty {
                Image(systemName: symbol)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .help(text)
            Spacer(minLength: 0)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Dismiss this message")
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar, ignoresSafeAreaEdges: [])
    }
}
