import SwiftUI

/// Keep text on its contrast-tested solid color. Hover only changes the edge.
struct TileFace: View {
    let title: String
    let size: String
    let symbol: String
    let rect: CGRect
    let color: UInt32
    let isHovered: Bool
    var isSelected = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Small tiles get smaller corners, so a sliver stays a rectangle instead of becoming a
    /// pill or a dot.
    private var radius: CGFloat {
        min(Theme.Radius.tile, max(min(rect.width, rect.height) * 0.22, 2))
    }

    private var edgeOpacity: Double {
        if isHovered { return 0.8 }
        return contrast == .increased ? 0.7 : 0.22
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(hex: color))
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.white.opacity(edgeOpacity), lineWidth: isHovered ? 2 : 1)
            TileLabel(title: title, size: size, symbol: symbol, rect: rect)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color(hex: color))
                    .padding(5)
                    .transition(Motion.content(scale: 0.3, reduced: reduceMotion))
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2.5)
        }
        .clipShape(.rect(cornerRadius: radius))
        .animation(Motion.snap(reduced: reduceMotion), value: isHovered)
    }
}
