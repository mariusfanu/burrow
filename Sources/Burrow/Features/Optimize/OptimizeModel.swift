import BurrowCore
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class OptimizeModel {
    enum State: Equatable {
        case idle
        case previewing
        case review
        case running
    }

    private(set) var state = State.idle
    private(set) var lines: [LogLine] = []
    private(set) var activity = ""
    private(set) var errorMessage: String?
    var isConfirming = false

    let run: RunController
    private var task: Task<Void, Never>?
    private var previewID = UUID()
    private var reviewCLI: CLIInfo?
    private let commands: CommandClient

    init(commands: CommandClient = CommandClient(), policy: ExecutionPolicy) {
        self.commands = commands
        run = RunController(policy: policy)
    }

    /// Parses `mo optimize --dry-run`.
    func preview(cli: CLIInfo) {
        reviewCLI = nil
        let id = UUID()
        previewID = id
        task?.cancel()
        state = .previewing
        activity = "Checking this Mac…"
        errorMessage = nil
        let buffer = LineOutputBuffer()
        let note: @MainActor @Sendable (String) -> Void = { [weak self] line in
            guard let self, self.previewID == id else { return }
            self.noteProgress(line)
        }
        task = Task {
            defer { if previewID == id { task = nil } }
            do {
                let status = try await commands.stream(
                    cli.executable, ["optimize", "--dry-run"], { chunk in
                        buffer.append(chunk)
                        Task { @MainActor in note(buffer.latestLine) }
                    }
                )
                try Task.checkCancellation()
                guard previewID == id else { return }
                let output = buffer.finish()
                // Mole returns 1 after printing the complete plan when an individual check fails.
                let completedWithFailures = status == 1 && output.contains {
                    $0.trimmingCharacters(in: .whitespaces) == "Dry Run Complete, No Changes Made"
                }
                guard status == 0 || completedWithFailures else {
                    throw CommandError.failed(status: status, message: "The preview didn't finish.")
                }
                withAnimation(Motion.glide) {
                    lines = Self.parse(lines: output)
                    if completedWithFailures {
                        errorMessage = "Some maintenance checks failed. Review the results and check again before running maintenance."
                    }
                    state = .review
                    reviewCLI = cli
                }
            } catch is CancellationError {
                if previewID == id { state = .idle }
            } catch {
                guard previewID == id else { return }
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
    }

    static func parse(_ output: String) -> [LogLine] {
        parse(lines: ANSI.strip(output).split(separator: "\n").map(String.init))
    }

    static func parse(lines: [String]) -> [LogLine] {
        lines
            .filter { !$0.isEmpty && !LogLine.isDecoration($0) && !$0.contains("DRY RUN MODE") && $0.trimmingCharacters(in: .whitespaces) != "Optimize" }
            .enumerated()
            .map { LogLine(id: $0.offset, raw: $0.element) }
    }

    private func noteProgress(_ line: String) {
        guard state == .previewing, !line.isEmpty else { return }
        activity = LogLine(id: 0, raw: line).title
    }

    func cancelPreview() {
        previewID = UUID()
        task?.cancel()
        task = nil
        state = .idle
    }

    func runMaintenance(cli: CLIInfo, preview: Bool) {
        guard preview || (state == .review && reviewCLI == cli && errorMessage == nil) else { return }
        state = .running
        run.start(
            title: preview ? "Previewing Maintenance" : "Running Maintenance",
            doneTitle: preview ? "Preview Finished" : "Maintenance Finished",
            expectedSections: lines.filter { $0.kind == .section }.count,
            cli: cli,
            arguments: preview ? ["optimize", "--dry-run"] : ["optimize"]
        )
    }

    func finishRun(cli: CLIInfo) {
        run.reset()
        preview(cli: cli)
    }

    func invalidateReview() {
        isConfirming = false
        reviewCLI = nil
        guard state != .running else { return }
        cancelPreview()
        lines = []
        errorMessage = nil
    }
}
