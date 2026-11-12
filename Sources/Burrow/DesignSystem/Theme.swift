import AppKit
import BurrowCore
import SwiftUI

/// Colors with a job to do. Everything comes from the system: status colors are its own, and
/// the Overview scene and treemap are derived from the accent the person chose in System
/// Settings, so the app feels like part of their Mac in light and dark.
enum Theme {
    /// The system accent as an sRGB value, for deriving other colors.
    static var accent: UInt32 {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["BURROW_ACCENT"], let value = UInt32(override, radix: 16) {
            return value
        }
        #endif
        guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return 0x007AFF }
        func byte(_ component: CGFloat) -> UInt32 { UInt32((component * 255).rounded()) }
        return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
    }

    /// The layers of the Overview scene, each a vertical gradient.
    static func levelLayers(_ scheme: ColorScheme) -> [Gradient] {
        AccentPalette.layers(accent: accent, isDark: scheme == .dark).map { layer in
            Gradient(colors: [Color(hex: layer.top), Color(hex: layer.bottom)])
        }
    }

    /// The Overview sky.
    static func skyMesh(_ scheme: ColorScheme) -> [Color] {
        AccentPalette.sky(accent: accent, isDark: scheme == .dark).map { Color(hex: $0) }
    }

    /// A treemap tile's color. Inside a folder, tiles are shades of that folder's color, so
    /// color says which branch you're in.
    static func tile(rank: Int, parent: UInt32?) -> UInt32 {
        if let parent { return AccentPalette.shade(rank: rank, parent: parent) }
        return AccentPalette.tile(rank: rank, accent: accent)
    }

    /// Standard radii, so that nested shapes stay related.
    enum Radius {
        static let bar: CGFloat = 2
        static let inset: CGFloat = 7
        static let tile: CGFloat = 8
        static let notice: CGFloat = 9
        static let card: CGFloat = 12
    }

    /// Standard spacing, from the macOS window margin down. Odd values that remain in views,
    /// such as 3 and 5, are optical adjustments rather than steps on this scale.
    enum Space {
        static let page: CGFloat = 24
        static let sheet: CGFloat = 22
        static let wide: CGFloat = 18
        static let group: CGFloat = 16
        static let card: CGFloat = 14
        static let cluster: CGFloat = 12
        static let item: CGFloat = 10
        static let row: CGFloat = 8
        static let snug: CGFloat = 6
        static let tight: CGFloat = 4
        static let micro: CGFloat = 2
    }
}
