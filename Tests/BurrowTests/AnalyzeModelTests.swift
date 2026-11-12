import Foundation
import Testing
import BurrowCore
@testable import Burrow

private actor AnalyzeFiles {
    private var present: Set<String> = ["/fixture/a", "/fixture/b"]
    private(set) var trashed: [String] = []
    private(set) var restored: [String] = []
    var refusesRestore = false

    func refuseRestore(_ refuse: Bool) { refusesRestore = refuse }
    func report() throws -> CommandResult {
        let json: [String: Any] = ["path": "/fixture", "entries": present.sorted().map {
            ["name": ($0 as NSString).lastPathComponent, "path": $0, "size": 1, "is_dir": false] as [String: Any]
        }]
        return CommandResult(status: 0, stdout: String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self), stderr: "")
    }
    func trash(_ entries: [(path: String, size: Int64)]) -> TrashMover.Report {
        .init(outcomes: entries.map { entry in
            present.remove(entry.path)
            trashed.append(entry.path)
            return .init(path: entry.path, error: nil, trashedURL: URL(fileURLWithPath: "/fixture-trash" + entry.path))
        }, logFailed: false)
    }
    func restore(_ items: [TrashMover.TrashedItem]) -> TrashMover.Report {
        .init(outcomes: items.map { item in
            if refusesRestore { return .init(path: item.originalPath, error: "Destination exists") }
            present.insert(item.originalPath)
            restored.append(item.originalPath)
            return .init(path: item.originalPath, error: nil)
        }, logFailed: false)
    }
}

