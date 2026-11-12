import BurrowCore
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("Preview Mode", isOn: $app.previewMode)
                    .disabled(!app.isPreviewToggleEnabled)
                    .help(app.previewToggleHelp)
            } footer: {
                Text("When this is on, actions show what would change instead of changing it. Anything that can’t be previewed is turned off.")
            }
            if let cli = app.cli {
                Section("Mole CLI") {
                    LabeledContent("Version", value: cli.version)
                    LabeledContent("Installed With", value: cli.installMethod)
                    LabeledContent("Location") {
                        Text(cli.executable)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !cli.hasBundledTools {
                        InlineNotice(text: "This copy is missing its status and analyze tools, so those pages won’t work.")
                    }
                    if let warning = CLICompatibility(version: cli.version).warning(version: cli.version) {
                        InlineNotice(text: warning)
                    }
                    if let error = app.cliChoiceError {
                        InlineNotice(text: error, tint: .red)
                    }
                    Button("Choose Another CLI…", action: chooseCLI)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseCLI() {
        guard let path = FilePicker.chooseFile(prompt: "Use This CLI") else { return }
        Task { await app.useCustomCLI(path: path) }
    }
}
