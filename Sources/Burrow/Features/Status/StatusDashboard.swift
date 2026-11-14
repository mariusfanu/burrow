import BurrowCore
import SwiftUI

struct StatusDashboard: View {
    let store: StatusStore
    let snapshot: StatusSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnCount = 3

    /// Returns the responsive grid column count for the available container width.
    nonisolated static func columns(forWidth width: CGFloat) -> Int {
        switch width {
        case 700...: 3
        case 460..<700: 2
        default: 1
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Space.cluster, alignment: .top), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.cluster) {
                StatusHealthStrip(snapshot: snapshot, sampleID: store.sampleCount, isLive: store.hasFreshSample && store.errorMessage == nil)
                    .arrives()
                if let message = store.errorMessage {
                    InlineNotice(text: message)
                }
                LazyVGrid(columns: columns, spacing: Theme.Space.cluster) {
                    CPUCard(snapshot: snapshot, store: store).arrives(index: 1)
                    MemoryCard(snapshot: snapshot, store: store).arrives(index: 2)
                    NetworkCard(snapshot: snapshot, store: store).arrives(index: 3)
                    DiskCard(snapshot: snapshot).arrives(index: 4)
                    GPUCard(snapshot: snapshot).arrives(index: 5)
                    PowerCard(snapshot: snapshot).arrives(index: 6)
                }
                .onGeometryChange(for: Int.self) { proxy in
                    Self.columns(forWidth: proxy.size.width)
                } action: { count in
                    withAnimation(Motion.glide(reduced: reduceMotion)) { columnCount = count }
                }
                if let bluetooth = snapshot.bluetooth, bluetooth.contains(where: { $0.connected == true }) {
                    BluetoothCard(devices: bluetooth)
                        .arrives(index: 7)
                        .transition(Motion.rise(reduced: reduceMotion))
                }
                ProcessCard(snapshot: snapshot).arrives(index: 8)
            }
            .padding(Theme.Space.page)
        }
    }
}
