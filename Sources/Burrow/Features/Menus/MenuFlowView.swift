import AppKit
import BurrowCore
import SwiftUI

struct MenuFlowView: View {
    let model: MenuFlowModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                MenuFlowIntro(model: model, cli: cli)
                    .transition(Motion.materialize)
            case .scanning:
                WorkingView(
                    title: model.configuration.scanTitle,
                    detail: model.readProgress.isEmpty ? model.run.activity : model.readProgress
                )
            case .choosing:
                MenuFlowList(model: model)
                    .transition(Motion.materialize)
            case .applying:
                WorkingView(title: "Applying Your Selection", detail: "Checking each row")
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .onChange(of: app.effectivePreview) { abandonIfPreviewChanged() }
        .onAppear(perform: abandonIfPreviewChanged)
    }

    /// A menu started in one mode must not be confirmed in the other.
    private func abandonIfPreviewChanged() {
        guard model.state == .choosing, model.isPreviewRun != app.effectivePreview else { return }
        model.abandon(because: MenuFlowModel.previewChangedReason)
    }
}

private struct MenuFlowIntro: View {
    @Bindable var model: MenuFlowModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        ToolIntro(
            symbol: model.configuration.screen.symbol,
            title: model.configuration.idleTitle,
            message: model.configuration.idleMessage,
            errorMessage: model.errorMessage
        ) {
            if model.configuration.managesScanPaths {
                Toggle("Include Empty Folders", isOn: $model.includeEmptyFolders)
                    .toggleStyle(.checkbox)
            }
            HStack {
                if model.configuration.managesScanPaths {
                    Button("Scan Locations…", action: editPaths)
                        .controlSize(.large)
                }
                Button("Scan", action: scan)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $model.isEditingPaths) {
            PurgePathsSheet()
        }
    }

    private func scan() {
        model.scan(cli: cli, preview: app.effectivePreview)
    }

    private func editPaths() {
        model.isEditingPaths = true
    }
}

private struct MenuFlowList: View {
    let model: MenuFlowModel
    /// The row under keyboard focus, which arrow keys move and Space toggles.
    @State private var focusedRow: MenuItem.ID?

    var body: some View {
        let largestBytes = model.items.map(\.bytes).max() ?? 0
        List(selection: $focusedRow) {
            ForEach(model.items.enumerated(), id: \.element.id) { index, item in
                MenuItemRow(
                    item: item,
                    largestBytes: largestBytes,
                    isSelected: model.selection.contains(item.index),
                    toggle: { toggle(item) }
                )
                .tag(item.id)
                .arrives(index: index)
            }
        }
        .onKeyPress(.space, action: toggleFocused)
        .onCommand(#selector(NSResponder.selectAll(_:)), perform: selectAll)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            NoticeBar(text: model.configuration.subtitle, symbol: "")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu("Select", systemImage: "checklist") {
                    Button("Select All", action: selectAll)
                    Button("Deselect All", action: deselectAll)
                }
                .help("Select or deselect every row")
            }
        }
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView(model.configuration.emptyTitle, systemImage: model.configuration.screen.symbol)
            }
        }
    }

    private func toggleFocused() -> KeyPress.Result {
        guard let item = model.items.first(where: { $0.id == focusedRow }) else { return .ignored }
        toggle(item)
        return .handled
    }

    private func toggle(_ item: MenuItem) {
        focusedRow = item.id
        withAnimation(Motion.snap) {
            if model.selection.contains(item.index) {
                model.selection.remove(item.index)
            } else {
                model.selection.insert(item.index)
            }
        }
    }

    private func selectAll() {
        withAnimation(Motion.snap) { model.selection = Set(model.items.map(\.index)) }
    }

    private func deselectAll() {
        withAnimation(Motion.snap) { model.selection = [] }
    }
}

private struct MenuItemRow: View {
    let item: MenuItem
    let largestBytes: Int64
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.cluster) {
            Toggle("Select \(item.name)", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: Theme.Space.micro) {
                Text(item.path?.abbreviatingHome ?? item.name)
                    .font(.body)
                    .bold(isSelected)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path ?? item.rowText)
                if item.path != nil {
                    Text(item.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let tag = item.tag {
                FactTag(text: tag, tint: .blue)
            }
            if let age = item.age {
                FactTag(text: age)
            }
            VStack(alignment: .trailing, spacing: Theme.Space.tight) {
                Text(item.sizeText ?? "")
                    .font(.callout)
                    .monospacedDigit()
                LevelBar(part: item.bytes, of: largestBytes, height: 3)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
        .animation(Motion.snap, value: isSelected)
    }
}

/// Edits the folders `mo purge` scans.
struct PurgePathsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var paths: [String] = []
    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var loadFailed = false

    private let store = PurgePathsStore(home: AppModel.home)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.card) {
            Text("Scan Locations")
                .font(.title3)
                .bold()
            Text("With no folders listed here, Mole looks in common project locations such as ~/Developer and ~/Projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(paths, id: \.self, selection: $selection) { path in
                Text(path)
                    .font(.callout.monospaced())
            }
            .frame(height: 180)
            HStack {
                Button("Add Folder…", action: addFolder)
                Button("Remove", action: removeSelected)
                    .disabled(selection == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loadFailed || app.effectivePreview)
                    .help(app.effectivePreview ? "Turn off Preview Mode to change these" : "Save these locations")
            }
            if let errorMessage {
                InlineNotice(text: errorMessage, tint: .red)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            paths = try store.load()
        } catch {
            loadFailed = true
            errorMessage = "The current list couldn’t be read, so it can’t be edited here: \(error.localizedDescription)"
        }
    }

    private func addFolder() {
        if let path = FilePicker.chooseFolder(prompt: "Add"), !paths.contains(path.abbreviatingHome) {
            paths.append(path.abbreviatingHome)
        }
    }

    private func removeSelected() {
        paths.removeAll { $0 == selection }
        selection = nil
    }

    private func save() {
        guard !loadFailed, !app.effectivePreview else { return }
        do {
            try store.save(paths)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
