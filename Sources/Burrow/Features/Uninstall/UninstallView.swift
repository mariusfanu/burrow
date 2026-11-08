import AppKit
import BurrowCore
import SwiftUI

struct UninstallView: View {
    let model: UninstallModel
    let cli: CLIInfo

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                ToolIntro(
                    symbol: "trash",
                    title: "Uninstall Apps Completely",
                    message: model.errorMessage ?? "See your apps with their sizes, then remove them along with the files they leave behind."
                ) {
                    Button("Load Apps", action: load)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(Motion.materialize)
            case .loading:
                WorkingView(title: "Listing Installed Apps")
            case .list:
                UninstallList(model: model)
                    .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .task(loadIfNeeded)
    }

    private func load() {
        model.load(cli: cli)
    }

    @Sendable
    private func loadIfNeeded() async {
        model.loadIfNeeded(cli: cli)
    }
}

private struct UninstallList: View {
    @Bindable var model: UninstallModel
    @Environment(AppModel.self) private var app

    @FocusState private var isSearchFocused: Bool
    /// The row under keyboard focus, which arrow keys move and Space toggles.
    @State private var focusedRow: InstalledApp.ID?

    var body: some View {
        let largestSize = model.sizes.values.max() ?? 0
        let visibleApps = model.visibleApps
        List(selection: $focusedRow) {
            ForEach(visibleApps.enumerated(), id: \.element.id) { index, item in
                AppRow(
                    app: item,
                    sizeState: model.sizeState(for: item),
                    largestSize: largestSize,
                    isSelected: model.selection.contains(item.id),
                    model: model,
                    focusedRow: $focusedRow
                )
                .tag(item.id)
                .arrives(index: index)
                .transition(Motion.content(scale: 0.96))
            }
        }
        .onKeyPress(.space, action: toggleFocused)
        .onCommand(#selector(NSResponder.selectAll(_:)), perform: selectAll)
        .onHover { inside in if inside { model.noteInteraction() } }
        .onChange(of: focusedRow) { model.noteInteraction() }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(Motion.isReduced ? nil : Motion.lift, value: model.sortOrder)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Apps")
        .searchFocused($isSearchFocused)
        .onChange(of: app.isSearchFocused) {
            if app.isSearchFocused {
                isSearchFocused = true
                app.isSearchFocused = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                UninstallOptionsMenu(model: model, isPreview: app.effectivePreview)
            }
        }
        .overlay {
            if model.apps.isEmpty {
                ContentUnavailableView("No Apps Found", systemImage: "app.dashed", description: Text("Mole didn’t list any apps it can remove."))
            } else if visibleApps.isEmpty {
                ContentUnavailableView.search
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let notice = model.activeOptionsNotice {
                NoticeBar(text: notice, dismiss: model.clearRemovalOptions)
                    .transition(Motion.rise)
            }
        }
        .alert("Delete Without Using the Trash?", isPresented: $model.isConfirmingPermanent) {
            Button("Cancel", role: .cancel) {}
            Button("Skip the Trash", role: .destructive, action: skipTrash)
        } message: {
            Text("Removed files can’t be restored. Using the Trash is the safer choice.")
        }
    }

    private func toggleFocused() -> KeyPress.Result {
        guard let item = model.apps.first(where: { $0.id == focusedRow }) else { return .ignored }
        focusedRow = item.id
        withAnimation(Motion.snap) { model.toggleSelection(item.id) }
        return .handled
    }

    private func selectAll() {
        withAnimation(Motion.snap) { model.selection = Set(model.visibleApps.map(\.id)) }
    }

    private func skipTrash() {
        model.deletePermanently = true
    }
}

/// Sorting and removal options, gathered so that the list itself stays quiet.
private struct UninstallOptionsMenu: View {
    @Bindable var model: UninstallModel
    let isPreview: Bool

    var body: some View {
        Menu("Options", systemImage: "line.3.horizontal.decrease") {
            Picker("Sort By", selection: $model.sortOrder) {
                ForEach(UninstallModel.SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            if model.hasPendingSizeSort {
                Button("Apply Size Order", systemImage: "arrow.up.arrow.down") { model.applySort() }
                    .disabled(model.isMeasuring)
            }
            Divider()
            Toggle("Include Personal Data", isOn: $model.includePersonalData)
                .help("Also removes the settings and documents these apps keep")
            Toggle("Skip the Trash…", isOn: permanent)
                .disabled(isPreview)
            Divider()
            Button("Deselect All", action: deselectAll)
                .disabled(model.selection.isEmpty)
        }
        .help("Change the sort order and removal options")
    }

    /// Turning this on asks first, because it can't be undone.
    private var permanent: Binding<Bool> {
        Binding {
            model.deletePermanently
        } set: { newValue in
            if newValue {
                model.isConfirmingPermanent = true
            } else {
                model.deletePermanently = false
            }
        }
    }

    private func deselectAll() {
        withAnimation(Motion.snap) { model.selection = [] }
    }
}

/// Local actions let unchanged rows skip other apps' measurement updates.
private struct AppRow: View {
    let app: InstalledApp
    let sizeState: UninstallModel.SizeState
    let largestSize: Int64
    let isSelected: Bool
    let model: UninstallModel
    @Binding var focusedRow: InstalledApp.ID?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.cluster) {
            Toggle("Select \(app.name)", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            AppIconView(path: app.path)
                .scaleEffect(isHovered && !Motion.isReduced ? 1.06 : 1)
            VStack(alignment: .leading, spacing: Theme.Space.micro) {
                Text(app.name)
                    .font(.body)
                    .bold(isSelected)
                    .lineLimit(1)
                Text(app.path?.abbreviatingHome ?? app.bundleId ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let source = app.source, source != "App" {
                FactTag(text: source, tint: .blue)
            }
            AppSizeColumn(app: app, state: sizeState, largestSize: largestSize, model: model)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
        .onHover { isHovered = $0 }
        .animation(Motion.snap, value: isHovered)
        .animation(Motion.snap, value: isSelected)
        .contextMenu {
            if let path = app.path {
                Button("Show in Finder") { FilePicker.reveal(path) }
            }
        }
    }

    private func toggle() {
        focusedRow = app.id
        withAnimation(Motion.snap) { model.toggleSelection(app.id) }
    }
}

/// The app's size with a small bar comparing it to the largest app.
private struct AppSizeColumn: View {
    let app: InstalledApp
    let state: UninstallModel.SizeState
    let largestSize: Int64
    let model: UninstallModel

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.tight) {
            switch state {
            case .measured(let size):
                Text(size.fileSize)
                    .font(.callout)
                    .monospacedDigit()
                    .transition(.opacity)
                LevelBar(
                    fraction: largestSize > 0 ? Double(size) / Double(largestSize) : 0,
                    height: 3
                )
            case .pending:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Measuring")
            case .unavailable:
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Size unavailable")
                    .help("A size isn’t available for this app.")
            case .failed(let message):
                Button("Retry Size", systemImage: "arrow.clockwise", action: retry)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(message)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, alignment: .trailing)
    }

    private func retry() {
        model.retrySize(for: app)
    }
}

/// An app icon from Launch Services, or a generic app symbol.
struct AppIconView: View {
    let path: String?

    var body: some View {
        Group {
            if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}
