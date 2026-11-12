import BurrowCore
import SwiftUI

/// Setting up, updating and removing the CLI.
struct MoleSettings: View {
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
