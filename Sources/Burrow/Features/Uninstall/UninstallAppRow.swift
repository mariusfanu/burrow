import BurrowCore
import SwiftUI

/// Local actions let unchanged rows skip other apps' measurement updates.
struct UninstallAppRow: View {
    let app: InstalledApp
    let sizeState: UninstallModel.SizeState
    let largestSize: Int64
    let isSelected: Bool
    let model: UninstallModel
    @Binding var focusedRow: InstalledApp.ID?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.cluster) {
            SelectionCheckbox(title: app.name, isSelected: isSelected, toggle: toggle)
            AppIconView(path: app.path)
                .scaleEffect(isHovered && !Motion.isReduced ? 1.06 : 1)
            VStack(alignment: .leading, spacing: Theme.Space.micro) {
                Text(app.name)
                    .font(.body)
                    .bold(isSelected)
                    .lineLimit(1)
                Text(app.path?.abbreviatingHome ?? app.bundleId ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let source = app.source, source != "App" {
                FactTag(text: source, tint: .blue)
            }
            UninstallSizeColumn(app: app, state: sizeState, largestSize: largestSize, model: model)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
        .onHover { isHovered = $0 }
        .animation(Motion.snap, value: isHovered)
        .animation(Motion.snap, value: isSelected)
        .contextMenu {
            if let path = app.path {
                Button("Show in Finder") { FilePicker.reveal(path) }
            }
        }
    }

    private func toggle() {
        focusedRow = app.id
        withAnimation(Motion.snap) { model.toggleSelection(app.id) }
    }
}
