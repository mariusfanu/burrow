import BurrowCore
import SwiftUI

/// App-level setup, in the standard Settings window.
struct SettingsView: View {
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                GeneralSettings()
            }
            Tab("Protected", systemImage: "lock.shield", value: SettingsPane.protected) {
                ProtectedSettings()
            }
            Tab("Maintenance", systemImage: "wrench.and.screwdriver", value: SettingsPane.maintenance) {
                MaintenanceSettings()
            }
            Tab("Mole CLI", systemImage: "terminal", value: SettingsPane.mole) {
                MoleSettings()
            }
            Tab("About", systemImage: "info.circle", value: SettingsPane.about) {
                ScrollView {
                    AboutView()
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 560, height: 500)
    }
}

enum SettingsPane: String {
    case general, protected, maintenance, mole, about
}

private struct GeneralSettings: View {
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

/// The paths cleanup must leave alone.
private struct ProtectedSettings: View {
    @Environment(AppModel.self) private var app
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
                    .transition(Motion.rise)
            }
            .animation(Motion.settle, value: model.patterns)
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
            }
            .disabled(!canEdit)
        }
        .padding(Theme.Space.page)
        .animation(Motion.settle, value: model.errorMessage)
        .onAppear { model.load(from: store) }
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

/// Which maintenance tasks Optimize runs.
private struct MaintenanceSettings: View {
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

/// Setting up, updating and removing the CLI.
private struct MoleSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var manage = app.manage
        Form {
            Section {
                LabeledContent("Status", value: manage.touchIDStatus.isEmpty ? "Checking…" : manage.touchIDStatus)
                HStack {
                    Button("Turn On") { run("Turning On Touch ID", previewable(["touchid", "enable"])) }
                        .disabled(manage.touchIDEnabled == true)
                    Button("Turn Off") { run("Turning Off Touch ID", previewable(["touchid", "disable"])) }
                        .disabled(manage.touchIDEnabled == false)
                }
            } header: {
                Text("Touch ID for sudo")
            } footer: {
                Text("Approve Mole’s administrator steps, and any other sudo command, with your fingerprint.")
            }
            Section {
                HStack {
                    Button("Preview") { run("Previewing Shell Completion", ["completion", "--dry-run"]) }
                    Button("Set Up") { run("Setting Up Shell Completion", previewable(["completion"])) }
                }
            } header: {
                Text("Shell Completion")
            } footer: {
                Text("Adds tab completion for mo and mole to your shell’s configuration.")
            }
            Section {
                HStack {
                    Button("Main Menu") { run("Mole", [], showsTerminal: true) }
                    Button("Clean List") { run("Protected Caches", ["clean", "--whitelist"], showsTerminal: true) }
                    Button("Optimize List") { run("Protected Tasks", ["optimize", "--whitelist"], showsTerminal: true) }
                }
                .disabled(app.effectivePreview)
            } header: {
                Text("Terminal Screens")
            } footer: {
                Text(app.effectivePreview
                    ? "These can change things, so they’re off in Preview Mode."
                    : "Open the CLI’s own screens for anything you’d rather do there.")
            }
            Section {
                HStack {
                    Button("Update") { run("Updating Mole", ["update"]) }
                    Button("Reinstall Latest Release") { run("Reinstalling Mole", ["update", "--force"]) }
                    Button("Install Nightly Build") { run("Installing the Nightly Build", ["update", "--nightly"]) }
                }
                .disabled(app.effectivePreview)
            } header: {
                Text("Update")
            } footer: {
                Text("Updates the CLI, not Burrow, which was last checked with Mole \(CLICompatibility.checkedVersion). Reopen Burrow afterward so that it finds the new version.")
            }
            Section {
                HStack {
                    Button("Preview") { run("Previewing Removal", ["remove", "--dry-run"]) }
                    Button("Remove Mole…", role: .destructive) { manage.isConfirmingRemove = true }
                        .disabled(app.effectivePreview)
                }
            } header: {
                Text("Remove")
            } footer: {
                Text("Removes the CLI and its caches, and keeps its operation logs. Burrow needs the CLI to work.")
            }
        }
        .formStyle(.grouped)
        .task(refresh)
        .sheet(isPresented: $manage.isRunPresented) {
            RunPanel(run: manage.run, isSheet: true, close: closeRun)
                .frame(width: 560, height: 460)
                .interactiveDismissDisabled()
        }
        .alert("Remove the Mole CLI from This Mac?", isPresented: $manage.isConfirmingRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { run("Removing Mole", ["remove"]) }
        } message: {
            Text("You’ll see what will be removed, and you can still cancel.")
        }
    }

    @Sendable
    private func refresh() async {
        if let cli = app.cli { app.manage.refresh(cli: cli) }
    }

    private func closeRun() {
        if let cli = app.cli { app.manage.closeRun(cli: cli) }
    }

    private func run(_ title: String, _ arguments: [String], showsTerminal: Bool = false) {
        guard let cli = app.cli else { return }
        app.manage.perform(title: title, arguments: arguments, cli: cli, showsTerminal: showsTerminal)
    }

    private func previewable(_ arguments: [String]) -> [String] {
        app.effectivePreview ? arguments + ["--dry-run"] : arguments
    }
}
