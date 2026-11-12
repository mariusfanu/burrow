import BurrowCore
import Foundation
import Observation
import SwiftUI

/// Runs one CLI command on a pseudo-terminal and publishes its progress to views.
@MainActor
@Observable
final class RunController {
    enum Phase: Equatable {
        case idle
        case running
        case finished(status: Int32)
        case failedToStart(String)
    }

    private(set) var phase = Phase.idle
    private(set) var title = ""
    private(set) var commandLine = ""
    private(set) var lines: [LogLine] = []
    private(set) var activity = ""
    /// Bumped on every terminal repaint so the terminal panel redraws.
    private(set) var screenRevision = 0
    var promptRequest: PromptRequest?
    var isTerminalVisible = false {
        didSet {
            // Hiding the terminal with its question unanswered brings the sheet back.
            guard oldValue, !isTerminalVisible, promptIsInTerminal else { return }
            promptIsInTerminal = false
            answeredPartial = nil
            terminalChanged()
        }
    }
    private(set) var wasCancelled = false
    /// True when the CLI's own question was answered with Cancel, so nothing changed.
    private(set) var wasDeclined = false
    /// True for a `--dry-run`, whose questions don't lead to any change.
    private(set) var isPreview = false
    /// Keeps the log open at the end, for commands whose output is the result.
    private(set) var keepsLogAtEnd = false

    /// What the finished state calls itself, such as "All Clean".
    private(set) var doneTitle = "Done"
    /// How many sections the plan expects, which makes progress determinate.
    private(set) var expectedSections = 0
    private(set) var completedSections = 0
    private(set) var currentSection = ""
    private(set) var summary: RunSummary?
    private(set) var startDate: Date?
    private(set) var duration: TimeInterval = 0
    /// Counts rejected passwords, so that the next password sheet can say so.
    private(set) var passwordRejections = 0

    /// What confirming will do, for the sheet that relays the CLI's question. The CLI's own
    /// wording doesn't say whether files can be restored.
    private(set) var consequence: String?
    /// True when confirming can't be undone, so that Return alone mustn't confirm it.
    private(set) var isIrreversible = false
    /// How many old lines have left the log, which holds a bounded number of rows.
    private(set) var hiddenLineCount = 0

    /// Hides the rows of a selection list from the log while it is being operated.
    var isLogSuppressed = false

    /// Called when a real command ends having been allowed to change things, even partly.
    var onFinishedChanges: (@MainActor () -> Void)?

    private(set) var terminal: CLITerminal?
    private var nextLineID = 0
    private var pendingLines: [LogLine] = []
    private var lineFlush: Task<Void, Never>?
    private var menuCheck: (revision: Int, isOnScreen: Bool)?
    private var answeredPartial: String?
    private var promptIsInTerminal = false
    private var confirmationCheck: (@MainActor ([String]) -> Bool)?
    private var promptCheck: Task<Void, Never>?
    private let policy: ExecutionPolicy

    private static let lineFlushInterval = Duration.milliseconds(100)
    private static let maximumLogRows = 20_000

    init(policy: ExecutionPolicy) {
        self.policy = policy
    }

    var isRunning: Bool { phase == .running }

    var didSucceed: Bool {
        if case .finished(let status) = phase { return status == 0 && !wasCancelled && !wasDeclined }
        return false
    }

    /// Starts the command. Selection menus pass a tall terminal so every row fits on one page.
    func start(
        title: String,
        doneTitle: String = "Done",
        expectedSections: Int = 0,
        cli: CLIInfo,
        arguments: [String],
        rows: Int = 50,
        columns: Int = 120,
        showsTerminal: Bool = false,
        keepsLogAtEnd: Bool = false,
        consequence: String? = nil,
        isIrreversible: Bool = false,
        confirmationCheck: (@MainActor ([String]) -> Bool)? = nil
    ) {
        reset()
        self.confirmationCheck = confirmationCheck
        self.title = title
        self.keepsLogAtEnd = keepsLogAtEnd
        self.consequence = consequence
        self.isIrreversible = isIrreversible
        isPreview = arguments.contains("--dry-run")
        self.doneTitle = doneTitle
        self.expectedSections = expectedSections
        startDate = Date.now
        commandLine = (["mo"] + arguments).joined(separator: " ")
        isTerminalVisible = showsTerminal
        guard !policy.effectivePreview || isPreview else {
            phase = .failedToStart("Preview Mode prevents this command from making changes. Start a preview instead.")
            return
        }
        do {
            let terminal = try CLITerminal(
                executable: cli.executable,
                arguments: arguments,
                environment: CLILocator.environment(),
                rows: rows,
                columns: columns
            )
            terminal.onLine = { [weak self, weak terminal] line in
                guard let self, let terminal, self.terminal === terminal else { return }
                self.append(line)
            }
            terminal.onChange = { [weak self, weak terminal] in
                guard let self, let terminal, self.terminal === terminal else { return }
                self.terminalChanged()
            }
            terminal.onExit = { [weak self, weak terminal] status in
                guard let self, let terminal, self.terminal === terminal else { return }
                self.finish(status: status)
            }
            self.terminal = terminal
            phase = .running
        } catch {
            phase = .failedToStart(error.localizedDescription)
        }
    }

