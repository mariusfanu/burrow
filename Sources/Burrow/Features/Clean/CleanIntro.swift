import BurrowCore
import SwiftUI

struct CleanIntro: View {
    let model: CleanModel
    let cli: CLIInfo

    var body: some View {
        ToolIntro(
            symbol: "sparkles",
            title: "See What Can Go",
            message: "Burrow previews first. Nothing is removed until you’ve reviewed the results and chosen to clean.",
            errorMessage: model.errorMessage
        ) {
            HStack {
                Button("Clean External Volume…", action: chooseVolume)
                    .controlSize(.large)
                Button("Scan This Mac", action: scan)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func scan() {
        model.scan(cli: cli)
    }

    private func chooseVolume() {
        model.isChoosingVolume = true
    }
}
