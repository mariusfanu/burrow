import BurrowCore
import SwiftUI

struct GPUCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        let gpu = snapshot.gpu?.first
        return Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                StatusCardTitle(title: "GPU", symbol: "display")
                if let usage = gpu?.usage, usage >= 0 {
                    StatusValueLine(value: usage.formatted(.number.precision(.fractionLength(0))), unit: "%", number: usage)
                    LevelBar(fraction: usage / 100, tint: StatusTint.load(usage))
                } else {
                    Text("Usage isn’t reported")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text([gpu?.name, gpu?.coreCount.map { "\($0) cores" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
