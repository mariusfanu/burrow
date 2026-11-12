import BurrowCore
import SwiftUI

struct CPUCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                StatusCardTitle(title: "CPU", symbol: "cpu")
                StatusPercentReadout(percent: snapshot.cpu?.usage ?? 0)
                Sparkline(values: store.cpuHistory, sampleID: store.sampleCount, maximum: 100)
                if let perCore = snapshot.cpu?.perCore, !perCore.isEmpty {
                    CoreBars(values: perCore)
                }
                Text("Load \((snapshot.cpu?.load1 ?? 0).formatted(.number.precision(.fractionLength(2)))) · \(snapshot.cpu?.coreCount ?? 0) cores")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
