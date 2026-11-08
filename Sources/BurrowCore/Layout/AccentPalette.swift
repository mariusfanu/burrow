import Foundation

/// Derives Burrow's colors from the system accent color, so that the app takes on whatever
/// accent the person chose, and every derived color stays readable.
public enum AccentPalette {
    struct HSB: Sendable, Equatable {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    /// The contrast the HIG asks for between text and its background.
    public static let minimumContrast = 4.5

    // MARK: - Treemap

    /// The tile color for a rank at the top level: neighbors of the accent on the color
    /// wheel, which stay related instead of turning into a rainbow.
    public static func tile(rank: Int, accent: UInt32) -> UInt32 {
        let base = hsb(from: accent)
        let steps: [(hue: Double, saturation: Double, brightness: Double)] = [
            (0, 1, 0.82), (0.07, 0.95, 0.74), (-0.06, 1, 0.70), (0.13, 0.9, 0.66),
            (-0.11, 0.95, 0.62), (0.035, 0.85, 0.58), (-0.035, 0.85, 0.54), (0.1, 0.8, 0.5),
        ]
        let step = steps[rank % steps.count]
        return legible(HSB(
            hue: base.hue + step.hue * saturationWeight(base),
            saturation: min(base.saturation * step.saturation, 1),
            brightness: step.brightness
        ))
    }

    /// A tile inside a folder: a shade of the folder's color, so color says which branch
    /// you're in.
    public static func shade(rank: Int, parent: UInt32) -> UInt32 {
        let base = hsb(from: parent)
        let steps: [(hue: Double, brightness: Double)] = [
            (0, 1), (0.018, 0.88), (-0.018, 1.08), (0.03, 0.78),
            (-0.03, 0.94), (0.01, 0.7), (-0.01, 0.84), (0.024, 0.64),
        ]
        let step = steps[rank % steps.count]
        return legible(HSB(
            hue: base.hue + step.hue * saturationWeight(base),
            saturation: base.saturation,
            brightness: min(base.brightness * step.brightness, 1)
        ))
    }

    // MARK: - Overview scene

    /// A 3x3 sky mesh, from top-left to bottom-right.
    public static func sky(accent: UInt32, isDark: Bool) -> [UInt32] {
        let base = hsb(from: accent)
        let color = { hex(from: variant(of: base, $0, $1, $2)) }
        if isDark {
            return [
                color(0.04, 0.55, 0.07), color(0, 0.6, 0.08), color(-0.03, 0.55, 0.09),
                color(0.05, 0.7, 0.14), color(0, 0.8, 0.2), color(-0.04, 0.75, 0.17),
                color(0.06, 0.8, 0.3), color(0, 0.85, 0.42), color(-0.05, 0.8, 0.36),
            ]
        }
        return [
            color(0.03, 0.03, 1), color(0, 0.02, 1), color(-0.02, 0.03, 1),
            color(0.04, 0.08, 1), color(0, 0.1, 1), color(-0.03, 0.09, 1),
            color(0.05, 0.2, 1), color(0, 0.26, 1), color(-0.04, 0.22, 1),
        ]
    }

    /// The layers of the disk level, from the surface down. Each is a pair of colors for a
    /// vertical gradient. The nearest layer holds a label, so it's kept readable.
    public static func layers(accent: UInt32, isDark: Bool) -> [(top: UInt32, bottom: UInt32)] {
        let base = hsb(from: accent)
        let color = { hex(from: variant(of: base, $0, $1, $2)) }
        if isDark {
            return [
                (color(-0.05, 0.62, 0.86), color(-0.03, 0.72, 0.62)),
                (color(-0.02, 0.74, 0.72), color(0.01, 0.8, 0.5)),
                (color(0.02, 0.8, 0.54), color(0.05, 0.84, 0.36)),
                (legible(variant(of: base, 0.06, 0.82, 0.34)), color(0.08, 0.85, 0.2)),
            ]
        }
        return [
            (color(-0.05, 0.3, 1), color(-0.03, 0.42, 1)),
            (color(-0.02, 0.5, 1), color(0, 0.6, 0.98)),
            (color(0.02, 0.68, 0.94), color(0.04, 0.78, 0.86)),
            (legible(variant(of: base, 0.05, 0.88, 0.72)), legible(variant(of: base, 0.07, 0.92, 0.58))),
        ]
    }

    // MARK: - Color math

    /// Darkens a color until white text on it meets the contrast minimum.
    static func legible(_ color: HSB) -> UInt32 {
        var adjusted = color
        var result = hex(from: adjusted)
        while contrast(0xFFFFFF, result) < minimumContrast, adjusted.brightness > 0.05 {
            adjusted.brightness -= 0.01
            result = hex(from: adjusted)
        }
        return result
    }

    /// WCAG contrast ratio between two sRGB colors.
    public static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (one, other) = (luminance(first), luminance(second))
        return (max(one, other) + 0.05) / (min(one, other) + 0.05)
    }

    static func luminance(_ color: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let value = Double((color >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// Near-gray accents such as Graphite stay gray instead of picking up a stray hue.
    private static func saturationWeight(_ color: HSB) -> Double {
        min(color.saturation / 0.45, 1)
    }

    /// A color near `base` on the wheel, scaled by how much color `base` has.
    private static func variant(of base: HSB, _ hueShift: Double, _ saturation: Double, _ brightness: Double) -> HSB {
        let weight = saturationWeight(base)
        return HSB(hue: base.hue + hueShift * weight, saturation: saturation * weight, brightness: brightness)
    }

    private static func wrap(_ hue: Double) -> Double {
        let remainder = hue.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    static func hsb(from color: UInt32) -> HSB {
        let red = Double((color >> 16) & 0xFF) / 255
        let green = Double((color >> 8) & 0xFF) / 255
        let blue = Double(color & 0xFF) / 255
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        var hue = 0.0
        if delta > 0 {
            if high == red {
                hue = (green - blue) / delta
            } else if high == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSB(hue: hue, saturation: high == 0 ? 0 : delta / high, brightness: high)
    }

    static func hex(from color: HSB) -> UInt32 {
        let hue = wrap(color.hue) * 6
        let saturation = min(max(color.saturation, 0), 1)
        let brightness = min(max(color.brightness, 0), 1)
        let chroma = brightness * saturation
        let second = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma
        let (red, green, blue): (Double, Double, Double)
        switch hue {
        case 0..<1: (red, green, blue) = (chroma, second, 0)
        case 1..<2: (red, green, blue) = (second, chroma, 0)
        case 2..<3: (red, green, blue) = (0, chroma, second)
        case 3..<4: (red, green, blue) = (0, second, chroma)
        case 4..<5: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        func byte(_ value: Double) -> UInt32 { UInt32(((value + match) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }
}
