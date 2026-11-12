import BurrowCore
import SwiftUI

struct DiskCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                StatusCardTitle(title: "Disk", symbol: "internaldrive")
                ForEach(snapshot.disks ?? []) { disk in
                    DiskRow(disk: disk)
                }
                Text("Read \(rate(snapshot.diskIo?.readRate)) · Write \(rate(snapshot.diskIo?.writeRate))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let trash = snapshot.trashSize, trash > 0 {
                    Text("Trash holds \(trash.fileSize)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rate(_ megabytesPerSecond: Double?) -> String {
        bytesPerSecond(megabytesPerSecond ?? 0)?.rate ?? "—"
    }
}
