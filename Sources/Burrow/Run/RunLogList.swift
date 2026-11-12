import SwiftUI

/// The running log. New lines rise in, and the list follows them unless you scroll away.
struct RunLogList: View {
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