@MainActor
struct AnalyzeModelTests {
    @Test func aScanThatPredatesInvalidationCannotPublish() async throws {
        let commands = ScriptedCommands()
        let model = AnalyzeModel(policy: .live, commands: commands.client, home: "/fixture")
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        model.markStale()
        await commands.completeRun(0, stdout: #"{"path":"/old"}"#)
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        #expect(model.result == nil)
        await commands.completeRun(1, stdout: #"{"path":"/current"}"#)
        try await eventually { model.result?.path == "/current" }
    }

    @Test func anAlreadyMissingItemDisappearsWithoutAnnouncingAMove() async throws {
        let files = AnalyzeFiles()
        let client = TrashClient(trash: { entries, _ in
            .init(outcomes: entries.map { .init(path: $0.path, status: .alreadyMissing) }, logFailed: false)
        })
        let model = AnalyzeModel(policy: .live, commands: CommandClient(run: { _, _, _ in try await files.report() }),
                                 trashClient: client, home: "/fixture")
        model.onFilesMoved = { Issue.record("Missing items did not change the filesystem") }
        model.openRoot(cli: fixtureCLI)
        try await eventually { model.entries.count == 2 }
        try await trash("/fixture/a", in: model)
        #expect(model.entries.map(\.path) == ["/fixture/b"])
        #expect(model.noticeMessage?.contains("already missing") == true)
        #expect(model.lastTrashed == nil)
    }

    private func fixture(policy: ExecutionPolicy = .live, restores: SuspendedRestore? = nil) async throws -> (AnalyzeModel, AnalyzeFiles, UndoManager) {
        let files = AnalyzeFiles()
        let commands = CommandClient(run: { _, _, _ in try await files.report() })
        let client = TrashClient(trash: { entries, _ in await files.trash(entries) }, restore: { items, _ in
            if let restores { await restores.restore(items) } else { await files.restore(items) }
        })
        let model = AnalyzeModel(policy: policy, commands: commands, trashClient: client, home: "/fixture")
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading }
        return (model, files, undo)
    }

    private func trash(_ path: String, in model: AnalyzeModel) async throws {
        model.selection = [path]
        model.trashSelection(cli: fixtureCLI)
        try await eventually { !model.isTrashing }
    }

    @Test func forcedAndLivePreviewBlockTheMutationBoundary() async throws {
        for forced in [false, true] {
            let policy = ExecutionPolicy(defaults: nil, forced: forced)
            let (model, files, undo) = try await fixture(policy: policy)
            // The live policy changes after the model is constructed, as Settings does.
            policy.previewMode = !forced
            try await trash("/fixture/a", in: model)
            #expect(await files.trashed.isEmpty)
            #expect(!undo.canUndo)
            #expect(model.entries.count == 2)
            #expect(model.noticeMessage?.contains("Preview Mode") == true)
        }
    }

    @Test func dismissingTheNoticePreservesEditUndo() async throws {
        let (model, files, undo) = try await fixture()
        try await trash("/fixture/a", in: model)
        model.dismissNotice()
        #expect(model.noticeMessage == nil)
        #expect(undo.canUndo)
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(await files.restored == ["/fixture/a"])
        #expect(!undo.canUndo)
    }

    @Test func rapidConsecutiveUndoRestoresEachCapturedBatchInOrder() async throws {
        let (model, files, undo) = try await fixture()
        try await trash("/fixture/a", in: model)
        try await trash("/fixture/b", in: model)
        undo.undo()
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(await files.restored == ["/fixture/b", "/fixture/a"])
        #expect(!undo.canUndo)
    }

    @Test func toastUndoConsumesOnlyItsOwnRegistration() async throws {
        let (model, files, undo) = try await fixture()
        try await trash("/fixture/a", in: model)
        try await trash("/fixture/b", in: model)
        model.undoTrash(cli: fixtureCLI)
        try await eventually { !model.isTrashing }
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(await files.restored == ["/fixture/b", "/fixture/a"])
        #expect(!undo.canUndo)
    }

    @Test func failedRestorationRemainsRetryable() async throws {
        let (model, files, undo) = try await fixture()
        try await trash("/fixture/a", in: model)
        await files.refuseRestore(true)
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(model.errorMessage?.contains("Destination exists") == true)
        #expect(model.lastTrashed?.items.count == 1)
        #expect(undo.canUndo)
        await files.refuseRestore(false)
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(await files.restored == ["/fixture/a"])
        #expect(model.errorMessage == nil)
    }

    @Test func oldScanErrorsCannotClearANewerDiskScan() async throws {
        let commands = ScriptedCommands()
        let model = AnalyzeModel(policy: .live, commands: commands.client)
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        model.openPath("/new", cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.failRun(0)
        await commands.completeRun(1, stdout: "{\"path\":\"/new\",\"entries\":[]}")
        try await eventually { !model.isLoading }
        #expect(model.result?.path == "/new")
        #expect(model.errorMessage == nil)
    }

    @Test func previewRefusesUndoWithoutLosingTheBatch() async throws {
        let policy = ExecutionPolicy.live
        let (model, files, undo) = try await fixture(policy: policy)
        try await trash("/fixture/a", in: model)
        policy.previewMode = true
        undo.undo()
        try await eventually { undo.canUndo }
        #expect(await files.restored.isEmpty)
        policy.previewMode = false
        undo.undo()
        try await eventually { !model.isTrashing }
        #expect(await files.restored == ["/fixture/a"])
    }

    @Test func queuedUndoRechecksPreviewModeBeforeItStartsAndRemainsRetryable() async throws {
        let policy = ExecutionPolicy.live
        let restores = SuspendedRestore()
        // Hold the first native restore open while the second Undo waits behind it.
        let (controlled, _, undo) = try await fixture(policy: policy, restores: restores)
        try await trash("/fixture/a", in: controlled)
        try await trash("/fixture/b", in: controlled)
        undo.undo()
        undo.undo()
        try await eventually { await restores.calls.count == 1 }
        policy.previewMode = true
        await restores.completeFirst()
        try await eventually { !controlled.isTrashing }
        #expect(await restores.calls == ["/fixture/b"])
        #expect(undo.canUndo)
        #expect(controlled.noticeMessage?.contains("Preview Mode") == true)
        policy.previewMode = false
        undo.undo()
        try await eventually { !controlled.isTrashing }
        #expect(await restores.calls == ["/fixture/b", "/fixture/a"])
    }

    @Test func shutdownRefusesNewUndoRequestsWhileDrainingAnExistingRestore() async throws {
        let restores = SuspendedRestore()
        let (model, _, undo) = try await fixture(restores: restores)
        try await trash("/fixture/a", in: model)
        try await trash("/fixture/b", in: model)
        undo.undo()
        try await eventually { await restores.calls.count == 1 }
        let drain = Task { await model.shutdown() }
        try await eventually { model.isShuttingDown }
        undo.undo()
        await restores.completeFirst()
        await drain.value
        #expect(await restores.calls == ["/fixture/b"])
        #expect(!model.isTrashing)
    }
}

private actor SuspendedRestore {
    private(set) var calls: [String] = []
    private var first: CheckedContinuation<TrashMover.Report, Never>?
    private var firstItems: [TrashMover.TrashedItem] = []
    func restore(_ items: [TrashMover.TrashedItem]) async -> TrashMover.Report {
        calls += items.map(\.originalPath)
        if calls.count == 1 {
            firstItems = items
            return await withCheckedContinuation { first = $0 }
        }
        return report(items)
    }
    func completeFirst() {
        first?.resume(returning: report(firstItems))
        first = nil
    }
    private func report(_ items: [TrashMover.TrashedItem]) -> TrashMover.Report {
        .init(outcomes: items.map { .init(path: $0.originalPath, error: nil) }, logFailed: false)
    }
}

private final class ProtectionChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var evaluations = 0
    private var ranOnMain = false
    func evaluate(_ entries: [AnalyzeResult.Entry], home: String) -> Set<String> {
        lock.withLock {
            evaluations += 1
            ranOnMain = ranOnMain || Thread.isMainThread
        }
        return ["/fixture/protected"]
    }
    var state: (count: Int, onMain: Bool) { lock.withLock { (evaluations, ranOnMain) } }
}

@MainActor
struct AnalyzePresentationTests {
    @Test func folderNavigationReusesBreadcrumbsWithoutConfusingTheDiskOverviewAndRootFolder() async throws {
        let commands = ScriptedCommands()
        let model = AnalyzeModel(policy: .live, commands: commands.client)
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: "{\"path\":\"/\",\"overview\":true,\"entries\":[]}")
        try await eventually { !model.isLoading }
        model.openPath("/", cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: "{\"path\":\"/\",\"entries\":[]}")
        try await eventually { !model.isLoading }
        #expect(Set(model.levels.map(\.id)).count == 2)
        model.openPath("/", cli: fixtureCLI)
        #expect(model.levels.count == 2)
        #expect(await commands.runs.count == 2)
        model.openPath("/child", cli: fixtureCLI)
        try await eventually { await commands.runs.count == 3 }
        await commands.completeRun(2, stdout: "{\"path\":\"/child\",\"entries\":[]}")
        try await eventually { !model.isLoading }
        model.openPath("/", cli: fixtureCLI)
        #expect(model.levels.count == 2)
        #expect(model.result?.path == "/")
        #expect(await commands.runs.count == 3)
        model.goBack(cli: fixtureCLI)
        #expect(model.result?.overview == true)
        #expect(await commands.runs.count == 3)
    }

