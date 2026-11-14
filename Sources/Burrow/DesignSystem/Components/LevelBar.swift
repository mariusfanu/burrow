import SwiftUI

/// A small meter whose fill glides to each new value and never leaves its track.
struct LevelBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: fillWidth(in: proxy.size.width))
                }
        }
        .frame(height: height)
        .animation(Motion.lift(reduced: reduceMotion), value: fraction)
        .accessibilityHidden(true)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard fraction.isFinite, width.isFinite, width > 0 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return clamped > 0 ? max(width * clamped, height) : 0
    }
}

extension LevelBar {
    /// A bar showing `part` as a share of `whole`, empty when there's no whole to compare with.
    init(part: Int64, of whole: Int64, tint: Color = .accentColor, height: CGFloat = 6) {
        self.init(fraction: whole > 0 ? Double(part) / Double(whole) : 0, tint: tint, height: height)
    }
}
