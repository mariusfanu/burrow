import BurrowCore
import Foundation

/// The commands the current page offers, used by both its toolbar and the menu bar.
extension AppModel {
    /// The page's one main action.
    var primaryAction: PageAction? {
        guard !isShuttingDown, let cli else { return nil }
        let preview = effectivePreview
        switch selection {
        case .clean:
            switch clean.state {
            case .idle:
                return guardedAction(title: "Scan This Mac", showsInToolbar: false, cli: cli) { self.clean.scan(cli: cli) }
            case .scanning:
                return nil
            case .review:
                let potential = clean.report.potentialBytes
                let hasWork = potential > 0
                if preview {
                    return guardedAction(title: "Preview Cleanup", isEnabled: hasWork, cli: cli) { self.clean.clean(cli: cli, preview: true) }
                }
                return guardedAction(title: "Clean \(potential.fileSize)…", symbol: "sparkles", isEnabled: hasWork, cli: cli) {
                    guard self.clean.state == .review else { return }
                    self.clean.isConfirming = true
                }
            case .running:
                return doneAction(clean.run, cli: cli) { self.clean.finishRun() }
            }
        case .uninstall:
            switch uninstall.state {
            case .idle:
                return guardedAction(title: "Load Apps", showsInToolbar: false, cli: cli) { self.uninstall.load(cli: cli) }
            case .loading:
                return nil
            case .list:
                let enabled = !uninstall.selection.isEmpty
                return guardedAction(title: preview ? "Preview Removal" : "Review Removal…", isEnabled: enabled, cli: cli) {
                    self.uninstall.beginRemoval(cli: cli, preview: preview)
                }
            case .running:
                return doneAction(uninstall.run, cli: cli) { self.uninstall.finishRun(cli: cli) }
            }
        case .purge:
            return menuFlowPrimary(purge, cli: cli, preview: preview)
        case .installers:
            return menuFlowPrimary(installers, cli: cli, preview: preview)
        case .slim:
            return menuFlowPrimary(slim, cli: cli, preview: preview)
        case .optimize:
            switch optimize.state {
            case .idle:
                return guardedAction(title: "Check This Mac", showsInToolbar: false, cli: cli) { self.optimize.preview(cli: cli) }
            case .previewing:
                return nil
            case .review:
                if preview {
                    return guardedAction(title: "Preview Maintenance", cli: cli) { self.optimize.runMaintenance(cli: cli, preview: true) }
                }
                guard optimize.errorMessage == nil else { return nil }
                return guardedAction(title: "Run Maintenance…", cli: cli) {
                    guard self.optimize.state == .review else { return }
                    self.optimize.isConfirming = true
                }
            case .running:
                return doneAction(optimize.run, cli: cli) { self.optimize.finishRun(cli: cli) }
            }
        case .analyze:
            guard cli.hasBundledTools, analyze.canTrashSelection else { return nil }
            let trashTitle = preview ? "Preview Move to Trash"
                : analyze.needsConfirmation(toTrash: analyze.selection) ? "Move to Trash…" : "Move to Trash"
            return guardedAction(title: trashTitle, symbol: "trash", isEnabled: !analyze.isTrashing, cli: cli) {
                self.analyze.trashSelection(cli: cli)
            }
        case .overview, .status, .history:
            return nil
        }
    }

    /// The page's escape or refresh command.
    var secondaryAction: PageAction? {
        guard !isShuttingDown, let cli else { return nil }
        switch selection {
        case .clean:
            switch clean.state {
            case .scanning: return guardedAction(title: "Cancel", isCancellation: true, cli: cli) { self.clean.cancelScan() }
            case .review: return guardedAction(title: "Scan Again", symbol: "arrow.clockwise", cli: cli) { self.clean.scan(cli: cli) }
            case .running: return cancelAction(clean.run, cli: cli)
            case .idle: return nil
            }
        case .uninstall:
            switch uninstall.state {
            case .list: return guardedAction(title: "Reload", symbol: "arrow.clockwise", cli: cli) { self.uninstall.load(cli: cli) }
            case .running: return cancelAction(uninstall.run, cli: cli)
            case .idle, .loading: return nil
            }
        case .purge:
            return menuFlowSecondary(purge, cli: cli)
        case .installers:
            return menuFlowSecondary(installers, cli: cli)
        case .slim:
            return menuFlowSecondary(slim, cli: cli)
        case .optimize:
            switch optimize.state {
            case .previewing: return guardedAction(title: "Cancel", isCancellation: true, cli: cli) { self.optimize.cancelPreview() }
            case .review: return guardedAction(title: "Check Again", symbol: "arrow.clockwise", cli: cli) { self.optimize.preview(cli: cli) }
            case .running: return cancelAction(optimize.run, cli: cli)
            case .idle: return nil
            }
        case .analyze:
            guard cli.hasBundledTools else { return nil }
            if analyze.isLoading { return guardedAction(title: "Cancel Scan", isCancellation: true, cli: cli) { self.analyze.cancelScan() } }
            return guardedAction(title: "Rescan", symbol: "arrow.clockwise", isEnabled: !analyze.isTrashing, cli: cli) { self.analyze.refresh(cli: cli) }
        case .history:
            return guardedAction(title: "Reload", symbol: "arrow.clockwise", cli: cli) { self.history.load(cli: cli) }
        case .overview, .status:
            return nil
        }
    }