    @Test func scansAndNavigationCannotRaceANativeTrashMutation() async throws {
        let commands = ScriptedCommands()
        let mutation = SuspendedTrash()
        let model = AnalyzeModel(policy: .live, commands: commands.client, trashClient: TrashClient(trash: { entries, _ in
            await mutation.move(entries)
        }), home: "/fixture", evaluateProtection: { _, _ in [] })
        let json = "{\"path\":\"/fixture\",\"entries\":[{\"name\":\"safe\",\"path\":\"/fixture/safe\",\"size\":2,\"is_dir\":false}]}"
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: json)
        try await eventually { !model.isLoading }
        model.selection = ["/fixture/safe"]
        model.refresh(cli: fixtureCLI)
        #expect(!model.canTrashSelection)
        model.trashSelection(cli: fixtureCLI)
        #expect(!model.isTrashing)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: json)
        try await eventually { !model.isLoading }
        model.trashSelection(cli: fixtureCLI)
        try await eventually { await mutation.isWaiting }
        model.refresh(cli: fixtureCLI)
        model.openPath("/other", cli: fixtureCLI)
        #expect(model.levels.count == 1)
        #expect(!model.isLoading)
        #expect(await commands.runs.count == 2)
        await mutation.complete()
        try await eventually { !model.isTrashing }
        #expect(model.entries.isEmpty)
    }

    @Test func renderingAndHoverUseThePreparedProtectionSnapshot() async throws {
        let checks = ProtectionChecks()
        let json = "{\"path\":\"/fixture\",\"entries\":[{\"name\":\"protected\",\"path\":\"/fixture/protected\",\"size\":10,\"is_dir\":true},{\"name\":\"safe\",\"path\":\"/fixture/safe\",\"size\":2,\"is_dir\":true}]}"
        let commands = CommandClient(run: { _, _, _ in CommandResult(status: 0, stdout: json, stderr: "") })
        let model = AnalyzeModel(policy: .live, commands: commands, evaluateProtection: checks.evaluate)
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading }
        #expect(checks.state.count == 1)
        #expect(!checks.state.onMain)
        for _ in 0..<100 {
            for entry in model.entries {
                model.hovered = entry.path
                #expect(model.canTrash(entry) == (entry.path == "/fixture/safe"))
            }
        }
        #expect(checks.state.count == 1)
        model.selection = ["/fixture/protected"]
        #expect(!model.canTrashSelection)
        #expect(model.selectedEntries.count == 1)
        // A protected directory remains a valid browsing destination.
        model.openPath("/fixture/protected", cli: fixtureCLI)
        try await eventually { !model.isLoading }
        #expect(model.current?.path == "/fixture/protected")
    }

    @Test func cancelAndChooseFolderRejectTheOldScanResult() async throws {
        let commands = ScriptedCommands()
        let model = AnalyzeModel(policy: .live, commands: commands.client)
        model.openRoot(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        model.cancelScan()
        #expect(!model.isLoading)
        #expect(model.emptyStateTitle == "No Scan Results")
        model.openPath("/chosen", cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(0, stdout: "{\"path\":\"/obsolete\",\"entries\":[]}")
        await commands.completeRun(1, stdout: "{\"path\":\"/chosen\",\"entries\":[]}")
        try await eventually { !model.isLoading }
        #expect(model.result?.path == "/chosen")
        #expect(model.current?.path == "/chosen")
        #expect(model.emptyStateTitle == "Empty Folder")
    }
}

private actor SuspendedTrash {
    private var waiter: CheckedContinuation<TrashMover.Report, Never>?
    private var entries: [(path: String, size: Int64)] = []
    var isWaiting: Bool { waiter != nil }
    func move(_ entries: [(path: String, size: Int64)]) async -> TrashMover.Report {
        self.entries = entries
        return await withCheckedContinuation { waiter = $0 }
    }
    func complete() {
        waiter?.resume(returning: .init(outcomes: entries.map {
            .init(path: $0.path, error: nil, trashedURL: URL(fileURLWithPath: "/fixture-trash/\(($0.path as NSString).lastPathComponent)"))
        }, logFailed: false))
        waiter = nil
    }
}

private actor RecordedTrash {
    private(set) var moved: [String] = []
    func trash(_ entries: [(path: String, size: Int64)]) -> TrashMover.Report {
        .init(outcomes: entries.map { entry in
            moved.append(entry.path)
            return .init(path: entry.path, error: nil, trashedURL: URL(fileURLWithPath: "/fixture-trash" + entry.path))
        }, logFailed: false)
    }
}

@MainActor
struct HighRiskTrashTests {
    private let risky = "/fixture/.ssh"
    private let ordinary = "/fixture/Downloads/big.iso"

    private func fixture(policy: ExecutionPolicy = .live) async throws -> (AnalyzeModel, RecordedTrash) {
        let recorded = RecordedTrash()
        let entries: [[String: Any]] = [
            ["name": ".ssh", "path": risky, "size": 2, "is_dir": true],
            ["name": "big.iso", "path": ordinary, "size": 1, "is_dir": false],
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["path": "/fixture", "entries": entries]), as: UTF8.self)
        let model = AnalyzeModel(
            policy: policy,
            commands: CommandClient(run: { _, _, _ in CommandResult(status: 0, stdout: json, stderr: "") }),
            trashClient: TrashClient(trash: { entries, _ in await recorded.trash(entries) }, restore: { _, _ in .init(outcomes: [], logFailed: false) }),
            home: "/fixture"
        )
        model.openRoot(cli: fixtureCLI)
        try await eventually { !model.isLoading }
        return (model, recorded)
    }

    @Test func anOrdinaryFileStillMovesInOneClick() async throws {
        let (model, recorded) = try await fixture()
        model.selection = [ordinary]
        #expect(!model.needsConfirmation(toTrash: model.selection))
        model.trashSelection(cli: fixtureCLI)
        #expect(model.pendingTrash == nil)
        try await eventually { await recorded.moved == [ordinary] }
    }

    @Test func aHighRiskItemMovesOnlyAfterConfirmation() async throws {
        let (model, recorded) = try await fixture()
        model.selection = [risky]
        model.trashSelection(cli: fixtureCLI)
        let question = try #require(model.pendingTrash)
        #expect(question.title == "Move “.ssh” to the Trash?")
        #expect(question.message.contains("Keys and passwords"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorded.moved.isEmpty)

        model.confirmPendingTrash(cli: fixtureCLI)
        #expect(model.pendingTrash == nil)
        try await eventually { await recorded.moved == [risky] }
    }

    @Test func decliningMovesNothing() async throws {
        let (model, recorded) = try await fixture()
        model.selection = [risky]
        model.trashSelection(cli: fixtureCLI)
        #expect(model.isConfirmingTrash)
        model.isConfirmingTrash = false
        #expect(model.pendingTrash == nil)
        model.isConfirmingTrash = true
        #expect(model.pendingTrash == nil)
        model.confirmPendingTrash(cli: fixtureCLI)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorded.moved.isEmpty)
        #expect(model.entries.count == 2)
    }

    @Test func oneRiskyItemMakesTheWholeSelectionAskAndNamesOnlyThatItem() async throws {
        let (model, recorded) = try await fixture()
        model.selection = [risky, ordinary]
        model.trashSelection(cli: fixtureCLI)
        let question = try #require(model.pendingTrash)
        #expect(question.title == "Move 2 Items to the Trash?")
        #expect(question.message.contains("Check these first: .ssh."))
        model.confirmPendingTrash(cli: fixtureCLI)
        try await eventually { await recorded.moved.count == 2 }
    }

    @Test func aSelectionThatChangedAfterTheQuestionDoesNotMove() async throws {
        let (model, recorded) = try await fixture()
        model.selection = [risky]
        model.trashSelection(cli: fixtureCLI)
        model.selection = [ordinary]
        model.confirmPendingTrash(cli: fixtureCLI)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await recorded.moved.isEmpty)
    }

    @Test func previewModeHasNothingToConfirm() async throws {
        let (model, recorded) = try await fixture(policy: ExecutionPolicy(defaults: nil, forced: true))
        model.selection = [risky]
        #expect(!model.needsConfirmation(toTrash: model.selection))
        model.trashSelection(cli: fixtureCLI)
        #expect(model.pendingTrash == nil)
        #expect(model.noticeMessage?.contains("Preview Mode") == true)
        #expect(await recorded.moved.isEmpty)
    }
}