    func retitle(_ newTitle: String, doneTitle newDoneTitle: String) {
        title = newTitle
        doneTitle = newDoneTitle
    }

    /// Drops what was logged so far, such as the first paint of a selection list.
    func clearLog() {
        lineFlush?.cancel()
        lineFlush = nil
        pendingLines = []
        lines = []
        hiddenLineCount = 0
    }

    /// Progress from 0 to 1 when the plan's length is known.
    var progress: Double? {
        guard expectedSections > 0 else { return nil }
        return min(Double(completedSections) / Double(expectedSections), 1)
    }

    func reset() {
        terminal?.onLine = nil
        terminal?.onChange = nil
        terminal?.onExit = nil
        if terminal?.isRunning == true { terminal?.cancel() }
        phase = .idle
        clearLog()
        activity = ""
        expectedSections = 0
        completedSections = 0
        currentSection = ""
        summary = nil
        startDate = nil
        duration = 0
        passwordRejections = 0
        promptRequest = nil
        promptCheck?.cancel()
        promptCheck = nil
        answeredPartial = nil
        promptIsInTerminal = false
        confirmationCheck = nil
        wasCancelled = false
        wasDeclined = false
        isPreview = false
        keepsLogAtEnd = false
        consequence = nil
        isIrreversible = false
        menuCheck = nil
        isLogSuppressed = false
        nextLineID = 0
        terminal = nil
    }

    func cancel() {
        guard isRunning else { return }
        wasCancelled = true
        promptRequest = nil
        promptCheck?.cancel()
        promptCheck = nil
        terminal?.cancel()
    }

    func send(_ text: String) {
        terminal?.send(text)
    }

    // MARK: - Answering prompts

    private func markAnswered() {
        answeredPartial = terminal?.partial
        promptRequest = nil
    }

    /// Answers in the terminal instead. The question stays unanswered, so it mustn't count as
    /// new when the terminal's first resize reports the same text again.
    func showTerminalForPrompt() {
        markAnswered()
        promptIsInTerminal = true
        isTerminalVisible = true
    }

    func answerConfirm() {
        guard mayAnswerCommand() else { return }
        markAnswered()
        terminal?.send("\r")
    }

    func answerDecline() {
        wasDeclined = true
        markAnswered()
        terminal?.send("\u{1B}")
    }

    func answerYesNo(_ yes: Bool) {
        guard mayAnswerCommand() else { return }
        markAnswered()
        terminal?.send(yes ? "y\r" : "n\r")
    }

    func answerSystemClean(useAdmin: Bool) {
        guard mayAnswerCommand() else { return }
        markAnswered()
        terminal?.send(useAdmin ? "\r" : " ")
    }

    /// Hands the password to `sudo` and keeps no copy of it.
    func answerPassword(_ password: String) {
        guard mayAnswerCommand() else { return }
        // Re-checked at the last moment: with echo on, the text would appear on screen.
        guard let terminal, terminal.isEchoOff else {
            promptRequest = nil
            return
        }
        markAnswered()
        terminal.send(password + "\r")
    }

    private func mayAnswerCommand() -> Bool {
        guard !policy.effectivePreview || isPreview else {
            cancel()
            return false
        }
        return true
    }

    /// Abandons a password prompt, which `sudo` treats as Ctrl-C.
    func answerPasswordCancel() {
        markAnswered()
        terminal?.send("\u{03}")
    }

    // MARK: - Terminal events

    private func append(_ raw: String) {
        // A finished line means the prompt that was answered is gone, so identical text
        // on the new line is a new question. sudo re-asks with the same "Password:".
        answeredPartial = nil
        guard !isLogSuppressed, !LogLine.isDecoration(raw) else { return }
        // A prompt line reaches the log once answered; the sheet already showed it.
        if PromptDetector.detect(partial: raw) != nil { return }
        if raw.contains("Sorry, try again") {
            passwordRejections += 1
            return
        }
        if LogLine.isChatter(raw) || isMenuRepaint(raw) { return }
        let line = LogLine(id: nextLineID, raw: raw)
        nextLineID += 1
        pendingLines.append(line)
        scheduleLineFlush()
        if line.kind == .section {
            currentSection = line.title
            withAnimation(Motion.lift) { completedSections += 1 }
        }
    }

