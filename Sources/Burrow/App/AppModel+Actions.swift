import BurrowCore
import Foundation

/// The commands the current page offers, used by both its toolbar and the menu bar.
extension AppModel {
    /// The page's one main action.
    var primaryAction: PageAction? {
        guard let cli else { return nil }
        let preview = effectivePreview
        switch selection {
        case .clean:
            switch clean.state {
            case .idle:
                return PageAction(title: "Scan This Mac", showsInToolbar: false) { self.clean.scan(cli: cli) }
            case .scanning:
                return nil
            case .review:
                let potential = clean.report.potentialBytes
                let hasWork = potential > 0
                if preview {
                    return PageAction(title: "Preview Cleanup", isEnabled: hasWork) { self.clean.clean(cli: cli, preview: true) }
                }
                return PageAction(title: "Clean \(potential.fileSize)…", symbol: "sparkles", isEnabled: hasWork) {
                    guard self.cli == cli, self.clean.state == .review else { return }
                    self.clean.isConfirming = true
                }
            case .running:
                return doneAction(clean.run) { self.clean.finishRun() }
            }
        case .uninstall:
            switch uninstall.state {
            case .idle:
                return PageAction(title: "Load Apps", showsInToolbar: false) { self.uninstall.load(cli: cli) }
            case .loading:
                return nil
            case .list:
                let enabled = !uninstall.selection.isEmpty
                return PageAction(title: preview ? "Preview Removal" : "Review Removal…", isEnabled: enabled) {
                    self.uninstall.beginRemoval(cli: cli, preview: preview)
                }
            case .running:
                return doneAction(uninstall.run) { self.uninstall.finishRun(cli: cli) }
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
                return PageAction(title: "Check This Mac", showsInToolbar: false) { self.optimize.preview(cli: cli) }
            case .previewing:
                return nil
            case .review:
                if preview {
                    return PageAction(title: "Preview Maintenance") { self.optimize.runMaintenance(cli: cli, preview: true) }
                }
                guard optimize.errorMessage == nil else { return nil }
                return PageAction(title: "Run Maintenance…") {
                    guard self.cli == cli, self.optimize.state == .review else { return }
                    self.optimize.isConfirming = true
                }
            case .running:
                return doneAction(optimize.run) { self.optimize.finishRun(cli: cli) }
            }
        case .analyze:
            guard analyze.canTrashSelection else { return nil }
            let trashTitle = preview ? "Preview Move to Trash"
                : analyze.needsConfirmation(toTrash: analyze.selection) ? "Move to Trash…" : "Move to Trash"
            return PageAction(title: trashTitle, symbol: "trash", isEnabled: !analyze.isTrashing) {
                self.analyze.trashSelection(cli: cli)
            }
        case .overview, .status, .history:
            return nil
        }
    }

    /// The page's escape or refresh command.
    var secondaryAction: PageAction? {
        guard let cli else { return nil }
        switch selection {
        case .clean:
            switch clean.state {
            case .scanning: return PageAction(title: "Cancel", isCancellation: true) { self.clean.cancelScan() }
            case .review: return PageAction(title: "Scan Again", symbol: "arrow.clockwise") { self.clean.scan(cli: cli) }
            case .running: return cancelAction(clean.run)
            case .idle: return nil
            }
        case .uninstall:
            switch uninstall.state {
            case .list: return PageAction(title: "Reload", symbol: "arrow.clockwise") { self.uninstall.load(cli: cli) }
            case .running: return cancelAction(uninstall.run)
            case .idle, .loading: return nil
            }
        case .purge:
            return menuFlowSecondary(purge)
        case .installers:
            return menuFlowSecondary(installers)
        case .slim:
            return menuFlowSecondary(slim)
        case .optimize:
            switch optimize.state {
            case .previewing: return PageAction(title: "Cancel", isCancellation: true) { self.optimize.cancelPreview() }
            case .review: return PageAction(title: "Check Again", symbol: "arrow.clockwise") { self.optimize.preview(cli: cli) }
            case .running: return cancelAction(optimize.run)
            case .idle: return nil
            }
        case .analyze:
            if analyze.isLoading { return PageAction(title: "Cancel Scan", isCancellation: true) { self.analyze.cancelScan() } }
            return PageAction(title: "Rescan", symbol: "arrow.clockwise", isEnabled: !analyze.isTrashing) { self.analyze.refresh(cli: cli) }
        case .history:
            return PageAction(title: "Reload", symbol: "arrow.clockwise") { self.history.load(cli: cli) }
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

    private func doneAction(_ run: RunController, finish: @escaping @MainActor () -> Void) -> PageAction? {
        run.isRunning ? nil : PageAction(title: "Done", perform: finish)
    }

    private func cancelAction(_ run: RunController) -> PageAction? {
        run.isRunning ? PageAction(title: "Cancel", isCancellation: true) { run.cancel() } : nil
    }

    private func menuFlowPrimary(_ flow: MenuFlowModel, cli: CLIInfo, preview: Bool) -> PageAction? {
        switch flow.state {
        case .idle:
            return PageAction(title: "Scan", showsInToolbar: false) { flow.scan(cli: cli, preview: preview) }
        case .scanning, .applying:
            return nil
        case .choosing:
            let title = flow.isPreviewRun ? "Preview Selection" : "\(flow.configuration.actionVerb) Selected…"
            return PageAction(title: title, isEnabled: !flow.selection.isEmpty) { flow.applySelection(preview: preview) }
        case .running:
            return doneAction(flow.run) { flow.finishRun() }
        }
    }

    private func menuFlowSecondary(_ flow: MenuFlowModel) -> PageAction? {
        switch flow.state {
        case .scanning: return PageAction(title: "Cancel", isCancellation: true) { flow.cancelScan() }
        case .choosing: return PageAction(title: "Cancel", isCancellation: true) { flow.abandonSelection() }
        case .running: return cancelAction(flow.run)
        case .idle, .applying: return nil
        }
    }
}
