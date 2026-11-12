import SwiftUI

/// The opened tile itself, growing to fill the map or shrinking back into place. It's solid,
/// so the two maps never show through each other.
@Animatable
struct ZoomPlate: View {
    var progress: CGFloat
    @AnimatableIgnored var rect: CGRect
    @AnimatableIgnored var tint: UInt32
    @AnimatableIgnored var size: CGSize
    @AnimatableIgnored var isZoomingIn: Bool

    var body: some View {
        let amount = min(max(progress, 0), 1)
        let growth = isZoomingIn ? amount : 1 - amount
        let tile = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        let frame = CGRect(
            x: tile.minX * (1 - growth),
            y: tile.minY * (1 - growth),
            width: tile.width + (size.width - tile.width) * growth,
            height: tile.height + (size.height - tile.height) * growth
        )
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(Color(hex: tint))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .fill(LinearGradient(colors: [.white.opacity(0.1), .clear, .black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            // Once the new tiles cover it, the plate gets out of the way of the gaps between them.
            .opacity(isZoomingIn ? 1 - Double(min(max((amount - 0.82) / 0.18, 0), 1)) : 1)
    }
}
