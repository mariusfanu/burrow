import Foundation
import Testing
import BurrowCore
@testable import Burrow

@MainActor
struct ExternalVolumeConfirmationTests {
    private func model(previewPolicy: Bool = false) -> CleanModel {
        CleanModel(policy: ExecutionPolicy(defaults: nil, forced: previewPolicy), home: "/nonexistent")
    }

    @Test func aRealCleanupWaitsForConfirmation() {
        let clean = model()
        clean.isChoosingVolume = true
        clean.requestExternalClean(path: "/Volumes/Disk", cli: fixtureCLI, preview: false)
        #expect(clean.state == .idle)
        #expect(clean.run.phase == .idle)
        #expect(clean.isChoosingVolume)
        #expect(clean.volumeAwaitingConfirmation == "/Volumes/Disk")

        clean.confirmExternalClean(cli: fixtureCLI)
        #expect(clean.state == .running)
        #expect(clean.run.commandLine == "mo clean --external /Volumes/Disk")
        #expect(!clean.isChoosingVolume)
        #expect(clean.volumeAwaitingConfirmation == nil)
        clean.finishRun()
    }

    @Test func decliningStartsNothing() {
        let clean = model()
        clean.requestExternalClean(path: "/Volumes/Disk", cli: fixtureCLI, preview: false)
        clean.volumeAwaitingConfirmation = nil
        clean.confirmExternalClean(cli: fixtureCLI)
        #expect(clean.state == .idle)
        #expect(clean.run.phase == .idle)
    }

    @Test func aPreviewNeedsNoConfirmationAndStaysADryRun() {
        let clean = model(previewPolicy: true)
        clean.isChoosingVolume = true
        clean.requestExternalClean(path: "/Volumes/Disk", cli: fixtureCLI, preview: true)
        #expect(clean.volumeAwaitingConfirmation == nil)
        #expect(!clean.isChoosingVolume)
        #expect(clean.state == .running)
        #expect(clean.run.isPreview)
        clean.finishRun()
    }
}

/// Stands in for `mo uninstall`: prints a fixed plan, asks, and records whether it was answered.
@MainActor
struct UninstallPlanGuardTests {
    private let listJSON = """
    [{"name":"Xcode","path":"/Applications/Xcode.app","uninstall_name":"Xcode"},
     {"name":"Xcode","path":"/Applications/Xcode-beta.app","uninstall_name":"Xcode"}]
    """

    private func fakeCLI(planning path: String) throws -> (CLIInfo, String) {
        try makeScript("""
        #!/bin/bash
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        printf 'Files to be removed:\\n◎ Xcode , 1GB\\n  ✓ \(path) , 1GB\\n\\n'
        printf 'Remove 1 app, 1GB  Enter confirm, ESC cancel: '
        IFS= read -r -s -n1 key
        [[ -z "$key" ]] && : > "$(dirname "$0")/removed"
        """)
    }

    private func loaded(cli: CLIInfo) async throws -> UninstallModel {
        let commands = ScriptedCommands()
        let model = UninstallModel(
            policy: .live,
            commands: commands.client,
            sizeClient: AppSizeClient(measure: { _ in 1 }),
            home: "/nonexistent"
        )
        model.load(cli: cli)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: listJSON)
        try await eventually { model.state == .list && !model.isMeasuring }
        return model
    }

    @Test func aPlanForTheChosenCopyReachesTheQuestion() async throws {
        let (cli, directory) = try fakeCLI(planning: "/Applications/Xcode-beta.app")
        let model = try await loaded(cli: cli)
        model.selection = ["/Applications/Xcode-beta.app"]
        model.beginRemoval(cli: cli, preview: false)
        try await eventually { model.run.promptRequest != nil }
        let arguments = try String(contentsOfFile: directory + "/args", encoding: .utf8)
        #expect(arguments.split(separator: "\n") == ["uninstall", "Xcode-beta"])
        model.run.cancel()
    }

    @Test func aStoppedAttemptDoesntPassItsOptionsToTheNextRemoval() async throws {
        let (cli, directory) = try fakeCLI(planning: "/Applications/Xcode.app")
        let model = try await loaded(cli: cli)
        model.selection = ["/Applications/Xcode-beta.app"]
        model.deletePermanently = true
        model.includePersonalData = true
        model.beginRemoval(cli: cli, preview: false)
        #expect(model.run.isIrreversible)
        #expect(model.run.consequence?.contains("can’t be restored") == true)
        #expect(model.run.consequence?.contains("Personal data") == true)
        try await eventually { model.state == .idle }
        let arguments = try String(contentsOfFile: directory + "/args", encoding: .utf8)
        #expect(arguments.contains("--permanent"))

        #expect(!model.deletePermanently)
        #expect(!model.includePersonalData)
        #expect(model.activeOptionsNotice == nil)
        model.selection = ["/Applications/Xcode-beta.app"]
        model.beginRemoval(cli: cli, preview: false)
        #expect(!model.run.isIrreversible)
        #expect(model.run.consequence?.contains("to the Trash") == true)
        try await eventually { model.state == .idle }
        let next = try String(contentsOfFile: directory + "/args", encoding: .utf8)
        #expect(!next.contains("--permanent"))
        #expect(!next.contains("--with-data"))
    }

    @Test func aPlanForTheOtherCopyStopsBeforeTheQuestion() async throws {
        let (cli, directory) = try fakeCLI(planning: "/Applications/Xcode.app")
        let model = try await loaded(cli: cli)
        model.selection = ["/Applications/Xcode-beta.app"]
        model.beginRemoval(cli: cli, preview: false)
        try await eventually { model.state == .idle }
        #expect(model.run.promptRequest == nil)
        #expect(model.errorMessage?.contains("nothing was removed") == true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!FileManager.default.fileExists(atPath: directory + "/removed"))
    }
}
