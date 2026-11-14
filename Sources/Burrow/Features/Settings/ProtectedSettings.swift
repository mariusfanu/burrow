import BurrowCore
import SwiftUI

/// The paths cleanup must leave alone.
struct ProtectedSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = ProtectedPathsModel()
    @State private var newPattern = ""
    @State private var selection: String?

    private var store: WhitelistStore { WhitelistStore(home: AppModel.home, cliRoot: app.cli?.root) }
    private var canEdit: Bool { model.isLoaded && !app.effectivePreview }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.item) {
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage = model.errorMessage {
                InlineNotice(text: errorMessage, tint: .red) { model.errorMessage = nil }
            }
            List(model.patterns, id: \.self, selection: $selection) { pattern in
                Text(pattern == "FINDER_METADATA" ? "Finder metadata (.DS_Store files)" : pattern.abbreviatingHome)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(pattern)
                    .transition(Motion.rise(reduced: reduceMotion))
            }
            .animation(Motion.settle(reduced: reduceMotion), value: model.patterns)
            .onDeleteCommand(perform: removeSelected)
            .frame(maxHeight: .infinity)
            HStack {
                TextField("Add a path or pattern", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .onSubmit(addTyped)
                Button("Add", action: addTyped)
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Choose…", action: chooseFolder)
                Button("Remove", action: removeSelected)
                    .disabled(selection == nil)
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .disabled(!canEdit)
        }
        .padding(Theme.Space.page)
        .animation(Motion.settle(reduced: reduceMotion), value: model.errorMessage)
        .task(id: app.cli?.root) { model.load(from: store) }
    }

    private var explanation: String {
        if app.effectivePreview { return "These lists affect later real runs, so they’re read-only in Preview Mode." }
        if model.usesDefaults { return "These are Mole’s default protections. Saving a change keeps them unless you remove them." }
        return "Cleanup leaves these alone. Patterns can use * as a wildcard. Mole’s built-in safety rules always apply."
    }

    private func addTyped() {
        if model.addTyped(newPattern, to: store, home: AppModel.home, isPreview: app.effectivePreview) {
            newPattern = ""
        }
    }

    private func chooseFolder() {
        if let path = FilePicker.chooseFolder(prompt: "Protect") {
            model.add(path, to: store, isPreview: app.effectivePreview)
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        if model.remove(selection, from: store, isPreview: app.effectivePreview) {
            self.selection = nil
        }
    }
}
