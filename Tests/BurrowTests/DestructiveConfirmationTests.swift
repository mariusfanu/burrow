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
        #expect(clean.isConfirmingExternalClean)
        clean.isConfirmingExternalClean = false
        #expect(clean.volumeAwaitingConfirmation == nil)
        clean.isConfirmingExternalClean = true
        #expect(clean.volumeAwaitingConfirmation == nil)
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

    private func fakeCLI(planning path: String, question: String = "Remove 1 app, 1GB  Enter confirm, ESC cancel: ") throws -> (CLIInfo, String) {
        try makeScript("""
        #!/bin/bash
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        printf '%s' "$MOLE_DELETE_MODE" > "$(dirname "$0")/delete-mode"
        printf 'Files to be removed:\\n◎ Xcode , 1GB\\n  ✓ \(path) , 1GB\\n\\n'
        printf '%s' '\(question)'
        if IFS= read -r -s -n1 key && [[ -z "$key" || "$key" == y ]]; then
            : > "$(dirname "$0")/removed"
        fi
        """)
    }

    @Test(arguments: [false, true]) func unexpectedInputCannotApproveRemoval(alternatePrompt: Bool) async throws {
        let (cli, directory) = try fakeCLI(
            planning: "/Applications/Xcode.app",
            question: alternatePrompt ? "Remove 1 app [y/N]: " : "Remove 1 app, 1GB  Enter confirm, ESC cancel: "
        )
        let model = try await loaded(cli: cli)
        defer { model.run.reset() }
        model.selection = ["/Applications/Xcode-beta.app"]
        model.beginRemoval(cli: cli, preview: false)
        if alternatePrompt {
            try await eventually { model.run.promptRequest != nil || model.state == .idle }
            if model.run.promptRequest != nil { model.run.answerYesNo(true) }
        } else {
            try await eventually { model.run.terminal?.partial.contains("Enter confirm") == true }
            model.run.send("\r")
        }
        try await eventually { model.state == .idle || !model.run.isRunning }
        #expect(model.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: directory + "/removed"))
    }

    private func loaded(cli: CLIInfo, commands: ScriptedCommands = ScriptedCommands()) async throws -> UninstallModel {
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
        #expect(try String(contentsOfFile: directory + "/delete-mode", encoding: .utf8) == "trash")
        let request = try #require(model.run.promptRequest)
        model.run.answerConfirm(requestID: UUID())
        #expect(model.run.promptRequest == request)
        model.run.answerConfirm(requestID: request.id)
        try await eventually { !model.run.isRunning }
        #expect(FileManager.default.fileExists(atPath: directory + "/removed"))
    }

    @Test func aStoppedAttemptDoesntPassItsOptionsToTheNextRemoval() async throws {
        let (cli, directory) = try fakeCLI(planning: "/Applications/Xcode.app")
        let commands = ScriptedCommands()
        let model = try await loaded(cli: cli, commands: commands)
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
        model.load(cli: cli)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: listJSON)
        try await eventually { model.state == .list }
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
