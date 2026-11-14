import BurrowCore
import SwiftUI

/// Lists mounted external volumes for `mo clean --external`.
struct ExternalVolumeSheet: View {
    @Bindable var model: CleanModel
    let cli: CLIInfo
    let isPreview: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var volumes: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.card) {
            Text("Clean an External Volume")
                .font(.title3)
                .bold()
            Text("Removes macOS metadata such as .DS_Store files and resource forks from the volume you choose.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if volumes.isEmpty {
                InlineNotice(text: "No external volumes are mounted.", symbol: "externaldrive", tint: .secondary)
            } else {
                List(volumes, id: \.self, selection: $selection) { volume in
                    Label(volume.lastPathComponent, systemImage: "externaldrive")
                }
                .frame(height: 140)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isPreview ? "Preview" : "Clean…", action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 440)
        .onAppear { volumes = ExternalVolumes.mounted() }
        .alert(confirmationTitle, isPresented: $model.isConfirmingExternalClean) {
            // Return mustn't be the way something permanent happens.
            Button("Cancel", role: .cancel) { model.cancelExternalClean() }
                .keyboardShortcut(.defaultAction)
            Button("Clean") { model.confirmExternalClean(cli: cli) }
        } message: {
            Text("This removes .DS_Store files, AppleDouble files and temporary items, and it can’t be undone. The volume’s Trash is left alone.")
        }
    }

    private var confirmationTitle: String {
        let name = model.volumeAwaitingConfirmation.map { $0.lastPathComponent } ?? "This Volume"
        return "Clean Metadata from \(name)?"
    }

    private func submit() {
        guard let selection else { return }
        model.requestExternalClean(path: selection, cli: cli, preview: isPreview)
    }
}
