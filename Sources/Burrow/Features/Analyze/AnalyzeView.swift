import BurrowCore
import SwiftUI

struct AnalyzeView: View {
    let model: AnalyzeModel
    let cli: CLIInfo
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            AnalyzePathBar(model: model, cli: cli)
                .disabled(model.isTrashing)
            AnalyzeContent(model: model, cli: cli)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Open Folder…", systemImage: "folder", action: chooseFolder)
                    .disabled(model.isTrashing)
            }
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.backward", action: goBack)
                    .disabled(!model.canGoBack || model.isTrashing)
                    .help("Go to the enclosing folder")
            }
        }
        .task(id: cli) { await start() }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.noticeMessage) { Announcer.say(model.noticeMessage) }
        .onChange(of: model.errorMessage) { Announcer.say(model.errorMessage) }
        .alert(model.pendingTrash?.title ?? "", isPresented: $model.isConfirmingTrash) {
            // Return mustn't be the way a high-risk move happens.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Move to Trash") { model.confirmPendingTrash(cli: cli) }
        } message: {
            Text(model.pendingTrash?.message ?? "")
        }
    }

    @Sendable
    private func start() async {
        model.openRoot(cli: cli)
    }

    private func goBack() {
        model.goBack(cli: cli)
    }

    private func chooseFolder() {
        guard let path = FilePicker.chooseFolder(prompt: "Explore") else { return }
        model.openPath(path, cli: cli)
    }
}
