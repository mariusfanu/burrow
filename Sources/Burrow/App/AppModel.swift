import BurrowCore
import Foundation
import Observation

/// App-wide state. Each feature keeps its own model here so that its progress survives
/// moving between pages.
@MainActor
@Observable
final class AppModel {
    private(set) var cli: CLIInfo?
    private(set) var isLocating = true

    var selection: Screen = .overview {
        didSet {
            movedDown = selection.order >= oldValue.order
            defaults?.set(selection.rawValue, forKey: Self.pageKey)
            updateStatusStream()
        }
    }

    /// The direction of the last page change, which sets the transition's direction.
    private(set) var movedDown = true

    /// When on, every action is passed `--dry-run`.
    var previewMode: Bool {
        get { executionPolicy.previewMode }
        set {
            executionPolicy.previewMode = newValue
            let effective = executionPolicy.effectivePreview
            if effective {
                clean.isConfirming = false
                optimize.isConfirming = false
                for run in allRuns where run.isRunning && !run.isPreview { run.cancel() }
            }
            for flow in [purge, installers, slim] where flow.state == .choosing && flow.isPreviewRun != effective {
                flow.abandon(because: MenuFlowModel.previewChangedReason)
            }
        }
    }

    /// Lets automated checks pin preview mode so a run can't change anything.
    var isPreviewForced: Bool { executionPolicy.isPreviewForced }

    /// Turning Preview on would stop a cleanup partway through, which isn't what anyone
    /// reaching for a "show me first" switch expects. So it waits until the work has ended.
    var isPreviewToggleEnabled: Bool {
        !isPreviewForced && (effectivePreview || !hasWorkChangingTheMac)
    }

    var previewToggleHelp: String {
        isPreviewToggleEnabled || isPreviewForced
            ? "Show what would change instead of changing it"
            : "Finish or cancel the running command to turn on Preview Mode"
    }

    /// True while something is really being changed. A scan, or a list waiting for a choice,
    /// doesn't count: leaving those loses nothing.
    var hasWorkChangingTheMac: Bool {
        if analyze.isTrashing { return true }
        let flows = [purge, installers, slim].filter { $0.state == .applying || $0.state == .running }.map(\.run)
        return (flows + [clean.run, uninstall.run, optimize.run, manage.run]).contains { $0.isRunning && !$0.isPreview }
    }

    /// How the last chosen CLI went, when it couldn't be used.
    private(set) var cliChoiceError: String?
    let executionPolicy: ExecutionPolicy

    /// Set by the page search field, so that Find in the menu bar can focus it.
    var isSearchFocused = false

    let status: StatusStore
    let clean: CleanModel
    let uninstall: UninstallModel
    let purge: MenuFlowModel
    let installers: MenuFlowModel
    let slim: MenuFlowModel
    let optimize: OptimizeModel
    let analyze: AnalyzeModel
    let history = HistoryModel()
    let manage: ManageModel

    #if DEBUG
    /// Lets scripted sessions open the Settings window.
    var openSettingsForDebug: (() -> Void)?
    #endif

    private static let pageKey = "lastPage"
    private let defaults: UserDefaults?
    private let environment: [String: String]
    private let locator: @Sendable (String?) async -> CLIInfo?
    private var customCLIPath: String?
    private var discoveryID = UUID()
    private(set) var isShuttingDown = false
    private(set) var isWindowVisible = true

    init(
        defaults: UserDefaults? = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        status: StatusStore = StatusStore(),
        locator: @escaping @Sendable (String?) async -> CLIInfo? = { await CLILocator.locate(customPath: $0) }
    ) {
        self.defaults = defaults
        self.environment = environment
        self.status = status
        self.locator = locator
        customCLIPath = defaults?.string(forKey: CLILocator.customPathKey)
        let policy = ExecutionPolicy(defaults: defaults, forced: environment["BURROW_FORCE_PREVIEW"] == "1")
        executionPolicy = policy
        clean = CleanModel(policy: policy)
        uninstall = UninstallModel(policy: policy)
        purge = MenuFlowModel(configuration: .purge, policy: policy)
        installers = MenuFlowModel(configuration: .installers, policy: policy)
        slim = MenuFlowModel(configuration: .slim, policy: policy)
        optimize = OptimizeModel(policy: policy)
        manage = ManageModel(policy: policy)
        analyze = AnalyzeModel(policy: policy)
        #if DEBUG
        let saved = environment["BURROW_SCREEN"] ?? defaults?.string(forKey: Self.pageKey)
        #else
        let saved = defaults?.string(forKey: Self.pageKey)
        #endif
        if let screen = saved.flatMap(Screen.init(rawValue:)) {
            selection = screen
        }
        watchForDiskChanges()
    }

    /// Pages keep their results while you're elsewhere, so another page's changes mark them
    /// out of date, and they load again the next time they appear.
    private func watchForDiskChanges() {
        clean.run.onFinishedChanges = { [weak self] in self?.analyze.markStale() }
        uninstall.run.onFinishedChanges = { [weak self] in self?.analyze.markStale() }
        for flow in [purge, installers, slim] {
            // A cancelled scan changed nothing, and by the time it ends the flow has left `.running`.
            flow.run.onFinishedChanges = { [weak self, weak flow] in
                guard let self, flow?.state == .running else { return }
                analyze.markStale()
                if flow?.configuration.changesApps == true { uninstall.markStale() }
            }
        }
        analyze.onFilesMoved = { [weak self] in self?.uninstall.markStale() }
    }

    var effectivePreview: Bool { executionPolicy.effectivePreview }

    /// True while a command that may change the Mac is running.
    var hasActiveWork: Bool {
        Screen.allCases.contains(where: isWorking) || manage.run.isRunning
    }

