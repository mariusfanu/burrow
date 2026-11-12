import BurrowCore
import SwiftUI

/// One map: either its tiles, or the folder's own color while it's being measured.
struct TreemapLayer: View {
    let snapshot: MapSnapshot
    let model: AnalyzeModel
    let cli: CLIInfo
    let isInteractive: Bool

    var body: some View {
        GeometryReader { proxy in
            if snapshot.isLoading, snapshot.entries.isEmpty {
                MeasuringPlate(name: snapshot.name, tint: snapshot.tint)
                    .transition(.opacity)
            } else if snapshot.entries.isEmpty {
                ContentUnavailableView(model.emptyStateTitle, systemImage: "folder")
            } else {
                tiles(in: proxy.size)
            }
        }
        .animation(Motion.isReduced ? nil : Motion.lift, value: snapshot.entries.map(\.id))
    }

    private func tiles(in size: CGSize) -> some View {
        let map = EntryMap(entries: snapshot.entries, in: CGRect(origin: .zero, size: size))
        let lookup = Dictionary(map.shown.enumerated().map { ($0.element.path, $0) }, uniquingKeysWith: { first, _ in first })

        return ZStack(alignment: .topLeading) {
            ForEach(map.tiles, id: \.id) { tile in
                if let found = lookup[tile.id] {
                    TreemapTile(
                        entry: found.element,
                        rank: found.offset,
                        color: Theme.tile(rank: found.offset, parent: snapshot.tint),
                        rect: tile.rect,
                        container: size,
                        isSelected: model.selection.contains(found.element.path),
                        isInteractive: isInteractive,
                        model: model,
                        cli: cli
                    )
                    .transition(Motion.content(scale: 0.7))
                } else {
                    SmallItemsTile(count: map.restCount, size: map.restSize, rect: tile.rect)
                }
            }
        }
    }
}
