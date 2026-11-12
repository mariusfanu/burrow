import SwiftUI

/// Sorting and removal options, gathered so that the list itself stays quiet.
struct UninstallOptionsMenu: View {
    @Bindable var model: UninstallModel
    let isPreview: Bool

    var body: some View {
        Menu("Options", systemImage: "line.3.horizontal.decrease") {
            Picker("Sort By", selection: $model.sortOrder) {
                ForEach(UninstallModel.SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            if model.hasPendingSizeSort {
                Button("Apply Size Order", systemImage: "arrow.up.arrow.down") { model.applySort() }
                    .disabled(model.isMeasuring)
            }
            Divider()
            Toggle("Include Personal Data", isOn: $model.includePersonalData)
                .help("Also removes the settings and documents these apps keep")
            Toggle("Skip the Trash…", isOn: $model.skipsTrash)
                .disabled(isPreview)
            Divider()
            Button("Deselect All", action: deselectAll)
                .disabled(model.selection.isEmpty)
        }
        .help("Change the sort order and removal options")
    }

    private func deselectAll() {
        withAnimation(Motion.snap) { model.selection = [] }
    }
}
