import SwiftUI

/// A short pill for facts such as a kind or an age.
struct FactTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, Theme.Space.micro)
            .background(tint.opacity(0.13), in: .capsule)
    }
}
