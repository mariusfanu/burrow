import SwiftUI

/// The window's trailing controls: the page's commands, then its one prominent action.
struct AppToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .automatic) {
            Toggle("Preview Mode", systemImage: model.effectivePreview ? "eye.fill" : "eye", isOn: $model.previewMode)
                .disabled(!model.isPreviewToggleEnabled)
                .contentTransition(.symbolEffect(.replace))
                .help(model.previewToggleHelp)
        }
        if !model.attentionScreens.isEmpty {
            ToolbarItem(placement: .automatic) {
                Menu("Needs Attention", systemImage: "exclamationmark.circle") {
                    ForEach(model.attentionScreens) { screen in
                        Button("Continue \(screen.title)") { model.selection = screen }
                    }
                }
                .help("A command on another page is waiting for your answer")
            }
        }
        if let secondary = model.secondaryAction {
            ToolbarItem(placement: .automatic) {
                SecondaryToolbarButton(action: secondary)
            }
        }
        if let primary = model.primaryAction, primary.showsInToolbar {
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(action: primary)
            }
        }
    }
}
