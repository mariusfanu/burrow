import BurrowCore
import SwiftUI

struct DiskRow: View {
    let disk: StatusSnapshot.Disk

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text(FileManager.default.displayName(atPath: disk.mount ?? "/"))
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
