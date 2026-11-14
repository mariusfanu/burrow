import BurrowCore
import SwiftUI

struct AnalyzeEntryMenu: View {
    let paths: Set<String>
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        if paths.count == 1, let path = paths.first {
            Button("Show in Finder") { FilePicker.reveal(path) }
        }
        Button(model.needsConfirmation(toTrash: paths) ? "Move to Trash…" : "Move to Trash") {
            model.selection = paths
            model.trashSelection(cli: cli)
        }
        .disabled(!model.canTrash(paths: paths))
    }
}
