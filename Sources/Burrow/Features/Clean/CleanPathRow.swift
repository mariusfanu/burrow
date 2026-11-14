import BurrowCore
import SwiftUI

/// A file row whose actions appear on hover, with the same commands on secondary click.
struct CleanPathRow: View {
    let entry: CleanReport.PathEntry
    let isProtected: Bool
    let isEditable: Bool
    let protect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.row) {
            if isProtected {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, options: .nonRepeating, value: Motion.isReduced(reduceMotion) ? false : isProtected)
                    .accessibilityLabel("Protected")
            }
            Text(entry.path.abbreviatingHome)
                .font(.callout.monospaced())
                .foregroundStyle(isProtected ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(entry.path)
            Spacer(minLength: 8)
            if !isProtected, isEditable {
                // Always present, because a control that needs a pointer can't be reached
                // with the keyboard or VoiceOver. It only stays quiet until you're near it.
                Button("Protect", systemImage: "lock", action: protectEntry)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .opacity(isHovered ? 1 : 0.35)
                    .accessibilityLabel("Protect \(entry.path.lastPathComponent)")
                    .help("Keep cleanup away from this path from now on")
            }
            Text(entry.sizeText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 20)
        .onHover { isHovered = $0 }
        .animation(Motion.snap(reduced: reduceMotion), value: isHovered)
        .contextMenu {
            Button("Show in Finder", action: reveal)
            Button("Always Protect This", action: protectEntry)
                .disabled(isProtected || !isEditable)
        }
    }

    private func reveal() {
        FilePicker.reveal(entry.path)
    }

    private func protectEntry() {
        protect(entry.path)
    }
}
