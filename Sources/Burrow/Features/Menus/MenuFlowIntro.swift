import BurrowCore
import SwiftUI

struct MenuFlowIntro: View {
    @Bindable var model: MenuFlowModel
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    var body: some View {
        ToolIntro(
            symbol: model.configuration.screen.symbol,
            title: model.configuration.idleTitle,
            message: model.configuration.idleMessage,
            errorMessage: model.errorMessage
        ) {
            if model.configuration.managesScanPaths {
                Toggle("Include Empty Folders", isOn: $model.includeEmptyFolders)
                    .toggleStyle(.checkbox)
            }
            HStack {
                if model.configuration.managesScanPaths {
                    Button("Scan Locations…", action: editPaths)
                        .controlSize(.large)
                }
                Button("Scan", action: scan)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $model.isEditingPaths) {
            PurgePathsSheet()
        }
    }

    private func scan() {
        model.scan(cli: cli, preview: app.effectivePreview)
    }

    private func editPaths() {
        model.isEditingPaths = true
    }
}
