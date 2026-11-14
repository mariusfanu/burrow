import BurrowCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CleanModel {
    enum State: Equatable {
        case idle
        case scanning
        case review
        case running
    }

    private(set) var state = State.idle
    private(set) var report = CleanReport()
    private(set) var scanActivity = ""
    private(set) var protectedThisSession: Set<String> = []
    var errorMessage: String?
    var expandedSections: Set<String> = []
    var isChoosingVolume = false
    var isConfirming = false
    /// The volume waiting on the confirmation that a real cleanup requires.
    private(set) var volumeAwaitingConfirmation: String?
    private var volumeConfirmationCLI: CLIInfo?
    private var reviewCLI: CLIInfo?

    /// Whether the external-volume question is on screen. Cancel and Confirm clear
    /// `volumeAwaitingConfirmation` explicitly so SwiftUI dismissing the alert first cannot no-op.
    var isConfirmingExternalClean: Bool {
        get { volumeAwaitingConfirmation != nil }
        set {}
    }


    let run: RunController
    private var scanTask: Task<Void, Never>?
    private var activePreview: CleanPreviewStream?
    private var scanID = UUID()
    private let commands: CommandClient
    private let policy: ExecutionPolicy
    private let home: String

    init(commands: CommandClient = CommandClient(), policy: ExecutionPolicy, home: String = AppModel.home) {
        self.commands = commands
        self.policy = policy
        self.home = home
        run = RunController(policy: policy)
    }

    subscript(isExpanded id: String) -> Bool {
        get { expandedSections.contains(id) }
        set {
            if newValue { expandedSections.insert(id) }
            else { expandedSections.remove(id) }
        }
    }

    /// Runs `mo clean --dry-run`, then reads the path list it writes.
    func scan(cli: CLIInfo) {
        reviewCLI = nil
        let id = UUID()
        scanID = id
        scanTask?.cancel()
        activePreview?.cancel()
        report = CleanReport()
        expandedSections = []
        state = .scanning
        scanActivity = "Starting"
        errorMessage = nil
        let preview = CleanPreviewStream(pathListURL: URL(fileURLWithPath: home + "/.config/mole/clean-list.txt"))
        activePreview = preview
        scanTask = Task {
            let updateTask = Task { [self] in
                for await partial in preview.updates {
                    guard self.scanID == id, self.state == .scanning else { continue }
                    self.scanActivity = partial.sections.last.map { "Checking \($0.name)" } ?? "Starting"
                    withAnimation(Motion.settle) { self.report = partial }
                }
            }
            defer {
                updateTask.cancel()
                preview.cancel()
                if scanID == id {
                    scanTask = nil
                    activePreview = nil
                }
            }
            do {
                let status = try await commands.stream(
                    cli.executable, ["clean", "--dry-run"], { preview.append($0) }
                )
                try Task.checkCancellation()
                guard scanID == id else { return }
                guard status == 0 else { throw CommandError.failed(status: status, message: "The preview didn't finish.") }
                let finished = await preview.finish()
                try Task.checkCancellation()
                guard scanID == id else { return }
                withAnimation(Motion.glide) {
                    report = finished
                    protectedThisSession = []
                    scanActivity = ""
                    reviewCLI = cli
                    state = .review
                }
            } catch is CancellationError {
                if scanID == id { state = .idle }
            } catch {
                guard scanID == id else { return }
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
    }

    /// The question before a real cleanup, which covers more than caches.
    var confirmationMessage: String { Self.confirmationMessage(for: report) }

    static func confirmationMessage(for report: CleanReport) -> String {
        let base = "This removes everything in the report, not only caches. It can’t be undone, and protected items are left alone."
        guard report.emptiesTrash else { return base }
        return "\(base)\n\nThis also permanently empties your Trash, including anything you moved there with Burrow."
    }

    /// The line under the window title once a scan has finished.
    var summaryLine: String {
        let groups = report.sections.filter { !$0.isEmpty }.count
        if let count = report.itemCount { return "\(count) items in \(groups) groups" }
        return "\(groups) groups"
    }

    func cancelScan() {
        scanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        activePreview?.cancel()
        activePreview = nil
        state = .idle
    }

    /// Runs the real cleanup. The CLI itself raises any admin question.
    func clean(cli: CLIInfo, preview: Bool) {
        guard state == .review, reviewCLI == cli else { return }
        state = .running
        run.start(
            title: preview ? "Previewing Cleanup" : "Cleaning",
            doneTitle: preview ? "Preview Finished" : "All Clean",
            expectedSections: report.sections.count,
            cli: cli,
            arguments: preview ? ["clean", "--dry-run"] : ["clean"]
        )
    }

    /// Starts from the volume sheet. The CLI doesn't ask before this cleanup and it can't be
    /// undone, so a real one waits for `confirmExternalClean`. A preview changes nothing.
    func requestExternalClean(path: String, cli: CLIInfo, preview: Bool) {
        guard !preview else {
            isChoosingVolume = false
            cleanExternal(path: path, cli: cli, preview: true)
            return
        }
        volumeAwaitingConfirmation = path
        volumeConfirmationCLI = cli
    }

    func confirmExternalClean(cli: CLIInfo) {
        guard let path = volumeAwaitingConfirmation, volumeConfirmationCLI == cli else { return }
        cancelExternalClean()
        isChoosingVolume = false
        cleanExternal(path: path, cli: cli, preview: false)
    }

    func cancelExternalClean() {
        volumeAwaitingConfirmation = nil
        volumeConfirmationCLI = nil
    }

    /// Cleans OS metadata from a mounted external volume.
    private func cleanExternal(path: String, cli: CLIInfo, preview: Bool) {
        state = .running
        var arguments = ["clean", "--external", path]
        if preview { arguments.append("--dry-run") }
        run.start(title: "Cleaning \(path.lastPathComponent)", doneTitle: "All Clean", cli: cli, arguments: arguments)
    }

    func finishRun() {
        run.reset()
        state = .idle
    }

    func invalidateReview() {
        isConfirming = false
        cancelExternalClean()
        isChoosingVolume = false
        reviewCLI = nil
        guard state != .running else { return }
        cancelScan()
        report = CleanReport()
        errorMessage = nil
    }

    /// Adds a path to the CLI's whitelist so that cleanup leaves it alone.
    func protect(path: String, cli: CLIInfo) {
        guard !policy.effectivePreview else { return }
        do {
            try WhitelistStore(home: home, cliRoot: cli.root).add(path)
            protectedThisSession.insert(path)
        } catch {
            let message = "Couldn't update the protected list: \(error.localizedDescription)"
            errorMessage = message
            Announcer.say(message)
        }
    }
}
