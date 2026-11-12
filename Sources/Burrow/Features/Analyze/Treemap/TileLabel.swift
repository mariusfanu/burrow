import SwiftUI

struct TileLabel: View {
    let title: String
    let size: String
    let symbol: String
    let rect: CGRect

    var body: some View {
        if rect.width > 70, rect.height > 38 {
            VStack(spacing: Theme.Space.micro) {
                HStack(spacing: Theme.Space.tight) {
                    if rect.width > 120 {
                        Image(systemName: symbol)
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.callout)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(size)
                    .font(.callout)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.snug)
        }
    }
}
