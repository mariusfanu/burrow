import BurrowCore
import SwiftUI

struct HistoryView: View {
    @Bindable var model: HistoryModel
    let cli: CLIInfo

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage {
                HStack {
                    InlineNotice(text: message, tint: .red)
                    Button("Retry", action: retry)
                        .disabled(model.isLoading)
                }
                .padding(Theme.Space.item)
            }
            if model.report == nil, model.errorMessage != nil {
                ContentUnavailableView("History Couldn’t Be Loaded", systemImage: "exclamationmark.triangle")
            } else if model.showsFiles {
                HistoryFiles(rows: model.report?.deletions ?? [])
                    .transition(.opacity)
            } else {
                HistorySessions(model: model)
                    .transition(.opacity)
            }
        }
        .animation(Motion.snap, value: model.showsFiles)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $model.showsFiles) {
                    Text("Sessions").tag(false)
                    Text("Files").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .automatic) {
                Menu("View Options", systemImage: "line.3.horizontal.decrease") {
                    Toggle("Include Previews", isOn: $model.includesPreviews)
                    if let path = model.report?.logs?.operations {
                        Button("Show Logs in Finder") { FilePicker.reveal(path) }
                    }
                }
                .help("Filter the history or find its log files")
            }
        }
        .task(load)
    }

    @Sendable
    private func load() async {
        model.load(cli: cli)
    }

    private func retry() { model.load(cli: cli) }
}

private struct HistorySessions: View {
    let model: HistoryModel

    private var visibleSessions: [HistoryReport.Session] {
        (model.report?.sessions ?? []).filter { session in
            guard (session.items ?? 0) > 0 || (session.operationCount ?? 0) > 0 else { return false }
            return model.includesPreviews || !session.isPreview
        }
    }

    var body: some View {
        let sessions = visibleSessions
        let realSessions = sessions.filter { !$0.isPreview }
        let totalFreed = realSessions.compactMap { SizeText.bytes(from: $0.size ?? "") }.saturatingSum
        if sessions.isEmpty {
            if model.isLoading, model.report == nil {
                WorkingView(title: "Reading the Logs")
            } else {
                ContentUnavailableView(
                    "Nothing Here Yet",
                    systemImage: "clock",
                    description: Text("Sessions appear here after Mole changes something.")
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.group) {
                    VStack(alignment: .leading, spacing: Theme.Space.micro) {
                        HeroNumber(text: totalFreed.fileSize, value: Double(totalFreed))
                        Text("freed across ^[\(realSessions.count) session](inflect: true)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .arrives()
                    LazyVStack(spacing: Theme.Space.row) {
                        ForEach(sessions.enumerated(), id: \.element.id) { index, session in
                            SessionRow(session: session)
                                .arrives(index: index + 1)
                        }
                    }
                    .animation(Motion.settle, value: sessions.map(\.id))
                }
                .padding(Theme.Space.page)
            }
        }
    }
}

private struct SessionRow: View {
    let session: HistoryReport.Session

    var body: some View {
        Surface(padding: Theme.Space.cluster) {
            HStack(spacing: Theme.Space.cluster) {
                Image(systemName: session.symbol)
                    .font(.title3)
                    .foregroundStyle(session.isPreview ? Color.secondary : Color.accentColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.micro) {
                    HStack(spacing: Theme.Space.snug) {
                        Text(session.title)
                            .font(.body)
                            .bold()
                        if session.isPreview {
                            FactTag(text: "Preview", tint: .blue)
                        }
                        if session.hadFailures {
                            FactTag(text: "Had Failures", tint: .red)
                        }
                    }
                    Text(session.startedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(session.startedAt ?? "")
                }
                Spacer()
                Text(session.actionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                VStack(alignment: .trailing, spacing: 1) {
                    if let size = session.sizeText {
                        Text(size)
                            .font(.body)
                            .bold()
                            .monospacedDigit()
                    }
                    if let items = session.itemsText {
                        Text(items)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(width: 92, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryFiles: View {
    let rows: [HistoryReport.Deletion]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                "No Files Recorded",
                systemImage: "doc",
                description: Text("Individual removals appear here once Mole’s deletion log has entries.")
            )
        } else {
            List(rows) { row in
                HStack(spacing: Theme.Space.item) {
                    Image(systemName: row.mode == "trash" ? "trash" : "xmark.bin")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityLabel(row.mode ?? "")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.path?.abbreviatingHome ?? "")
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(row.timestampText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let status = row.status, status != "ok" {
                        FactTag(text: status, tint: .red)
                    }
                    if let bytes = row.bytes {
                        Text(bytes.fileSize)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
