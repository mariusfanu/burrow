import BurrowCore
import SwiftUI

/// Processes glide to their new positions when the order changes, so you can follow one.
struct ProcessCard: View {
    let snapshot: StatusSnapshot
    @State private var sortsByMemory = false

    private var sortedProcesses: [StatusSnapshot.Process] {
        let all = snapshot.topProcesses ?? []
        return sortsByMemory
            ? all.sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
            : all.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }
    }

    var body: some View {
        let processes = sortedProcesses
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.item) {
                HStack {
                    StatusCardTitle(title: "Top Processes", symbol: "list.bullet")
                    Spacer()
                    Picker("Sort Processes By", selection: $sortsByMemory) {
                        Text("CPU").tag(false)
                        Text("Memory").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                ProcessHeaderRow()
                // Rows update in place, as in Activity Monitor. This table reorders every
                // couple of seconds, and sliding or fading rows smeared names across each
                // other mid-move.
                VStack(spacing: Theme.Space.snug) {
                    ForEach(processes) { ProcessRow(process: $0) }
                }
                .transaction { $0.animation = nil }
            }
        }
    }
}
