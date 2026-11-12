import BurrowCore
import SwiftUI

/// The front door: the ground itself shows how full the disk is, and the sky holds the one
/// number most people came to see.
struct OverviewView: View {
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    /// Nine tools sit best as three rows of three. Narrower windows step down instead of
    /// leaving one tile alone on the last row.
    @State private var columnCount = 3
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Space.cluster, alignment: .top), count: columnCount)
    }
    private let tools: [Screen] = [.clean, .uninstall, .purge, .installers, .slim, .optimize, .analyze, .status, .history]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverviewHero(cli: cli)
                VStack(alignment: .leading, spacing: Theme.Space.group) {
                    LazyVGrid(columns: columns, spacing: Theme.Space.cluster) {
                        ForEach(tools.enumerated(), id: \.element) { index, screen in
                            ToolTile(screen: screen, fact: fact(for: screen))
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
                        withAnimation(Motion.glide) { columnCount = count }
                    }
                    RecentActivity(sessions: recentSessions)
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
        guard let percent = Int(exactly: (value ?? 0).rounded(.towardZero)) else { return "—" }
        return "\(percent)%"
    }
}

private struct OverviewHero: View {
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    private var disk: StatusSnapshot.Disk? { app.status.snapshot?.rootDisk }
    private var used: Int64 { max(disk?.used ?? 0, 0) }
    private var total: Int64 { max(disk?.total ?? 0, 0) }
    private var free: Int64 { max(total - used, 0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            StrataScene(usedFraction: total > 0 ? Double(used) / Double(total) : 0)
                .mask {
                    // The scene melts into the page instead of ending at a hard edge.
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .backgroundExtensionEffect()
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                Spacer(minLength: 56)
                // Until the disk is measured, a soft placeholder holds the number's place, so
                // nothing jumps when it lands.
                HeroNumber(text: total > 0 ? free.fileSize : "000.00 GB", size: 52, value: Double(free))
                    .redacted(reason: total > 0 ? [] : .placeholder)
                    .accessibilityHidden(total == 0)
                Text(diskCaption)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                HStack {
                    Button("Scan for Space", action: scan)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    Button("Explore Disk", action: explore)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(.top, Theme.Space.item)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.page + 4)
            .accessibilityElement(children: .contain)
        }
        .frame(height: 350)
        .animation(Motion.settle, value: total > 0)
    }

    private var diskCaption: String {
        if total > 0 { return "available · \(used.fileSize) of \(total.fileSize) used" }
        // Only Mole's status tool reports this, so without it there's nothing to wait for.
        if !cli.hasBundledTools || app.status.errorMessage != nil { return "Disk usage isn’t available" }
        return "Measuring your disk"
    }

    private func scan() {
        app.selection = .clean
        if app.clean.state == .idle { app.clean.scan(cli: cli) }
    }

    private func explore() {
        app.selection = .analyze
    }
}

private struct ToolTile: View {
    let screen: Screen
    let fact: String
    @Environment(AppModel.self) private var app
    @State private var hoverCount = 0

    var body: some View {
        Button(action: open) {
            Surface(padding: Theme.Space.card) {
                HStack(spacing: Theme.Space.cluster) {
                    Image(systemName: screen.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, options: .speed(1.4), value: hoverCount)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.micro) {
                        Text(screen.title)
                            .font(.body)
                            .bold()
                        Text(fact)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(Motion.snap, value: fact)
                    }
                    Spacer(minLength: 0)
                }
            }
            .modifier(PointerGlow(color: .accentColor, strength: 0.1, radius: 160))
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(SurfaceButtonStyle())
        .onHover(perform: hover)
        .accessibilityHint(screen.summary)
    }

    private func open() {
        app.selection = screen
    }

    private func hover(_ inside: Bool) {
        if inside, !Motion.isReduced { hoverCount += 1 }
    }
}

private struct RecentActivity: View {
    let sessions: [HistoryReport.Session]
    @Environment(AppModel.self) private var app

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                HStack {
                    Text("Recent Activity")
                        .font(.headline)
                    Spacer()
                    Button("All History", action: showHistory)
                        .buttonStyle(.link)
                }
                Surface(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(sessions.enumerated(), id: \.element.id) { index, session in
                            if index > 0 {
                                Divider().padding(.leading, 48)
                            }
                            RecentSessionRow(session: session)
                        }
                    }
                }
            }
            .arrives(index: 9)
        }
    }

    private func showHistory() {
        app.selection = .history
    }
}

private struct RecentSessionRow: View {
    let session: HistoryReport.Session

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: session.symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(session.title)
                .bold()
            Text(session.startedText)
                .foregroundStyle(.secondary)
                .help(session.startedAt ?? "")
            Spacer(minLength: Theme.Space.item)
            if let items = session.itemsText {
                Text(items)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Sessions that freed nothing still say what they did.
            Text(session.sizeText ?? session.actionSummary)
                .foregroundStyle(session.sizeText == nil ? .secondary : .primary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.card)
        .padding(.vertical, Theme.Space.item)
        .accessibilityElement(children: .combine)
    }
}
