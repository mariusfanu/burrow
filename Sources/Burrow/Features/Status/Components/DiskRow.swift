import BurrowCore
import SwiftUI

struct DiskRow: View {
    let disk: StatusSnapshot.Disk

    private static let displayNameCache = NSCache<NSString, NSString>()

    private static func displayName(for path: String) -> String {
        let key = path as NSString
        if let cached = displayNameCache.object(forKey: key) { return cached as String }
        let name = FileManager.default.displayName(atPath: path)
        displayNameCache.setObject(name as NSString, forKey: key)
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text(Self.displayName(for: disk.mount ?? "/"))
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text("\(disk.usedPercent ?? 0, format: .number.precision(.fractionLength(0)))%")
                    .monospacedDigit()
            }
            .font(.callout)
            LevelBar(fraction: (disk.usedPercent ?? 0) / 100, tint: StatusTint.disk(disk.usedPercent ?? 0))
            Text("\((disk.used ?? 0).fileSize) of \((disk.total ?? 0).fileSize)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
