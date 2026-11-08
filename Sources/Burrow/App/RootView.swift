import AppKit
import BurrowCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(selection: $model.selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 280)
        } detail: {
            PageHost()
                .toolbar { AppToolbar() }
        }
        .navigationTitle(model.selection.title)
        .navigationSubtitle(model.subtitle)
        .task { await model.locateCLI() }
        #if DEBUG
        .onAppear { model.openSettingsForDebug = { openSettings() } }
        .tint(ProcessInfo.processInfo.environment["BURROW_ACCENT"] == nil ? nil : Color(hex: Theme.accent))
        #endif
        .background { WindowVisibilityObserver(changed: model.setWindowVisible).frame(width: 0, height: 0) }
        .disabled(model.isShuttingDown)
    }
}

/// Shows the current page and carries the transition between pages.
private struct PageHost: View {
    @Environment(AppModel.self) private var model
    /// Bumps when the system accent changes, so that derived colors follow it.
    @State private var accentRevision = 0
    /// The CLI version whose compatibility note has been dismissed.
    @AppStorage("dismissedCLINotice") private var dismissedNoticeVersion = ""

    private var compatibilityNotice: String? {
        guard let cli = model.cli, cli.version != dismissedNoticeVersion else { return nil }
        return CLICompatibility(version: cli.version).warning(version: cli.version)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if model.isLocating, model.cli == nil {
                    WorkingView(title: "Looking for the Mole CLI")
                } else if let cli = model.cli {
                    PageContent(screen: model.selection, cli: cli)
                        .id("\(model.selection.rawValue)-\(accentRevision)")
                        .transition(Motion.page(movingDown: model.movedDown))
                } else {
                    MissingCLIView()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            if let notice = compatibilityNotice {
                Divider()
                NoticeBar(text: notice) { dismissedNoticeVersion = model.cli?.version ?? "" }
            }
        }
        .animation(Motion.glide, value: model.selection)
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            accentRevision += 1
        }
    }
}

private struct PageContent: View {
    let screen: Screen
    let cli: CLIInfo
    @Environment(AppModel.self) private var model

    var body: some View {
        if !cli.hasBundledTools, screen == .status || screen == .analyze {
            ContentUnavailableView(
                "This Copy of Mole Is Missing a Tool",
                systemImage: "wrench.adjustable",
                description: Text("\(screen.title) uses the status and analyze programs that come with Mole releases. Install a release with Homebrew, or choose another copy in Settings.")
            )
        } else {
            switch screen {
            case .overview: OverviewView(cli: cli)
            case .clean: CleanView(model: model.clean, cli: cli)
            case .uninstall: UninstallView(model: model.uninstall, cli: cli)
            case .purge: MenuFlowView(model: model.purge, cli: cli)
            case .installers: MenuFlowView(model: model.installers, cli: cli)
            case .slim: MenuFlowView(model: model.slim, cli: cli)
            case .optimize: OptimizeView(model: model.optimize, cli: cli)
            case .analyze: AnalyzeView(model: model.analyze, cli: cli)
            case .status: StatusView(store: model.status)
            case .history: HistoryView(model: model.history, cli: cli)
            }
        }
    }
}

/// The window's trailing controls: the page's commands, then its one prominent action.
private struct AppToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .automatic) {
            Toggle("Preview Mode", systemImage: model.effectivePreview ? "eye.fill" : "eye", isOn: $model.previewMode)
                .disabled(!model.isPreviewToggleEnabled)
                .contentTransition(.symbolEffect(.replace))
                .help(model.previewToggleHelp)
        }
        if !model.attentionScreens.isEmpty {
            ToolbarItem(placement: .automatic) {
                Menu("Needs Attention", systemImage: "exclamationmark.circle") {
                    ForEach(model.attentionScreens) { screen in
                        Button("Continue \(screen.title)") { model.selection = screen }
                    }
                }
                .help("A command on another page is waiting for your answer")
            }
        }
        if let secondary = model.secondaryAction {
            ToolbarItem(placement: .automatic) {
                SecondaryToolbarButton(action: secondary)
            }
        }
        if let primary = model.primaryAction, primary.showsInToolbar {
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(action: primary)
            }
        }
    }
}

/// A refresh shows only its symbol and spins once when clicked. Cancel is spelled out.
private struct SecondaryToolbarButton: View {
    let action: PageAction
    @State private var turns = 0

    var body: some View {
        Group {
            if let symbol = action.symbol {
                Button(action: refresh) {
                    Label(action.title, systemImage: symbol)
                        .symbolEffect(.rotate, options: .speed(2), value: turns)
                }
                .help(action.title)
            } else {
                Button(action.title, action: action.perform)
            }
        }
        .disabled(!action.isEnabled)
    }

    private func refresh() {
        if !Motion.isReduced { turns += 1 }
        action.perform()
    }
}

private struct PrimaryToolbarButton: View {
    let action: PageAction

    var body: some View {
        Button(action: action.perform) {
            Text(action.title)
                .contentTransition(.numericText())
                .animation(Motion.snap, value: action.title)
        }
        .buttonStyle(.glassProminent)
        .disabled(!action.isEnabled)
    }
}

struct SidebarView: View {
    @Binding var selection: Screen

    var body: some View {
        List(selection: $selection) {
            ForEach(Screen.groups) { group in
                if let title = group.title {
                    Section(title) { SidebarRows(screens: group.screens) }
                } else {
                    SidebarRows(screens: group.screens)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRows: View {
    let screens: [Screen]
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(screens) { screen in
            SidebarRow(
                screen: screen,
                isSelected: model.selection == screen,
                isWorking: model.isWorking(screen),
                needsAttention: model.needsAttention(screen),
                badge: model.badge(for: screen)
            )
            .tag(screen)
        }
    }
}

/// One sidebar row. Its icon answers a selection, and its trailing edge shows that a page
/// has work under way or a result waiting.
private struct SidebarRow: View {
    let screen: Screen
    let isSelected: Bool
    let isWorking: Bool
    let needsAttention: Bool
    let badge: String?

    @State private var selectionCount = 0

    var body: some View {
        HStack {
            Label {
                Text(screen.title)
            } icon: {
                Image(systemName: screen.symbol)
                    .symbolEffect(.bounce, options: .speed(1.5), value: selectionCount)
            }
            Spacer(minLength: 4)
            if needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs Attention")
                    .help("This command is waiting for your answer")
            } else if isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .transition(Motion.materialize)
                    .accessibilityLabel("Working")
            } else if let badge {
                Text(badge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.settle, value: isWorking)
        .animation(Motion.settle, value: badge)
        .onChange(of: isSelected) {
            if isSelected, !Motion.isReduced { selectionCount += 1 }
        }
    }
}

/// Shown when no copy of the CLI can be found.
struct MissingCLIView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ToolIntro(
            symbol: "terminal",
            title: "Burrow Needs the Mole CLI",
            message: "Burrow is a window onto the free, open-source Mole command-line tool. Install it, then check again.",
            errorMessage: model.cliChoiceError
        ) {
            Text("brew install mole")
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Space.cluster)
                .padding(.vertical, Theme.Space.snug)
                .background(.fill.quaternary, in: .rect(cornerRadius: Theme.Radius.inset))
            HStack {
                Button("Choose CLI…", action: choose)
                Button("Check Again", action: checkAgain)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func choose() {
        guard let path = FilePicker.chooseFile(prompt: "Use This CLI") else { return }
        Task { await model.useCustomCLI(path: path) }
    }

    private func checkAgain() {
        Task { await model.locateCLI() }
    }
}
