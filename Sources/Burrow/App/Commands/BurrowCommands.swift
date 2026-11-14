import SwiftUI

/// The menu bar. Standard menus are kept, and every command the app offers appears here.
struct BurrowCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()

        CommandGroup(replacing: .appInfo) {
            Button("About Burrow") {
                AboutPanelController.shared.show()
            }
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { model.isSearchFocused = true }
                .keyboardShortcut("f")
                .disabled(model.isShuttingDown || model.cli == nil || model.selection != .uninstall || model.uninstall.state != .list)
        }

        CommandGroup(before: .sidebar) {
            Button(model.effectivePreview ? "Turn Preview Mode Off" : "Turn Preview Mode On") {
                model.previewMode.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(model.isShuttingDown || !model.isPreviewToggleEnabled)

            Button(model.currentRun?.isTerminalVisible == true ? "Hide Terminal" : "Show Terminal") {
                model.currentRun?.isTerminalVisible.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model.isShuttingDown || model.currentRun?.terminal == nil)
            Divider()
        }

        CommandMenu("Actions") {
            ActionMenuItem(action: model.primaryAction, placeholder: "Start", key: .return, modifiers: .command)
            ActionMenuItem(action: model.reloadAction, placeholder: "Reload", key: "r", modifiers: .command)
            ActionMenuItem(action: model.trashAction, placeholder: "Move to Trash", key: .delete, modifiers: .command)
            Divider()
            Button("Cancel Current Command") { model.cancellationAction?.perform() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.cancellationAction == nil)
        }

        CommandMenu("Go") {
            ForEach(Screen.allCases) { screen in
                Button(screen.title) { model.selection = screen }
                    .keyboardShortcut(screen.goShortcut)
                    .disabled(model.isShuttingDown)
            }
            Divider()
            Button("Back") {
                if let cli = model.cli { model.analyze.goBack(cli: cli) }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(model.isShuttingDown || model.selection != .analyze || !model.analyze.canGoBack)
        }

        CommandGroup(replacing: .help) {
            Link("Burrow Website", destination: AboutView.burrowWebsiteURL)
            Link("Marius Fanu", destination: AboutView.personalWebsiteURL)
            Divider()
            Link("Mole CLI Documentation", destination: URL(string: "https://github.com/tw93/Mole#readme")!)
            Button("Show Mole Logs") {
                let log = AppModel.home + "/Library/Logs/mole/operations.log"
                let target = FileManager.default.fileExists(atPath: log) ? log : (log as NSString).deletingLastPathComponent
                FilePicker.reveal(target)
            }
        }
    }
}
