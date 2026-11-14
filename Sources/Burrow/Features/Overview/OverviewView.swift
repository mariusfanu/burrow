import BurrowCore
import SwiftUI

/// The front door: the ground itself shows how full the disk is, and the sky holds the one
/// number most people came to see.
struct OverviewView: View {
    let cli: CLIInfo
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Nine tools sit best as three rows of three. Narrower windows step down instead of
    /// leaving one tile alone on the last row.
    @State private var columnCount = 3
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Space.cluster, alignment: .top), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverviewHero(cli: cli)
                VStack(alignment: .leading, spacing: Theme.Space.group) {
                    LazyVGrid(columns: columns, spacing: Theme.Space.cluster) {
                        ForEach(Screen.tools.enumerated(), id: \.element) { index, screen in
                            OverviewToolTile(screen: screen, fact: fact(for: screen))
                                .arrives(index: index)
                        }
                    }
                    .onGeometryChange(for: Int.self) { proxy in
                        switch proxy.size.width {
                        case 700...: 3
                        case 460..<700: 2
                        default: 1
                        }
                    } action: { count in
                        withAnimation(Motion.glide(reduced: reduceMotion)) { columnCount = count }
                    }
                    OverviewRecentActivity(sessions: recentSessions)
                }
                .padding(Theme.Space.page)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .scrollEdgeEffectHidden(true, for: .top)
        .task(loadHistory)
    }

    @Sendable
    private func loadHistory() async {
        app.history.load(cli: cli)
    }

    private var recentSessions: [HistoryReport.Session] {
        Array(
            (app.history.report?.sessions ?? [])
                .filter { !$0.isPreview && $0.recordedWork }
                .prefix(3)
        )
    }

    /// Something true about each tool right now, where there's something to say.
    private func fact(for screen: Screen) -> String {
        switch screen {
        case .clean where app.clean.state == .review:
            return "\(app.clean.report.potentialBytes.fileSize) can be reclaimed"
        case .uninstall where !app.uninstall.apps.isEmpty:
            return "\(app.uninstall.apps.count) apps installed"
        case .status:
            guard let snapshot = app.status.snapshot else { return screen.summary }
            return "CPU \(percent(snapshot.cpu?.usage)) · Memory \(percent(snapshot.memory?.usedPercent))"
        case .analyze:
            guard let trash = app.status.snapshot?.trashSize, trash > 0 else { return screen.summary }
            return "Trash holds \(trash.fileSize)"
        default:
            return screen.summary
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value, let percent = Int(exactly: value.rounded(.towardZero)) else { return "—" }
        return "\(percent)%"
    }
}
