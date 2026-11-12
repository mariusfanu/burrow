import BurrowCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AnalyzeModel {
    private(set) var levels: [AnalyzeLevel] = []
    /// The folder on show, prepared off the main actor.
    private var presentation: AnalyzePresentation?
    var result: AnalyzeResult? { presentation?.result }
    var entries: [AnalyzeResult.Entry] { presentation?.entries ?? [] }
    /// Items that are allowed in the Trash but get a second look first.
    var trashRisks: [String: TrashRisk.Reason] { presentation?.trashRisks ?? [:] }
    /// The question waiting on an answer before a high-risk selection moves.
    var pendingTrash: TrashConfirmation?

    /// Whether the high-risk question is on screen. Dismissing it drops the question.
    var isConfirmingTrash: Bool {
        get { pendingTrash != nil }
        set { if !newValue { pendingTrash = nil } }
    }

    private(set) var isLoading = false
    private(set) var isTrashing = false
    /// Set for the next map change: true when zooming in, false when zooming out.
    private(set) var isZoomingIn = true
    /// The tile to zoom toward or back to.
    private(set) var zoomRect: CGRect?
    /// The color of that tile.
    private(set) var zoomTint: UInt32?
    @ObservationIgnored var mapSize: CGSize = .zero
    private(set) var lastTrashed: TrashedBatch?
    var selection: Set<String> = []
    var hovered: String?
    private var isStale = false
    /// Tells other pages that files moved to or from the Trash.
    var onFilesMoved: (@MainActor () -> Void)?
    var errorMessage: String?
    var noticeMessage: String?
    /// The window's undo manager, so that Edit > Undo can put trashed items back.
    weak var undoManager: UndoManager?

    private var cache: [String: AnalyzePresentation] = [:]
    private var task: Task<Void, Never>?
    private var loadID = UUID()
    private let policy: ExecutionPolicy
    private let commands: CommandClient
    private let trashClient: TrashClient
    private let home: String
    private var undoActions: [UUID: TrashUndoAction] = [:]
    private var mutationTask: Task<Void, Never>?
    private var mutationCount = 0
    private(set) var isShuttingDown = false
    private let evaluateProtection: @Sendable ([AnalyzeResult.Entry], String) -> Set<String>

    init(
        policy: ExecutionPolicy,
        commands: CommandClient = CommandClient(),
        trashClient: TrashClient = TrashClient(),
        home: String = AppModel.home,
        evaluateProtection: @escaping @Sendable ([AnalyzeResult.Entry], String) -> Set<String> = AnalyzePresentation.protectedPaths
    ) {
        self.policy = policy
        self.commands = commands
        self.trashClient = trashClient
        self.home = home
        self.evaluateProtection = evaluateProtection
    }

    var current: AnalyzeLevel? { levels.last }
    var canGoBack: Bool { levels.count > 1 }
    var emptyStateTitle: String {
        if errorMessage != nil { return "This Location Couldn’t Be Scanned" }
        return result == nil ? "No Scan Results" : "Empty Folder"
    }

    var selectedEntries: [AnalyzeResult.Entry] {
        entries.filter { selection.contains($0.path) }
    }

    var selectedBytes: Int64 {
        selectedEntries.map(\.size).saturatingSum
    }

    func openRoot(cli: CLIInfo) {
        guard !isTrashing, !isShuttingDown else { return }
        guard levels.isEmpty else {
            if isStale { refresh(cli: cli) }
            return
        }
        levels = [AnalyzeLevel(path: nil, tint: nil, originRect: nil)]
        load(cli: cli, refresh: false)
    }

    /// Another page changed the disk, so what's on show may be wrong until the next look.
    func markStale() {
        cancelScan()
        isStale = true
        cache.removeAll()
        pendingTrash = nil
    }

    func invalidateCLIResults() {
        cancelScan()
        resetInteraction()
        levels = []
        cache.removeAll()
        presentation = nil
        noticeMessage = nil
    }

    /// A list selection can land on a protected row, and then there's no Move to Trash to
    /// offer, so this says why.
    func noteSelection(added: Set<String>) {
        guard let entry = entries.first(where: { added.contains($0.path) && !canTrash($0) }) else { return }
        noticeMessage = "\(entry.name) is protected, so it stays view-only."
    }

    /// Opens a folder, growing from the tile it was opened from.
    func open(_ entry: AnalyzeResult.Entry, tint: UInt32?, rect: CGRect?, cli: CLIInfo) {
        openPath(entry.path, tint: tint, rect: rect, cli: cli)
    }

    /// Opens a folder by path. Without a tile, there's nothing to grow from.
    func openPath(_ path: String, tint: UInt32? = nil, rect: CGRect? = nil, cli: CLIInfo) {
        guard !isTrashing, !isShuttingDown else { return }
        if revisit(path, cli: cli) { return }
        isZoomingIn = true
        zoomRect = rect
        zoomTint = tint
        levels.append(AnalyzeLevel(path: path, tint: tint, originRect: rect))
        resetInteraction()
        load(cli: cli, refresh: false)
    }

    func goBack(cli: CLIInfo) {
        guard canGoBack else { return }
        jump(toDepth: levels.count - 2, cli: cli)
    }

    /// Jumps to an ancestor shown in the path bar.
    func jump(toDepth depth: Int, cli: CLIInfo) {
        guard !isTrashing, !isShuttingDown, depth >= 0, depth < levels.count - 1 else { return }
        isZoomingIn = false
        // Going back one level returns to the exact tile. Further jumps zoom out from center.
        if depth == levels.count - 2, let child = levels.last {
            if let path = child.path, let parent = cache[levels[depth].id] {
                zoomRect = tileRect(for: path, in: parent.entries)
            } else {
                zoomRect = child.originRect
            }
        } else {
            zoomRect = nil
        }
        zoomTint = levels.last?.tint
        levels.removeLast(levels.count - depth - 1)
        resetInteraction()
        load(cli: cli, refresh: false)
    }

    /// Where an entry's tile sits in the current map, as fractions of the map.
    func tileRect(for entry: AnalyzeResult.Entry) -> CGRect? {
        tileRect(for: entry.path, in: entries)
    }

    private func tileRect(for path: String, in entries: [AnalyzeResult.Entry]) -> CGRect? {
        let map = EntryMap(entries: entries, in: CGRect(origin: .zero, size: mapSize))
        guard let rect = map.tiles.first(where: { $0.id == path })?.rect else { return nil }
        return EntryMap.normalized(rect, in: mapSize)
    }

    func cancelScan() {
        loadID = UUID()
        task?.cancel()
        task = nil
        isLoading = false
        if result == nil { noticeMessage = "Scan cancelled. Choose a folder or rescan to continue." }
    }

    func shutdown() async {
        isShuttingDown = true
        cancelScan()
        await mutationTask?.value
    }

    var canTrashSelection: Bool {
        !isStale && !isLoading && !isTrashing && !isShuttingDown && !selection.isEmpty
            && selectedEntries.count == selection.count && selectedEntries.allSatisfy(canTrash)
    }

    func refresh(cli: CLIInfo) {
        guard !isTrashing else { return }
        load(cli: cli, refresh: true)
    }

    /// Reopening an ancestor reuses its breadcrumb and cached presentation.
    private func revisit(_ path: String, cli: CLIInfo) -> Bool {
        guard let depth = levels.firstIndex(where: { $0.path == path }) else { return false }
        if depth < levels.count - 1 { jump(toDepth: depth, cli: cli) }
        return true
    }

    private func resetInteraction() {
        selection = []
        hovered = nil
        errorMessage = nil
        pendingTrash = nil
    }

    private func load(cli: CLIInfo, refresh: Bool, clearError: Bool = true) {
        guard !isShuttingDown else { return }
        let id = UUID()
        loadID = id
        task?.cancel()
        if clearError {
            errorMessage = nil
            noticeMessage = nil
        }
        let path = current?.path
        let key = current?.id ?? "/"
        if !refresh, let cached = cache[key] {
            presentation = cached
            isLoading = false
            return
        }
        isLoading = true
        if !refresh { presentation = nil }
        task = Task {
            defer { if loadID == id { task = nil } }
            do {
                var arguments = ["analyze", "--json"]
                if let path { arguments.append(path) }
                let output = try await commands.run(cli.executable, arguments, 600)
                try Task.checkCancellation()
                guard loadID == id else { return }
                try output.requireSuccess()
                let home = home
                let evaluate = evaluateProtection
                let prepared = try await Task.detached {
                    let parsed = try AnalyzeResult.decode(Data(output.stdout.utf8))
                    let entries = parsed.entries ?? []
                    return AnalyzePresentation(
                        result: parsed,
                        protectedPaths: evaluate(entries, home),
                        trashRisks: AnalyzePresentation.trashRisks(entries, home: home)
                    )
                }.value
                try Task.checkCancellation()
                guard loadID == id else { return }
                cache[key] = prepared
                isStale = false
                withAnimation(Motion.lift) { presentation = prepared }
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard loadID == id else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func canTrash(_ entry: AnalyzeResult.Entry) -> Bool {
        guard let presentation else { return false }
        return presentation.entryPaths.contains(entry.path) && !presentation.protectedPaths.contains(entry.path)
    }

    /// Selects a tile the way Finder selects a file. Protected items stay view-only.
    func click(_ entry: AnalyzeResult.Entry, extending: Bool) {
        guard canTrash(entry) else {
            noticeMessage = "\(entry.name) is protected, so it stays view-only."
            return
        }
        withAnimation(Motion.snap) {
            if extending {
                if selection.contains(entry.path) {
                    selection.remove(entry.path)
                } else {
                    selection.insert(entry.path)
                }
            } else {
                selection = selection == [entry.path] ? [] : [entry.path]
            }
        }
    }

    /// Whether moving these items asks first, so that the command can say so with an ellipsis.
    func needsConfirmation(toTrash paths: Set<String>) -> Bool {
        !policy.effectivePreview && paths.contains { trashRisks[$0] != nil }
    }

    /// Moves the selection to the Trash after the same checks the CLI applies. Moving to the
    /// Trash can be undone, so ordinary items don't ask first, just as the Finder doesn't.
    /// Items that `TrashRisk` flags do, because moving one by mistake can do harm before
    /// anyone thinks to undo it.
    func trashSelection(cli: CLIInfo) {
        guard !isTrashing, !isShuttingDown else { return }
        guard !isStale else {
            noticeMessage = "Rescan this folder to review its current contents."
            return
        }
        guard canTrashSelection else {
            noticeMessage = "Protected items stay view-only. Select other items to move to the Trash."
            return
        }
        let chosen = selectedEntries.map { (path: $0.path, size: $0.size) }
        if policy.effectivePreview {
            let count = chosen.count
            noticeMessage = "Preview Mode: nothing moved. This would move \(String(count.itemCount.characters)) (\(selectedBytes.fileSize)) to the Trash."
            withAnimation(Motion.snap) { selection = [] }
            return
        }
        guard !needsConfirmation(toTrash: selection) else {
            pendingTrash = TrashConfirmation(selected: selectedEntries, risks: trashRisks)
            return
        }
        moveToTrash(chosen, cli: cli)
    }

    /// Goes ahead with the question's selection, and only if that's still what is selected.
    func confirmPendingTrash(cli: CLIInfo) {
        guard let pending = pendingTrash else { return }
        pendingTrash = nil
        guard pending.paths == selection, canTrashSelection else { return }
        moveToTrash(selectedEntries.map { (path: $0.path, size: $0.size) }, cli: cli)
    }

    private func moveToTrash(_ chosen: [(path: String, size: Int64)], cli: CLIInfo) {
        enqueueMutation { [self] in
            guard !policy.effectivePreview else {
                noticeMessage = "Preview Mode: nothing moved. Turn off Preview Mode to move these items to the Trash."
                return
            }
            let report = await self.trashClient.trash(chosen, self.home)
            let moved = report.outcomes.filter { $0.status == .succeeded }
            let removed = report.outcomes.filter { $0.status == .succeeded || $0.status == .alreadyMissing }
            showErrors(report, logFailure: "The move couldn’t be written to Mole’s history log.")

            let restorable = moved.compactMap(\.trashedItem)
            if !restorable.isEmpty {
                registerUndo(for: TrashedBatch(items: restorable), cli: cli)
            } else {
                lastTrashed = nil
            }
            if !moved.isEmpty {
                onFilesMoved?()
                noticeMessage = "Moved \(String(moved.count.itemCount.characters)) to the Trash."
            } else if !removed.isEmpty {
                noticeMessage = "The selected items that disappeared were already missing."
            }
            // The rest of the map closes over the gap, because the tiles keep their identity.
            withAnimation(Motion.lift) {
                presentation = presentation?.removing(Set(removed.map(\.path)))
                selection = []
            }
            cache.removeAll()
            if !isStale, let presentation { cache[current?.id ?? "/"] = presentation }
        }
    }

    /// Restores the toast's batch; other batches keep their own Undo registrations.
    func undoTrash(cli: CLIInfo) {
        guard let batch = lastTrashed else { return }
        restore(batch, cli: cli)
    }

    private func registerUndo(for batch: TrashedBatch, cli: CLIInfo) {
        lastTrashed = batch
        let action = TrashUndoAction { [weak self] in
            self?.restore(batch, cli: cli)
        }
        undoActions[batch.id] = action
        guard let undoManager else { return }
        let needsGroup = undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: action) { action in
            MainActor.assumeIsolated { action.restore() }
        }
        undoManager.setActionName("Move to Trash")
        if needsGroup { undoManager.endUndoGrouping() }
    }

    private func restore(_ batch: TrashedBatch, cli: CLIInfo) {
        guard !isShuttingDown, undoActions[batch.id] != nil else { return }
        if policy.effectivePreview {
            noticeMessage = "Preview Mode: nothing restored. Turn off Preview Mode to put these items back."
            if undoManager?.isUndoing == true {
                // Re-register after Undo finishes, otherwise UndoManager would make this a Redo.
                Task { [weak self] in
                    guard let self, let action = self.undoActions.removeValue(forKey: batch.id) else { return }
                    self.undoManager?.removeAllActions(withTarget: action)
                    self.registerUndo(for: batch, cli: cli)
                }
            }
            return
        }
        if let action = undoActions.removeValue(forKey: batch.id) {
            undoManager?.removeAllActions(withTarget: action)
        }
        if lastTrashed?.id == batch.id { lastTrashed = nil }
        enqueueMutation { [self] in
            guard !policy.effectivePreview else {
                registerUndo(for: batch, cli: cli)
                noticeMessage = "Preview Mode: nothing restored. Turn off Preview Mode to put these items back."
                return
            }
            let report = await self.trashClient.restore(batch.items, self.home)
            let failedPaths = Set(report.outcomes.filter { $0.error != nil }.map(\.path))
            let failed = batch.items.filter { failedPaths.contains($0.originalPath) }
            showErrors(report, logFailure: "The restoration couldn’t be written to Mole’s history log.")
            let restored = report.outcomes.filter { $0.error == nil }.count
            if restored > 0 { onFilesMoved?() }
            noticeMessage = restored > 0 ? "Put back \(String(restored.itemCount.characters))." : nil
            if !failed.isEmpty {
                registerUndo(for: TrashedBatch(items: failed), cli: cli)
                noticeMessage = "Some items couldn’t be put back. Undo can retry them."
            }
            cache.removeAll()
            load(cli: cli, refresh: true, clearError: false)
        }
    }

    private func showErrors(_ report: TrashMover.Report, logFailure: String) {
        var messages = report.outcomes.compactMap(\.error)
        if report.logFailed { messages.append(logFailure) }
        errorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    /// Serializes Trash and restore operations, including rapid consecutive Undo commands.
    private func enqueueMutation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = mutationTask
        mutationCount += 1
        isTrashing = true
        mutationTask = Task {
            await previous?.value
            await operation()
            mutationCount -= 1
            isTrashing = mutationCount > 0
            if mutationCount == 0 { mutationTask = nil }
        }
    }

    /// Called from hover actions. Views that show the hovered entry read `hovered` themselves.
    func setHovered(_ path: String, inside: Bool) {
        if inside {
            hovered = path
        } else if hovered == path {
            hovered = nil
        }
    }

    func dismissNotice() {
        withAnimation(Motion.glide) {
            noticeMessage = nil
        }
    }
}
