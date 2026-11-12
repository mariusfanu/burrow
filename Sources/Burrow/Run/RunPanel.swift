import BurrowCore
import SwiftUI

/// A command at work. While it runs, the page shows what it's doing and how far along it is.
/// When it ends, the result takes over and the log folds away behind Details.
struct RunPanel: View {
    @Bindable var run: RunController
    /// Sheets have no window toolbar, so they carry their own controls.
    var isSheet = false
    var close: (() -> Void)?

    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if run.isTerminalVisible, let terminal = run.terminal {
                TerminalPanel(terminal: terminal, revision: run.screenRevision)
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                    .padding(Theme.Space.item)
                    .transition(Motion.materialize)
            } else {
                RunPanelContent(run: run, showsDetails: $showsDetails)
            }
            if isSheet {
                SheetControls(run: run, close: close)
            }
        }
        .animation(Motion.glide, value: run.isTerminalVisible)
        .animation(Motion.glide, value: showsDetails)
        .toolbar {
            if !isSheet {
                ToolbarItem(placement: .automatic) {
                    TerminalToggle(run: run)
                }
            }
        }
        .sheet(item: $run.promptRequest) { request in
            PromptSheet(request: request, run: run)
        }
        .sensoryFeedback(.levelChange, trigger: run.didSucceed) { _, succeeded in succeeded }
        .onChange(of: run.phase) { Announcer.say(run.completionAnnouncement) }
    }
}

/// What the panel shows in place of the terminal: the result, the log, or both.
struct RunPanelContent: View {
    let run: RunController
    @Binding var showsDetails: Bool

    var body: some View {
        if isFinished, !showsLogByDefault {
            CompletionHero(run: run, showsDetails: $showsDetails)
                .transition(Motion.materialize)
        } else {
            VStack(spacing: 0) {
                if isFinished {
                    CompletionBanner(run: run, showsDetails: $showsDetails)
                        .transition(Motion.materialize)
                } else {
                    RunProgressHeader(run: run)
                        .transition(.opacity)
                }
                RunLogList(run: run)
            }
        }
    }

    private var isFinished: Bool {
        switch run.phase {
        case .finished, .failedToStart: true
        case .idle, .running: false
        }
    }

    /// A failure keeps its log in view, because that's where the reason is.
    private var showsLogByDefault: Bool {
        showsDetails || run.keepsLogAtEnd || (!run.didSucceed && !run.wasCancelled && !run.wasDeclined)
    }
}

private struct TerminalToggle: View {
    @Bindable var run: RunController

    var body: some View {
        Toggle("Terminal", systemImage: "terminal", isOn: $run.isTerminalVisible)
            .disabled(run.terminal == nil)
            .help("Show the command's real terminal, where you can type directly")
    }
}

/// Inline controls for a run shown in a sheet.
private struct SheetControls: View {
    @Bindable var run: RunController
    let close: (() -> Void)?

    var body: some View {
        HStack {
            Toggle("Terminal", systemImage: "terminal", isOn: $run.isTerminalVisible)
                .toggleStyle(.button)
                .disabled(run.terminal == nil)
            Spacer()
            if run.isRunning {
                Button("Cancel", role: .cancel) { run.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else if let close {
                Button("Done", action: close)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.group)
    }
}

/// The top of a running command: its name, its current step, and a bar that moves only when
/// the command really advances.
private struct RunProgressHeader: View {
    let run: RunController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.item) {
            HStack(spacing: Theme.Space.item) {
                ProgressView()
                    .controlSize(.small)
                Text(run.title)
                    .font(.title2)
                    .bold()
                Spacer()
                if let progress = run.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: progress))
                }
            }
            Text(stepText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(Motion.snap, value: stepText)
            if let progress = run.progress {
                LevelBar(fraction: progress)
            }
        }
        .padding([.horizontal, .top], Theme.Space.page)
        .padding(.bottom, Theme.Space.group)
    }

    private var stepText: String {
        if !run.activity.isEmpty { return run.activity }
        if !run.currentSection.isEmpty { return run.currentSection }
        return run.commandLine
    }
}

/// Says that the log has let go of its oldest rows.
struct HiddenLinesNote: View {
    let count: Int

    var body: some View {
        Text("\(count.formatted()) earlier lines aren’t shown.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// The running log. New lines rise in, and the list follows them unless you scroll away.
private struct RunLogList: View {
    let run: RunController
    @State private var follow = LogFollowState()

    private static let bottomID = "run-log-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.snug) {
                    if run.hiddenLineCount > 0 {
                        HiddenLinesNote(count: run.hiddenLineCount)
                    }
                    ForEach(run.lines) { line in
                        LogRow(line: line)
                            .transition(Motion.rise)
                    }
                    if case .failedToStart(let message) = run.phase {
                        InlineNotice(text: message, symbol: "xmark.octagon.fill", tint: .red)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.item)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Coming back to a page mid-run shows the latest output, not the first line.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: LogViewport.self) { geometry in
                LogViewport(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height + geometry.contentInsets.bottom,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { previous, viewport in
                var next = follow
                // Keyboard scrolling may be reported as animating, so also detect upward
                // movement independently of the user-driven trackpad/wheel phases.
                let movedUp = viewport.offset < previous.offset - 1 && viewport.contentHeight >= previous.contentHeight
                next.updateViewport(offset: viewport.offset, contentHeight: viewport.contentHeight, viewportHeight: viewport.viewportHeight, movedUp: movedUp)
                if next != follow { follow = next }
            }
            .onScrollPhaseChange { _, phase in
                follow.userScrolling(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                if !follow.isFollowing {
                    Button("Jump to Latest", systemImage: "arrow.down") {
                        follow.jumpToLatest()
                        withAnimation(Motion.glide) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    }
                    .buttonStyle(.glass)
                    .padding(Theme.Space.item)
                }
            }
            .onChange(of: run.lines.count) {
                guard follow.isFollowing else { return }
                withAnimation(Motion.glide) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: run.startDate) { follow = LogFollowState() }
            .task {
                // Returning mid-run: once row heights are real, land exactly on the latest row.
                try? await Task.sleep(for: .milliseconds(300))
                follow.finishSettling()
                if follow.isFollowing { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }
}
