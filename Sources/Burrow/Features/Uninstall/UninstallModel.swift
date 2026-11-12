import BurrowCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class UninstallModel {
    enum State: Equatable {
        case idle
        case loading
        case list
        case running
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name"
        case size = "Size"
        var id: String { rawValue }
    }

    enum SizeState: Sendable, Equatable {
        case pending
        case measured(Int64)
        case unavailable
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var apps: [InstalledApp] = []
    private(set) var sizes: [String: Int64] = [:]
    private(set) var sizeStates: [String: SizeState] = [:]
    private(set) var isMeasuring = false
    private(set) var hasPendingSizeSort = false
    private var orderedApps: [InstalledApp] = []
    var selection: Set<String> = [] {
        didSet { noteInteraction() }
    }
    var searchText = "" {
        didSet { noteInteraction() }
    }
    var sortOrder = SortOrder.size {
        didSet { applySort() }
    }
    var isConfirmingPermanent = false
    var includePersonalData = false
    var deletePermanently = false
    var errorMessage: String?

    let run: RunController

    init(
        policy: ExecutionPolicy,
        commands: CommandClient = CommandClient(),
        sizeClient: AppSizeClient = AppSizeClient(),
        home: String = AppModel.home
    ) {
        run = RunController(policy: policy)
        self.commands = commands
        self.sizeClient = sizeClient
        self.home = home
    }
    private let home: String
    private var isStale = false
    private var loadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var loadID = UUID()
    private var measurementID = UUID()
    private var measurementWasInteractedWith = false
    private let commands: CommandClient
    private let sizeClient: AppSizeClient

    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? orderedApps : orderedApps.filter {
            $0.name.localizedStandardContains(query)
                || ($0.bundleId?.localizedStandardContains(query) ?? false)
        }
    }

    func sizeState(for app: InstalledApp) -> SizeState {
        sizeStates[app.id] ?? (app.path == nil ? .unavailable : .pending)
    }

    func noteInteraction() {
        if isMeasuring { measurementWasInteractedWith = true }
    }

    func toggleSelection(_ id: InstalledApp.ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Only an explicit sorting action changes order while someone is interacting.
    func applySort() {
        noteInteraction()
        orderedApps = sortedApps()
        hasPendingSizeSort = false
    }

    private func byName(_ first: InstalledApp, _ second: InstalledApp) -> Bool {
        let comparison = first.name.localizedStandardCompare(second.name)
        return comparison == .orderedSame ? first.id < second.id : comparison == .orderedAscending
    }

    private func sortedApps() -> [InstalledApp] {
        switch sortOrder {
        case .name:
            return apps.sorted(by: byName)
        case .size:
            return apps.sorted {
                let firstSize = sizes[$0.id] ?? -1
                let secondSize = sizes[$1.id] ?? -1
                return firstSize == secondSize ? byName($0, $1) : firstSize > secondSize
            }
        }
    }

    var selectedApps: [InstalledApp] {
        apps.filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedApps.compactMap { sizes[$0.id] }.saturatingSum
    }

    /// The line under the window title.
    var selectionSummary: String {
        guard state == .list else { return "" }
        if selection.isEmpty { return "\(apps.count) apps" }
        return "\(selection.count) selected · \(selectedBytes.fileSize)"
    }

    /// Another page changed what's installed, so the list needs reading again.
    func markStale() {
        isStale = true
    }

    /// What the page does on appearing: reads the list unless it's already good.
    func loadIfNeeded(cli: CLIInfo) {
        switch state {
        case .idle where errorMessage == nil: load(cli: cli)
        case .list where isStale: load(cli: cli)
        default: break
        }
    }

    func load(cli: CLIInfo) {
        isStale = false
        let id = UUID()
        loadID = id
        loadTask?.cancel()
        stopMeasurements()
        state = .loading
        errorMessage = nil
        loadTask = Task {
            defer { if loadID == id { loadTask = nil } }
            do {
                let result = try await commands.run(cli.executable, ["uninstall", "--list"], 120)
                try Task.checkCancellation()
                guard loadID == id else { return }
                try result.requireSuccess()
                let list = try InstalledApp.decodeList(Data(result.stdout.utf8))
                let previousOrder = Dictionary(orderedApps.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
                withAnimation(Motion.settle) {
                    apps = list
                    sizes = [:]
                    sizeStates = [:]
                    // A Reload keeps familiar positions until fresh measurements finish.
                    orderedApps = apps.sorted {
                        let first = previousOrder[$0.id] ?? Int.max
                        let second = previousOrder[$1.id] ?? Int.max
                        return first == second ? byName($0, $1) : first < second
                    }
                    selection.formIntersection(Set(list.map(\.id)))
                    state = .list
                }
                measureSizes(list, wasInteractedWith: false)
            } catch is CancellationError {
                return
            } catch {
                guard loadID == id else { return }
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
    }

    /// Measures app bundles with `du`, four at a time, because the CLI's list doesn't include sizes.
    private func measureSizes(_ candidates: [InstalledApp], wasInteractedWith: Bool) {
        let id = UUID()
        measurementID = id
        sizeTask?.cancel()
        measurementWasInteractedWith = wasInteractedWith
        hasPendingSizeSort = false
        let pending = candidates.compactMap { app -> (String, String)? in
            guard let path = app.path else { return nil }
            sizeStates[app.id] = .pending
            return (app.id, path)
        }
        guard !pending.isEmpty else {
            isMeasuring = false
            orderedApps = sortedApps()
            return
        }
        isMeasuring = true
        let sizeClient = sizeClient
        sizeTask = Task {
            defer {
                if measurementID == id {
                    sizeTask = nil
                    isMeasuring = false
                }
            }
            await withTaskGroup(of: (String, SizeState).self) { group in
                var next = 0
                while next < min(4, pending.count) {
                    let (appID, path) = pending[next]
                    next += 1
                    group.addTask { await Self.measure(appID, at: path, using: sizeClient) }
                }
                while let (appID, measurement) = await group.next() {
                    guard measurementID == id, !Task.isCancelled else { continue }
                    sizeStates[appID] = measurement
                    if case .measured(let bytes) = measurement {
                        sizes[appID] = bytes
                    }
                    if next < pending.count {
                        let (appID, path) = pending[next]
                        next += 1
                        group.addTask { await Self.measure(appID, at: path, using: sizeClient) }
                    }
                }
            }
            guard measurementID == id, !Task.isCancelled else { return }
            if !measurementWasInteractedWith {
                orderedApps = sortedApps()
            } else if sortOrder == .size {
                hasPendingSizeSort = orderedApps.map(\.id) != sortedApps().map(\.id)
            }
        }
    }

    /// Keep this `do`/`catch` out of the `addTask` closure. Written inline, Swift 6.4.2 with
    /// optimization makes `group.next()` return nil while children are still running, so the
    /// group is destroyed under them and the app crashes in `TaskGroup::offer`. Debug builds
    /// don't show it, so run the tests in release too (see the README).
    private nonisolated static func measure(_ appID: String, at path: String, using client: AppSizeClient) async -> (String, SizeState) {
        do { return (appID, .measured(try await client.measure(path))) }
        catch { return (appID, .failed(error.localizedDescription)) }
    }

    func retrySize(for app: InstalledApp) {
        guard state == .list, !isMeasuring, app.path != nil else { return }
        measureSizes([app], wasInteractedWith: true)
    }

    private func stopMeasurements() {
        measurementID = UUID()
        sizeTask?.cancel()
        sizeTask = nil
        isMeasuring = false
        for (id, measurement) in sizeStates where measurement == .pending {
            sizeStates[id] = .failed("Measurement stopped. Try again.")
        }
    }

    func cancelLoading() {
        loadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        stopMeasurements()
        if state == .loading { state = .idle }
    }

    /// Starts the CLI on the chosen apps. It prints its plan and waits for an answer,
    /// which the run panel relays as a native confirmation. The CLI takes names, not
    /// locations, so that question only appears if its plan names exactly the chosen apps.
    func beginRemoval(cli: CLIInfo, preview: Bool) {
        let chosen = selectedApps
        guard !chosen.isEmpty else { return }
        var arguments = ["uninstall"]
        if preview { arguments.append("--dry-run") }
        if includePersonalData { arguments.append("--with-data") }
        if deletePermanently, !preview { arguments.append("--permanent") }
        arguments += UninstallTargeting.terms(for: chosen, among: apps)

        stopMeasurements()
        errorMessage = nil
        state = .running
        run.start(
            title: preview ? "Previewing Removal" : "Uninstalling",
            doneTitle: preview ? "Preview Finished" : "Uninstalled",
            cli: cli,
            arguments: arguments,
            rows: 60,
            columns: 180,
            consequence: preview ? nil : removalConsequence,
            isIrreversible: deletePermanently,
            confirmationCheck: { [weak self] lines in
                self?.planMatches(lines, chosen: chosen) ?? false
            }
        )
    }

    /// Says what the options on this removal mean, beside the CLI's question.
    var removalConsequence: String {
        var parts = [deletePermanently
            ? "Skip the Trash is on: removed files can’t be restored."
            : "Mole moves these apps and their files to the Trash."]
        if includePersonalData { parts.append("Personal data these apps keep is included.") }
        return parts.joined(separator: " ")
    }

    /// Options that widen a removal, which the page keeps in view while they're on.
    var activeOptionsNotice: String? {
        guard deletePermanently || includePersonalData else { return nil }
        var parts: [String] = []
        if deletePermanently { parts.append("Skip the Trash is on, so removed files can’t be restored.") }
        if includePersonalData { parts.append("Include Personal Data is on, so the settings and documents these apps keep are removed too.") }
        return parts.joined(separator: " ")
    }

    func clearRemovalOptions() {
        deletePermanently = false
        includePersonalData = false
    }

    /// Stops the command at its question when it would remove anything but the chosen apps.
    private func planMatches(_ lines: [String], chosen: [InstalledApp]) -> Bool {
        let planned = UninstallPlan.appPaths(in: lines, home: home)
        let expected = chosen.map(\.path)
        guard planned != Set(expected.compactMap { $0 }) || expected.contains(nil) else { return true }
        run.reset()
        errorMessage = "The CLI’s plan didn’t match the apps you chose, so nothing was removed. "
            + "Apps with the same name can’t always be told apart. "
            + "Run mo uninstall in Terminal to choose from its own list."
        // These widen what a removal does, so a stopped attempt mustn't pass them on.
        clearRemovalOptions()
        state = .idle
        return false
    }

    func finishRun(cli: CLIInfo) {
        let changedSomething = run.didSucceed
        run.reset()
        if changedSomething { selection = [] }
        // These widen what a removal does, so they never carry over to the next one.
        clearRemovalOptions()
        load(cli: cli)
    }
}
