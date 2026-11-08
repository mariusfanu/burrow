// Draws Burrow's app icon and writes every size an .iconset needs.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-icon.swift <output.iconset>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func archPath(in rect: CGRect) -> CGPath {
    let radius = rect.width / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
    path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - radius), radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.closeSubpath()
    return path
}

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // The macOS icon grid leaves a margin around a rounded square.
    let margin = size * 0.1
    let body = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let plate = CGPath(roundedRect: body, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)
    context.addPath(plate)
    context.clip()

    // Dusk sky, pale blue into a little periwinkle. Matches the layered icon.
    let sky = CGGradient(colorsSpace: nil, colors: [color(0x94C2ED), color(0xBAB3DB)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Nested arches in the same blues as Resources/Burrow.icon, ending in the dark mouth.
    let bands: [UInt32] = [0xA7C3E3, 0x6B94C4, 0x3866A6, 0x2A4E86, 0x122441]
    let baseWidth = body.width * 0.86
    let step = body.width * 0.11
    for (index, band) in bands.enumerated() {
        let inset = CGFloat(index) * step
        let width = baseWidth - inset * 2
        let rect = CGRect(
            x: body.midX - width / 2,
            y: body.minY,
            width: width,
            height: body.height * 0.82 - inset
        )
        context.addPath(archPath(in: rect))
        context.setFillColor(color(band))
        context.fillPath()
    }

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in entries {
    try drawIcon(pixels: pixels).write(to: output.appendingPathComponent(name + ".png"))
}