    /// Large runs print far faster than anyone can read, and each update to `lines` makes the
    /// log re-diff and scroll, so rows reach the view in batches.
    private func scheduleLineFlush() {
        guard lineFlush == nil else { return }
        lineFlush = Task { [weak self] in
            try? await Task.sleep(for: Self.lineFlushInterval)
            guard !Task.isCancelled else { return }
            self?.flushLines()
        }
    }

    private func flushLines() {
        lineFlush?.cancel()
        lineFlush = nil
        guard !pendingLines.isEmpty else { return }
        // Only a modest list is worth animating.
        if lines.count < 300 {
            withAnimation(Motion.snap) { lines.append(contentsOf: pendingLines) }
        } else {
            lines.append(contentsOf: pendingLines)
        }
        pendingLines = []
        if lines.count > Self.maximumLogRows {
            let excess = lines.count - Self.maximumLogRows
            lines.removeFirst(excess)
            hiddenLineCount += excess
        }
    }

    /// A selection list repainting itself is not progress. An unselected row looks just like
    /// the `  ○ item` a dry run reports, so that shape counts only while a list is on screen.
    private func isMenuRepaint(_ raw: String) -> Bool {
        if MenuParser.isKeyHint(raw) { return true }
        guard let row = MenuParser.parseRow(raw) else { return false }
        if row.isCursor || row.isSelected { return true }
        return isMenuOnScreen
    }

    /// Reading the whole screen for each row would make a long listing quadratic, so the
    /// answer is kept until the screen next changes.
    private var isMenuOnScreen: Bool {
        guard let terminal else { return false }
        let revision = terminal.screen.revision
        if let menuCheck, menuCheck.revision == revision { return menuCheck.isOnScreen }
        let isOnScreen = terminal.screen.lines.contains(where: MenuParser.isKeyHint)
        menuCheck = (revision, isOnScreen)
        return isOnScreen
    }

    private func terminalChanged() {
        screenRevision &+= 1
        guard let terminal else { return }
        let partial = terminal.partial
        if partial != answeredPartial { answeredPartial = nil }
        guard !isLogSuppressed else { return }

        let detected = PromptDetector.detect(partial: partial)
        activity = detected == nil ? cleanActivity(partial) : ""
        guard answeredPartial == nil else { return }

        guard let prompt = detected else {
            promptCheck?.cancel()
            promptCheck = nil
            promptRequest = nil
            return
        }
        guard promptRequest?.prompt != prompt else { return }

        // A prompt waits, while progress text moves on. Raise a sheet only for text that
        // has held still, so that a passing line that looks like a question can't.
        promptCheck?.cancel()
        promptCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.raisePrompt(prompt, ifStill: partial)
        }
    }

    private func raisePrompt(_ prompt: CLIPrompt, ifStill partial: String) {
        // The child may remain alive during cancellation's grace period.
        guard !wasCancelled, let terminal, terminal.isRunning, terminal.partial == partial else { return }
        if case .password = prompt, !terminal.isEchoOff { return }
        // The plan beside the question, and the one being checked, must be complete.
        flushLines()
        if case .confirm = prompt, let confirmationCheck, !confirmationCheck(lines.map(\.raw)) { return }
        promptRequest = PromptRequest(prompt: prompt)
    }

    private func cleanActivity(_ text: String) -> String {
        // Drop the spinner glyph at the front of the CLI's progress line.
        text.startsWithSpinner ? String(text.dropFirst()).trimmingCharacters(in: .whitespaces) : text
    }

    /// What VoiceOver says when the command ends, or nil while it's still going.
    var completionAnnouncement: String? {
        switch phase {
        case .idle, .running:
            return nil
        case .failedToStart(let message):
            return message
        case .finished:
            if wasCancelled { return "\(title) cancelled." }
            if wasDeclined { return "Cancelled. Nothing changed." }
            return didSucceed ? "\(doneTitle)." : "\(title) failed. Details are in the log."
        }
    }

    private func finish(status: Int32) {
        promptCheck?.cancel()
        promptCheck = nil
        flushLines()
        summary = RunSummary.parse(lines: lines.lazy.map(\.raw))
        if let startDate { duration = Date.now.timeIntervalSince(startDate) }
        withAnimation(Motion.settle) {
            phase = .finished(status: status)
            if status == 0 { completedSections = expectedSections }
        }
        activity = ""
        promptRequest = nil
        if !isPreview, !wasDeclined { onFinishedChanges?() }
    }
}
