import SwiftUI

/// Shown when no copy of the CLI can be found.
struct MissingCLIView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ToolIntro(
            symbol: "terminal",
            title: "Burrow Needs the Mole CLI",
            message: "Burrow is a window onto the free, open-source Mole command-line tool. Install it, then check again.",
            errorMessage: model.cliChoiceError
        ) {
            Text("brew install mole")
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Space.cluster)
                .padding(.vertical, Theme.Space.snug)
                .background(.fill.quaternary, in: .rect(cornerRadius: Theme.Radius.inset))
            HStack {
                Button("Choose CLI…", action: choose)
                Button("Check Again", action: checkAgain)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func choose() {
        guard let path = FilePicker.chooseFile(prompt: "Use This CLI") else { return }
        Task { await model.useCustomCLI(path: path) }
    }

    private func checkAgain() {
        Task { await model.locateCLI() }
    }
}
