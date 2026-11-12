import BurrowCore
import Foundation
import Observation
import SwiftUI

/// Puts a native list in front of a CLI selection menu.
///
/// The CLI scans and waits at its menu while the user chooses here. `MenuDriver` then
/// applies the choice to the real menu and verifies it, and the CLI's own confirmation
/// comes back through the run panel.
@MainActor
@Observable
final class MenuFlowModel {
    enum State: Equatable {
        case idle
        case scanning
        case choosing
        /// Applying the selection to the CLI's menu. Everything is locked meanwhile.
        case applying
        case running
    }

    let configuration: MenuFlowConfiguration
    let run: RunController
    private let policy: ExecutionPolicy

    private(set) var state = State.idle
    private(set) var items: [MenuItem] = []
    private(set) var isPreviewRun = false
    private(set) var readProgress = ""
    var selection: Set<Int> = []
    var includeEmptyFolders = false
    var isEditingPaths = false
    var errorMessage: String?

    static let previewChangedReason = "Preview Mode changed, so nothing was applied. Scan again to continue."

    private var driver: MenuDriver?
    private var flowTask: Task<Void, Never>?

    init(configuration: MenuFlowConfiguration, policy: ExecutionPolicy) {
        self.configuration = configuration
        self.policy = policy
        run = RunController(policy: policy)
    }

    /// True while the flow is scanning, applying a selection, or running the command.
    var isWorking: Bool {
        state == .scanning || state == .applying || run.isRunning && state == .running
    }

    var selectedBytes: Int64 {
        items.filter { selection.contains($0.index) }.map(\.bytes).saturatingSum
    }

    func shutdown() {
        flowTask?.cancel()
        flowTask = nil
        driver = nil
        run.cancel()
    }

    /// The line under the window title.
    var selectionSummary: String {
        guard state == .choosing else { return "" }
        let count = "\(selection.count) of \(items.count) selected"
        return selection.isEmpty ? count : "\(count) · \(selectedBytes.fileSize)"
    }

    func scan(cli: CLIInfo, preview: Bool) {
        flowTask?.cancel()
        errorMessage = nil
        items = []
        selection = []
        readProgress = ""
        isPreviewRun = preview

        var arguments = [configuration.command]
        if preview { arguments.append("--dry-run") }
        if configuration.managesScanPaths, includeEmptyFolders { arguments.append("--include-empty") }

        // Every row must fit on one page, so that the driver sees the whole list.
        let listsOnly = preview && !configuration.previewShowsMenu
        run.start(
            title: listsOnly ? "\(configuration.screen.title) Preview" : configuration.scanTitle,
            doneTitle: listsOnly ? "Preview Finished" : configuration.doneTitle,
            cli: cli,
            arguments: arguments,
            rows: 400,
            columns: 220,
            keepsLogAtEnd: listsOnly,
            consequence: preview ? nil : configuration.consequence,
            isIrreversible: configuration.isIrreversible
        )

        guard let terminal = run.terminal else {
            if case .failedToStart(let message) = run.phase { errorMessage = message }
            state = .idle
            return
        }

        // Without a menu to wait at, this is a plain listing with nothing to select.
        guard !listsOnly else {
            state = .running
            return
        }

        state = .scanning
        let driver = MenuDriver(terminal: terminal)
        self.driver = driver
        flowTask = Task {
            do {
                guard try await driver.waitForMenu() != nil else {
                    run.retitle(configuration.screen.title, doneTitle: configuration.emptyTitle)
                    state = .running
                    return
                }
                run.isLogSuppressed = true
                let found = try await driver.readItems { done, total in
                    self.readProgress = "Reading \(done) of \(total)"
                }
                try Task.checkCancellation()
                items = found
                withAnimation(Motion.settle) {
                    selection = Set(found.filter(\.preselected).map(\.index))
                    state = .choosing
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                run.cancel()
                state = .idle
            }
        }
    }

    func cancelScan() {
        flowTask?.cancel()
        run.cancel()
        driver = nil
        state = .idle
    }

    /// Leaves the CLI's menu without selecting anything.
    func abandonSelection() {
        flowTask?.cancel()
        driver?.quit()
        driver = nil
        run.reset()
        items = []
        selection = []
        state = .idle
    }

    /// Applies the selection to the real menu and confirms it. `preview` is the current
    /// mode, which must still match the mode the menu was started in.
    func applySelection(preview: Bool) {
        guard state == .choosing, let driver else { return }
        guard preview == isPreviewRun else {
            abandon(because: Self.previewChangedReason)
            return
        }
        let wanted = items.filter { selection.contains($0.index) }
        guard !wanted.isEmpty else { return }
        state = .applying
        flowTask?.cancel()
        flowTask = Task {
            do {
                try await driver.select(wanted)
                guard policy.effectivePreview == isPreviewRun else {
                    abandon(because: Self.previewChangedReason)
                    return
                }
                try driver.confirm()
                run.clearLog()
                run.isLogSuppressed = false
                run.retitle(
                    isPreviewRun ? "\(configuration.screen.title) Preview" : configuration.workingTitle,
                    doneTitle: isPreviewRun ? "Preview Finished" : configuration.doneTitle
                )
                state = .running
            } catch is CancellationError {
                return
            } catch {
                abandon(because: error.localizedDescription)
            }
        }
    }

    /// Leaves the CLI's menu without confirming anything and explains why.
    func abandon(because reason: String) {
        abandonSelection()
        errorMessage = reason
    }

    func finishRun() {
        driver = nil
        run.reset()
        items = []
        selection = []
        state = .idle
    }
}