    /// Whether a page has work under way, shown beside it in the sidebar.
    func isWorking(_ screen: Screen) -> Bool {
        switch screen {
        case .clean: clean.state == .scanning || clean.run.isRunning
        case .uninstall: uninstall.state == .loading || uninstall.run.isRunning
        case .purge: purge.isWorking
        case .installers: installers.isWorking
        case .slim: slim.isWorking
        case .optimize: optimize.state == .previewing || optimize.run.isRunning
        case .analyze: analyze.isLoading || analyze.isTrashing
        case .overview, .status, .history: false
        }
    }

    /// A short result to show beside a page in the sidebar.
    func badge(for screen: Screen) -> String? {
        switch screen {
        case .clean:
            clean.state == .review && clean.report.potentialBytes > 0 ? clean.report.potentialBytes.fileSize : nil
        case .uninstall:
            uninstall.selection.isEmpty ? nil : "\(uninstall.selection.count)"
        case .purge:
            flowBadge(purge)
        case .installers:
            flowBadge(installers)
        case .slim:
            flowBadge(slim)
        case .overview, .optimize, .analyze, .status, .history:
            nil
        }
    }

    private func flowBadge(_ flow: MenuFlowModel) -> String? {
        flow.state == .choosing && !flow.selection.isEmpty ? flow.selectedBytes.fileSize : nil
    }

    /// The line under the window title.
    var subtitle: String {
        let detail: String
        switch selection {
        case .clean:
            detail = clean.state == .review ? clean.summaryLine : ""
        case .uninstall:
            detail = uninstall.selectionSummary
        case .purge:
            detail = purge.selectionSummary
        case .installers:
            detail = installers.selectionSummary
        case .slim:
            detail = slim.selectionSummary
        case .overview, .optimize, .analyze, .status, .history:
            detail = ""
        }
        let parts = [detail, effectivePreview ? "Preview Mode" : ""].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var hasPerformedInitialLocate = false

    func locateCLIOnLaunch() async {
        guard !hasPerformedInitialLocate else { return }
        hasPerformedInitialLocate = true
        await locateCLI()
    }

    func locateCLI() async {
        await discoverCLI(customPath: customCLIPath, requiresExactPath: false)
    }

    func useCustomCLI(path: String) async {
        await discoverCLI(customPath: path, requiresExactPath: true)
    }

    private func discoverCLI(customPath: String?, requiresExactPath: Bool) async {
        guard !isShuttingDown else { return }
        let id = UUID()
        discoveryID = id
        isLocating = true
        var found = await locator(customPath)
        guard discoveryID == id, !Task.isCancelled, !isShuttingDown else { return }
        isLocating = false
        if requiresExactPath, let customPath {
            guard found?.executable == customPath else {
                cliChoiceError = "\(customPath.lastPathComponent) couldn’t be used. It isn’t a working copy of Mole, or another account can change it."
                return
            }
            self.customCLIPath = customPath
            defaults?.set(customPath, forKey: CLILocator.customPathKey)
            cliChoiceError = nil
        }
        #if DEBUG
        if environment["BURROW_NO_CLI"] == "1" { found = nil }
        #endif
        if cli != found {
            if found == nil, allRuns.contains(where: \.isRunning) { return }
            if cli != nil { invalidateCLIResults() }
            cli = found
        }
        updateStatusStream()
        #if DEBUG
        if let cli { DebugDriver.runIfRequested(model: self, cli: cli) }
        #endif
    }

    private func invalidateCLIResults() {
        clean.invalidateReview()
        optimize.invalidateReview()
        uninstall.invalidateInventory()
        for flow in [purge, installers, slim] {
            flow.isEditingPaths = false
            if flow.state != .running { flow.abandonSelection() }
        }
        analyze.invalidateCLIResults()
        history.invalidateCLIResults()
        manage.invalidateCLIResults()
    }

    func setWindowVisible(_ visible: Bool) {
        isWindowVisible = visible
        updateStatusStream()
    }

    private func updateStatusStream() {
        guard !isShuttingDown, isWindowVisible, let cli, cli.hasBundledTools else {
            status.stop()
            return
        }
        switch selection {
        case .status: status.start(cli: cli, interval: 2)
        case .overview: status.start(cli: cli, interval: 6)
        case .clean, .uninstall, .purge, .installers, .slim, .optimize, .analyze, .history: status.stop()
        }
    }

    /// Built from `run(for:)`, so that a new page's run can't escape Preview or shutdown.
    var allRuns: [RunController] {
        Screen.allCases.compactMap { run(for: $0) } + [manage.run]
    }

    func run(for screen: Screen) -> RunController? {
        switch screen {
        case .clean: clean.run
        case .uninstall: uninstall.run
        case .purge: purge.run
        case .installers: installers.run
        case .slim: slim.run
        case .optimize: optimize.run
        case .overview, .analyze, .status, .history: nil
        }
    }

    func needsAttention(_ screen: Screen) -> Bool {
        run(for: screen)?.promptRequest != nil
    }

    var attentionScreens: [Screen] {
        Screen.allCases.filter { $0 != selection && needsAttention($0) }
    }

    /// Stop producers before the process registry closes admission and reaps its children.
    func shutdown(lifecycle: ProcessLifecycle = .shared) async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        discoveryID = UUID()
        status.stop()
        if clean.state == .scanning { clean.cancelScan() }
        if optimize.state == .previewing { optimize.cancelPreview() }
        uninstall.cancelLoading()
        history.cancelLoading()
        purge.shutdown()
        installers.shutdown()
        slim.shutdown()
        for run in allRuns { run.cancel() }
        await analyze.shutdown()
        await lifecycle.shutdownAll()
    }

    /// The home directory the CLI works in, which also honors a sandboxed `HOME`.
    static var home: String {
        ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }
}
