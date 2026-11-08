import SwiftUI
import BurrowCore
import Testing
@testable import Burrow

@MainActor
struct TreemapRenderingTests {
    @Test func hoverAndLightingPreserveTheActualTextBackgroundContrast() throws {
        for accent: UInt32 in [0x8C8C8C, 0x007AFF, 0xF74F9E, 0xFFC600, 0xFFFFFF] {
            let color = AccentPalette.tile(rank: 0, accent: accent)
            for (hovered, selected) in [(false, false), (true, false), (false, true), (true, true)] {
                let view = TileFace(title: "Folder", size: "1 KB", symbol: "folder", rect: CGRect(x: 0, y: 0, width: 160, height: 80), color: color, isHovered: hovered, isSelected: selected)
                    .frame(width: 160, height: 80)
                let bytes = try pixels(view)
                try #require(bytes.count == 160 * 80 * 4)
                // Inside the surface, away from the border and label antialiasing.
                let offset = (10 * 160 + 10) * 4
                #expect(bytes[offset + 3] == 255)
                let rendered = UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
                #expect(AccentPalette.contrast(0xFFFFFF, rendered) >= AccentPalette.minimumContrast)
            }
        }
    }
}
