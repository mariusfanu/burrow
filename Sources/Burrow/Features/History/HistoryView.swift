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
