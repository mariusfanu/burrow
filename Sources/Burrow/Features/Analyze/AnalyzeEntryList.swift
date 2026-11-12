import BurrowCore
import SwiftUI

/// The same entries as the map, with native selection, arrow keys and Return to open.
struct AnalyzeEntryList: View {
    @Bindable var model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.entries.enumerated(), id: \.element.id) { rank, entry in
                AnalyzeEntryRow(
                    entry: entry,
                    tint: Theme.tile(rank: rank, parent: model.current?.tint),
                    total: model.result?.totalSize ?? 0,
                    model: model,
                    canTrash: model.canTrash(entry)
                )
                .tag(entry.path)
                .onHover { inside in model.setHovered(entry.path, inside: inside) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(Motion.lift, value: model.entries)
        .onChange(of: model.selection) { old, new in model.noteSelection(added: new.subtracting(old)) }
        .contextMenu(forSelectionType: String.self) { paths in
            AnalyzeEntryMenu(paths: paths, model: model, cli: cli)
        } primaryAction: { paths in
            open(paths)
        }
        .overlay {
            if !model.isLoading, model.entries.isEmpty, model.errorMessage == nil {
                ContentUnavailableView(model.emptyStateTitle, systemImage: "folder")
            }
        }
    }

    private func open(_ paths: Set<String>) {
        guard let path = paths.first,
              let rank = model.entries.firstIndex(where: { $0.path == path }) else { return }
        let entry = model.entries[rank]
        if entry.isDir {
            let tint = Theme.tile(rank: rank, parent: model.current?.tint)
            model.open(entry, tint: tint, rect: model.tileRect(for: entry), cli: cli)
        } else {
            FilePicker.reveal(entry.path)
        }
    }
}
