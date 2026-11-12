import BurrowCore
import SwiftUI

/// Which maintenance tasks Optimize runs.
struct MaintenanceSettings: View {
    @Environment(AppModel.self) private var app
    @State private var model = MaintenanceSettingsModel()

    private var store: OptimizeWhitelistStore { OptimizeWhitelistStore(home: AppModel.home, cliRoot: app.cli?.root) }

    var body: some View {
        Form {
            if let errorMessage = model.errorMessage {
                InlineNotice(text: errorMessage, tint: .red)
            }
            Section {
                ForEach(model.tasks) { task in
                    Toggle(task.name, isOn: binding(for: task))
                        .disabled(!model.isLoaded || app.effectivePreview)
                }
            } header: {
                Text("Maintenance Tasks")
            } footer: {
                Text(app.effectivePreview
                    ? "This list affects later real runs, so it’s read-only in Preview Mode."
                    : "Optimize skips any task you turn off.")
            }
        }
        .formStyle(.grouped)
        .overlay {
            if model.tasks.isEmpty {
                ContentUnavailableView("No Task List", systemImage: "wrench.and.screwdriver", description: Text("This version of the CLI doesn’t list its maintenance tasks."))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        model.load(tasks: store.availableTasks(), read: store.load)
    }

    private func binding(for task: OptimizeWhitelistStore.Task) -> Binding<Bool> {
        Binding {
            model.isEnabled(task.action)
        } set: { isOn in
            guard !app.effectivePreview else { return }
            model.setEnabled(isOn, action: task.action, save: store.save)
        }
    }
}
