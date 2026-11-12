import BurrowCore
import SwiftUI

struct MemoryCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        let memory = snapshot.memory
        return Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                StatusCardTitle(title: "Memory", symbol: "memorychip")
                StatusPercentReadout(percent: memory?.usedPercent ?? 0)
                Sparkline(values: store.memoryHistory, sampleID: store.sampleCount, tint: .blue, maximum: 100)
                Text("\((memory?.used ?? 0).memorySize) of \((memory?.total ?? 0).memorySize) · \((memory?.swapUsed ?? 0).memorySize) swap")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
