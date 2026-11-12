import BurrowCore
import SwiftUI

struct StatusDashboard: View {
    let store: StatusStore
    let snapshot: StatusSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.cluster) {
                StatusHealthStrip(snapshot: snapshot, sampleID: store.sampleCount, isLive: store.isRunning && store.errorMessage == nil)
                    .arrives()
                if let message = store.errorMessage {
                    InlineNotice(text: message)
                }
                Grid(horizontalSpacing: Theme.Space.cluster, verticalSpacing: Theme.Space.cluster) {
                    GridRow {
                        CPUCard(snapshot: snapshot, store: store).arrives(index: 1)
                        MemoryCard(snapshot: snapshot, store: store).arrives(index: 2)
                        NetworkCard(snapshot: snapshot, store: store).arrives(index: 3)
                    }
                    GridRow {
                        DiskCard(snapshot: snapshot).arrives(index: 4)
                        GPUCard(snapshot: snapshot).arrives(index: 5)
                        PowerCard(snapshot: snapshot).arrives(index: 6)
                    }
                }
                if let bluetooth = snapshot.bluetooth, bluetooth.contains(where: { $0.connected == true }) {
                    BluetoothCard(devices: bluetooth)
                        .arrives(index: 7)
                        .transition(Motion.rise)
                }
                ProcessCard(snapshot: snapshot).arrives(index: 8)
            }
            .padding(Theme.Space.page)
        }
    }
}
