import BurrowCore
import SwiftUI

/// One map: either its tiles, or the folder's own color while it's being measured.
struct TreemapLayer: View {
    let snapshot: MapSnapshot
    let model: AnalyzeModel
    let cli: CLIInfo
    let isInteractive: Bool
    @Environment(\.accentRevision) private var accentRevision
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = accentRevision
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
        .animation(Motion.isReduced(reduceMotion) ? nil : Motion.lift(reduced: reduceMotion), value: AnimationKey(id: snapshot.id, count: snapshot.entries.count))
    }

    private struct AnimationKey: Equatable {
        let id: String
        let count: Int
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
                        isInteractive: isInteractive,
                        model: model,
                        cli: cli
                    )
                    .transition(Motion.content(scale: 0.7, reduced: reduceMotion))
                } else {
                    SmallItemsTile(count: map.restCount, size: map.restSize, rect: tile.rect)
                }
            }
        }
    }
}
