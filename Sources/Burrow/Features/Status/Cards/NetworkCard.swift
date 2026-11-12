import BurrowCore
import SwiftUI

struct NetworkCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                StatusCardTitle(title: "Network", symbol: "network")
                HStack(spacing: Theme.Space.wide) {
                    RateTile(label: "Down", symbol: "arrow.down", rate: snapshot.totalDownload)
                    RateTile(label: "Up", symbol: "arrow.up", rate: snapshot.totalUpload)
                }
                Sparkline(values: store.downloadHistory, sampleID: store.sampleCount, tint: .green)
                if let address = snapshot.network?.first(where: { !($0.ip ?? "").isEmpty }) {
                    Text("\(address.name ?? "") · \(address.ip ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if snapshot.proxy?.enabled == true {
                    Text("Proxy \(snapshot.proxy?.type ?? "") · \(snapshot.proxy?.host ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
