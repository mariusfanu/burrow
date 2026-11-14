import AppKit
import SwiftUI

/// An app icon from Launch Services, or a generic app symbol.
struct AppIconView: View {
    let path: String?

    private static let iconCache = NSCache<NSString, NSImage>()

    private static func icon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let path {
                Image(nsImage: Self.icon(for: path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}
