import BurrowCore
import SwiftUI

/// Edits the folders `mo purge` scans.
struct PurgePathsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var paths: [String] = []
    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var loadFailed = false

    private let store = PurgePathsStore(home: AppModel.home)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.card) {
            Text("Scan Locations")
                .font(.title3)
                .bold()
            Text("With no folders listed here, Mole looks in common project locations such as ~/Developer and ~/Projects.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(paths, id: \.self, selection: $selection) { path in
                Text(path)
                    .font(.callout.monospaced())
            }
            .frame(height: 180)
            HStack {
                Button("Add Folder…", action: addFolder)
                Button("Remove", action: removeSelected)
                    .disabled(selection == nil)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loadFailed || app.effectivePreview)
                    .help(app.effectivePreview ? "Turn off Preview Mode to change these" : "Save these locations")
            }
            if let errorMessage {
                InlineNotice(text: errorMessage, tint: .red)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            paths = try store.load()
        } catch {
            loadFailed = true
            errorMessage = "The current list couldn’t be read, so it can’t be edited here: \(error.localizedDescription)"
        }
    }

    private func addFolder() {
        if let path = FilePicker.chooseFolder(prompt: "Add"), !paths.contains(path.abbreviatingHome) {
            paths.append(path.abbreviatingHome)
        }
    }

    private func removeSelected() {
        paths.removeAll { $0 == selection }
        selection = nil
    }

    private func save() {
        guard !loadFailed, !app.effectivePreview else { return }
        do {
            try store.save(paths)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
