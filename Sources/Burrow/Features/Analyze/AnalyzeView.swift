import BurrowCore
import SwiftUI

struct AnalyzeView: View {
    let model: AnalyzeModel
    let cli: CLIInfo
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            AnalyzePathBar(model: model, cli: cli)
                .disabled(model.isTrashing)
            AnalyzeContent(model: model, cli: cli)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Open Folder…", systemImage: "folder", action: chooseFolder)
                    .disabled(model.isTrashing)
            }
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.backward", action: goBack)
                    .disabled(!model.canGoBack || model.isTrashing)
                    .help("Go to the enclosing folder")
            }
        }
        .task(start)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.noticeMessage) { Announcer.say(model.noticeMessage) }
        .onChange(of: model.errorMessage) { Announcer.say(model.errorMessage) }
        .alert(model.pendingTrash?.title ?? "", isPresented: $model.isConfirmingTrash) {
            // Return mustn't be the way a high-risk move happens.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Move to Trash") { model.confirmPendingTrash(cli: cli) }
        } message: {
            Text(model.pendingTrash?.message ?? "")
        }
    }

    @Sendable
    private func start() async {
        model.openRoot(cli: cli)
    }

    private func goBack() {
        model.goBack(cli: cli)
    }

    private func chooseFolder() {
        guard let path = FilePicker.chooseFolder(prompt: "Explore") else { return }
        model.openPath(path, cli: cli)
    }
}

/// The path to the current folder. Each step carries its branch's color, and on the far side
/// sits a readout of whatever the pointer is over.
private struct AnalyzePathBar: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        HStack(spacing: Theme.Space.snug) {
            ForEach(model.levels.enumerated(), id: \.element.id) { depth, level in
                if depth > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                PathStep(level: level, isCurrent: depth == model.levels.count - 1) {
                    model.jump(toDepth: depth, cli: cli)
                }
                .transition(Motion.rise)
            }
            Spacer(minLength: 12)
            AnalyzeReadout(model: model)
        }
        .animation(Motion.settle, value: model.levels)
        // Lines up with the treemap's edge and the list's sizes below, not the page margin.
        .padding(.leading, Theme.Space.cluster)
        .padding(.trailing, Theme.Space.group)
        .padding(.vertical, Theme.Space.item)
        .frame(minHeight: 40)
    }
}

private struct PathStep: View {
    let level: AnalyzeLevel
    let isCurrent: Bool
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: 5) {
                if let tint = level.tint {
                    Circle()
                        .fill(Color(hex: tint))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(level.name)
                    .bold(isCurrent)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(level.path ?? "The overview of this Mac")
    }
}

private struct AnalyzeReadout: View {
    let model: AnalyzeModel

    private var hoveredEntry: AnalyzeResult.Entry? {
        model.entries.first { $0.path == model.hovered }
    }

    var body: some View {
        HStack(spacing: Theme.Space.row) {
            if let entry = hoveredEntry {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.size.fileSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let total = model.result?.totalSize, total > 0 {
                    Text(Double(entry.size) / Double(total), format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if let total = model.result?.totalSize {
                Text(total.fileSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(total)))
            }
            if model.result?.isPartial == true {
                FactTag(text: "Partial Scan", tint: .orange)
                    .help("Some folders took too long and weren’t measured")
            }
        }
        .font(.callout)
        .animation(Motion.snap, value: model.hovered)
    }
}

private struct AnalyzeContent: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        HSplitView {
            TreemapStage(model: model, cli: cli)
                .overlay(alignment: .top) {
                    AnalyzeNotices(model: model, cli: cli)
                        .padding(Theme.Space.item)
                }
                .animation(Motion.settle, value: model.noticeMessage)
                .animation(Motion.settle, value: model.errorMessage)
                .padding([.horizontal, .bottom], Theme.Space.item)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            AnalyzeEntryList(model: model, cli: cli)
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
        }
    }
}

private struct AnalyzeNotices: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        VStack(spacing: Theme.Space.row) {
            if let notice = model.noticeMessage {
                GlassToast(
                    text: notice,
                    undo: undoAction,
                    dismiss: model.dismissNotice
                )
            }
            if let error = model.errorMessage {
                InlineNotice(text: error, tint: .red) { model.errorMessage = nil }
                    .frame(maxWidth: 520)
            }
        }
    }

    private var undoAction: (() -> Void)? {
        guard model.lastTrashed != nil else { return nil }
        return { model.undoTrash(cli: cli) }
    }
}

/// The same entries as the map, with native selection, arrow keys and Return to open.
private struct AnalyzeEntryList: View {
    @Bindable var model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.entries.enumerated(), id: \.element.id) { rank, entry in
                EntryRow(
                    entry: entry,
                    tint: Theme.tile(rank: rank, parent: model.current?.tint),
                    total: model.result?.totalSize ?? 0,
                    model: model,
                    canTrash: model.canTrash(entry)
                )
                .tag(entry.path)
                .onHover { inside in model.setHovered(entry.path, inside: inside) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(Motion.lift, value: model.entries)
        .onChange(of: model.selection) { old, new in model.noteSelection(added: new.subtracting(old)) }
        .contextMenu(forSelectionType: String.self) { paths in
            EntryMenu(paths: paths, model: model, cli: cli)
        } primaryAction: { paths in
            open(paths)
        }
        .overlay {
            if !model.isLoading, model.entries.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(model.emptyStateTitle, systemImage: "folder")
            }
        }
    }

    private func open(_ paths: Set<String>) {
        guard let path = paths.first,
              let rank = model.entries.firstIndex(where: { $0.path == path }) else { return }
        let entry = model.entries[rank]
        if entry.isDir {
            let tint = Theme.tile(rank: rank, parent: model.current?.tint)
            model.open(entry, tint: tint, rect: model.tileRect(for: entry), cli: cli)
        } else {
            FilePicker.reveal(entry.path)
        }
    }
}

private struct EntryMenu: View {
    let paths: Set<String>
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        if let path = paths.first {
            Button("Show in Finder") { FilePicker.reveal(path) }
        }
        Button(model.needsConfirmation(toTrash: paths) ? "Move to Trash…" : "Move to Trash") {
            model.selection = paths
            model.trashSelection(cli: cli)
        }
        .disabled(paths.isEmpty || !model.entries.filter { paths.contains($0.path) }.allSatisfy(model.canTrash))
    }
}

private struct EntryRow: View {
    let entry: AnalyzeResult.Entry
    let tint: UInt32
    let total: Int64
    /// Read here, not in the list, so that moving the pointer only touches the rows.
    let model: AnalyzeModel
    let canTrash: Bool

    private var isHovered: Bool { model.hovered == entry.path }

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: entry.isDir ? "folder.fill" : "doc")
                .foregroundStyle(Color(hex: tint))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                HStack(spacing: Theme.Space.snug) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.cleanable == true {
                        FactTag(text: "Cleanable", tint: .green)
                    }
                    if !canTrash {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Protected")
                    }
                }
                LevelBar(
                    part: entry.size,
                    of: total,
                    tint: Color(hex: tint),
                    height: 3
                )
            }
            Text(entry.size.fileSize)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.micro)
        .opacity(isHovered ? 1 : 0.94)
    }
}
