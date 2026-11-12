import SwiftUI

/// A clickable row opening a related project or developer URL.
struct AboutLinkRow: View {
    let title: String
    let name: String
    let detail: String
    let systemImage: String
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Theme.Space.cluster) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Space.item)

                Image(systemName: "arrow.up.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .scaleEffect(isHovered && !Motion.isReduced ? 1.08 : 1)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snap) {
                isHovered = hovering
            }
        }
        .help("Open \(url.absoluteString)")
    }
}
