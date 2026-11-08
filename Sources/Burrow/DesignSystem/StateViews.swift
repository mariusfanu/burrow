import SwiftUI

/// The first thing a tool shows: one symbol, one sentence, and one button. The symbol draws
/// itself in when the page appears.
struct ToolIntro<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var errorMessage: String?
    @ViewBuilder var actions: Actions

    @State private var isDrawn = false

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.drawOn, isActive: !isDrawn)
            }
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: Theme.Space.cluster) {
                if let errorMessage {
                    InlineNotice(text: errorMessage, tint: .red)
                        .frame(maxWidth: 440)
                }
                actions
            }
        }
        .onAppear {
            isDrawn = false
            withAnimation(.easeOut(duration: Motion.isReduced ? 0 : 0.9)) { isDrawn = true }
        }
    }
}

/// A spinner with the task's name and what it's doing right now.
struct WorkingView: View {
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(spacing: Theme.Space.cluster) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.title3)
                .bold()
            Text(detail.isEmpty ? " " : detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
                .animation(Motion.snap, value: detail)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(Motion.materialize)
    }
}

/// One-line messages near the content they're about.
struct InlineNotice: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Dismiss this message")
            }
        }
        .padding(.horizontal, Theme.Space.cluster)
        .padding(.vertical, Theme.Space.row)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.Radius.notice))
        .transition(Motion.rise)
    }
}

/// A notice pinned to the edge of a page.
///
/// Unlike `InlineNotice`, its height is capped. A window measures its minimum size by proposing
/// a very narrow width, and text that insists on its full height would wrap into a column taller
/// than the window, which pushes the whole window's content out of view.
struct NoticeBar: View {
    let text: String
    var symbol = "exclamationmark.triangle.fill"
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            if !symbol.isEmpty {
                Image(systemName: symbol)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .help(text)
            Spacer(minLength: 0)
            if let dismiss {
                Button("Dismiss", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Dismiss this message")
            }
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar, ignoresSafeAreaEdges: [])
    }
}

/// A short pill for facts such as a kind or an age.
struct FactTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, Theme.Space.micro)
            .background(tint.opacity(0.13), in: .capsule)
    }
}

/// A floating confirmation with an optional Undo. It's a control that floats above content,
/// so here Liquid Glass is the right material.
struct GlassToast: View {
    let text: String
    var undo: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .nonRepeating)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.borderless)
                    .bold()
            }
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss this message")
        }
        .padding(.horizontal, Theme.Space.card)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .transition(Motion.materialize)
    }
}