    /// What Command-Delete does, which is the page's main action only in Disk Explorer.
    var trashAction: PageAction? {
        selection == .analyze ? primaryAction : nil
    }

    /// What Command-R does. It stays out of reach while the secondary action is a Cancel,
    /// because reloading must never be able to stop a cleanup partway through.
    var reloadAction: PageAction? {
        secondaryAction.flatMap { $0.isCancellation ? nil : $0 }
    }

    /// What Command-Period does: stops whatever the page has under way.
    var cancellationAction: PageAction? {
        secondaryAction.flatMap { $0.isCancellation ? $0 : nil }
    }

    /// The run on the current page, for the Terminal command.
    var currentRun: RunController? {
        switch selection {
        case .clean: clean.state == .running ? clean.run : nil
        case .uninstall: uninstall.state == .running ? uninstall.run : nil
        case .purge: purge.state == .running ? purge.run : nil
        case .installers: installers.state == .running ? installers.run : nil
        case .slim: slim.state == .running ? slim.run : nil
        case .optimize: optimize.state == .running ? optimize.run : nil
        case .overview, .analyze, .status, .history: nil
        }
    }

    private func guardedAction(
        title: String,
        symbol: String? = nil,
        showsInToolbar: Bool = true,
        isEnabled: Bool = true,
        isCancellation: Bool = false,
        cli: CLIInfo,
        perform: @escaping @MainActor () -> Void
    ) -> PageAction {
        PageAction(
            title: title,
            symbol: symbol,
            isEnabled: isEnabled,
            showsInToolbar: showsInToolbar,
            isCancellation: isCancellation
        ) {
            guard !self.isShuttingDown, self.cli == cli else { return }
            perform()
        }
    }

    private func doneAction(_ run: RunController, cli: CLIInfo, finish: @escaping @MainActor () -> Void) -> PageAction? {
        run.isRunning ? nil : guardedAction(title: "Done", cli: cli, perform: finish)
    }

    private func cancelAction(_ run: RunController, cli: CLIInfo) -> PageAction? {
        run.isRunning ? guardedAction(title: "Cancel", isCancellation: true, cli: cli) { run.cancel() } : nil
    }

    private func menuFlowPrimary(_ flow: MenuFlowModel, cli: CLIInfo, preview: Bool) -> PageAction? {
        switch flow.state {
        case .idle:
            return guardedAction(title: "Scan", showsInToolbar: false, cli: cli) { flow.scan(cli: cli, preview: preview) }
        case .scanning, .applying:
            return nil
        case .choosing:
            let title = flow.isPreviewRun ? "Preview Selection" : "\(flow.configuration.actionVerb) Selected…"
            return guardedAction(title: title, isEnabled: !flow.selection.isEmpty, cli: cli) { flow.applySelection(preview: preview) }
        case .running:
            return doneAction(flow.run, cli: cli) { flow.finishRun() }
        }
    }

    private func menuFlowSecondary(_ flow: MenuFlowModel, cli: CLIInfo) -> PageAction? {
        switch flow.state {
        case .scanning: return guardedAction(title: "Cancel", isCancellation: true, cli: cli) { flow.cancelScan() }
        case .choosing: return guardedAction(title: "Cancel", isCancellation: true, cli: cli) { flow.abandonSelection() }
        case .running: return cancelAction(flow.run, cli: cli)
        case .idle, .applying: return nil
        }
    }
}
