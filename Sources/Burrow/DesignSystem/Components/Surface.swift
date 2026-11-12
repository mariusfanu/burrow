import SwiftUI

/// A grouped area in the content layer. It's deliberately not Liquid Glass: glass is for the
/// controls that float above content, and cards are content.
struct Surface<Content: View>: View {
    var padding: CGFloat = Theme.Space.group
    @ViewBuilder var content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.fill.quinary, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(.separator.opacity(contrast == .increased ? 1 : 0.5))
            }
    }
}
