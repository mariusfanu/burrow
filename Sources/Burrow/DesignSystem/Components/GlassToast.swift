import SwiftUI

/// A floating confirmation with an optional Undo. It's a control that floats above content,
/// so here Liquid Glass is the right material.
struct GlassToast: View {
    let text: String
    var undo: (() -> Void)?
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.borderless)
                    .bold()
            }
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss this message")
        }
        .padding(.horizontal, Theme.Space.card)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .transition(Motion.materialize(reduced: reduceMotion))
    }
}
