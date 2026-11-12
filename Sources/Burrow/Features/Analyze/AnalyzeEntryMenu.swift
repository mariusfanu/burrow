import BurrowCore
import SwiftUI

struct AnalyzeEntryMenu: View {
    let paths: Set<String>
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        if let path = paths.first {
            Button("Show in Finder") { FilePicker.reveal(path) }
        }
        Button(model.needsConfirmation(toTrash: paths) ? "Move to Trash…" : "Move to Trash") {
            model.selection = paths
            model.trashSelection(cli: cli)
        }
        .disabled(paths.isEmpty || !model.entries.filter { paths.contains($0.path) }.allSatisfy(model.canTrash))
    }
}
