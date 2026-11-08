import Testing
@testable import BurrowCore

@Suite struct AccentPaletteTests {
    /// The macOS accent options, plus extremes a palette must survive.
    static let accents: [UInt32] = [
        0x007AFF, 0xA550A7, 0xF74F9E, 0xFF5257, 0xF7821B, 0xFFC600, 0x62BA46, 0x8C8C8C, // system
        0xFFFFFF, 0x000000, 0x00FFFF,
    ]

    @Test(arguments: accents)
    func treemapLabelsStayReadableAtEveryDepth(accent: UInt32) {
        for rank in 0..<16 {
            let top = AccentPalette.tile(rank: rank, accent: accent)
            #expect(AccentPalette.contrast(0xFFFFFF, top) >= AccentPalette.minimumContrast)
            for childRank in 0..<16 {
                let child = AccentPalette.shade(rank: childRank, parent: top)
                #expect(AccentPalette.contrast(0xFFFFFF, child) >= AccentPalette.minimumContrast)
                let grandchild = AccentPalette.shade(rank: rank, parent: child)
                #expect(AccentPalette.contrast(0xFFFFFF, grandchild) >= AccentPalette.minimumContrast)
            }
        }
    }

    @Test(arguments: accents)
    func theLabelOnTheNearestLayerStaysReadable(accent: UInt32) {
        for isDark in [false, true] {
            let nearest = AccentPalette.layers(accent: accent, isDark: isDark).last
            #expect(AccentPalette.contrast(0xFFFFFF, nearest?.top ?? 0xFFFFFF) >= AccentPalette.minimumContrast)
            #expect(AccentPalette.contrast(0xFFFFFF, nearest?.bottom ?? 0xFFFFFF) >= AccentPalette.minimumContrast)
        }
    }

    @Test(arguments: accents)
    func skyTextStaysReadable(accent: UInt32) {
        // Text sits over the top two rows of the mesh, as black in light and white in dark.
        for color in AccentPalette.sky(accent: accent, isDark: false).prefix(6) {
            #expect(AccentPalette.contrast(0x000000, color) >= 7)
        }
        for color in AccentPalette.sky(accent: accent, isDark: true).prefix(6) {
            #expect(AccentPalette.contrast(0xFFFFFF, color) >= 7)
        }
    }

    @Test func graphiteStaysGray() {
        let tile = AccentPalette.hsb(from: AccentPalette.tile(rank: 1, accent: 0x8C8C8C))
        #expect(tile.saturation < 0.02)
    }

    @Test func colorConversionRoundTrips() {
        for color: UInt32 in [0x007AFF, 0xF74F9E, 0x62BA46, 0x8C8C8C, 0xFFFFFF, 0x000000] {
            #expect(AccentPalette.hex(from: AccentPalette.hsb(from: color)) == color)
        }
    }
}
