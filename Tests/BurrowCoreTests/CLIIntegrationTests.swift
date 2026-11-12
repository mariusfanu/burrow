import Foundation
import Testing
@testable import BurrowCore

/// Exercises terminal interactions with fixtures and, when enabled, the installed CLI.
@MainActor
// A prompt a newer CLI words differently would otherwise wait forever.
@Suite(.serialized, .timeLimit(.minutes(5))) struct CLIIntegrationTests {
    private struct Sandbox {
        let root: String
        let home: String
        let environment: [String: String]
        let cli: CLIInfo
    }

    /// Real CLI tests use a throwaway HOME and MOLE_TEST_NO_AUTH. MOLE_TEST_MODE is
    /// left unset because it makes scripts such as bin/installer.sh load without running.
    private func makeSandbox(files: [String]) async throws -> Sandbox {
        let cli = try #require(await CLILocator.locate(customPath: nil), "The Mole CLI must be installed to run these tests")
        let root = "/tmp/burrow-test-" + UUID().uuidString
        let home = root + "/home"
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: home + "/Downloads", withIntermediateDirectories: true)
        for file in files {
            try Data(repeating: 0x41, count: 2_000_000).write(to: URL(fileURLWithPath: home + "/Downloads/" + file))
        }
        var environment = CLILocator.environment()
        environment["HOME"] = home
        environment["MOLE_TEST_NO_AUTH"] = "1"
        return Sandbox(root: root, home: home, environment: environment, cli: cli)
    }

    /// `mo installer` deletes permanently as of 1.69.0. If a later version uses trash(8),
    /// which resolves the real user's Trash, this removes the one uniquely named file the
    /// test put there. It never touches anything else in the Trash.
    private func removeTestFileFromTrash(named name: String) {
        let trash = NSHomeDirectory() + "/.Trash/" + name
        guard name.hasPrefix("burrowtest"), FileManager.default.fileExists(atPath: trash) else { return }
        try? FileManager.default.removeItem(atPath: trash)
    }

    private func waitForPrompt(_ terminal: CLITerminal, timeout: TimeInterval = 60) async throws -> CLIPrompt? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let prompt = PromptDetector.detect(partial: terminal.partial) { return prompt }
            if !terminal.isRunning { return nil }
            try await Task.sleep(for: .milliseconds(30))
        }
        return nil
    }

    /// Starts the real CLI inside the sandbox and waits for its menu.
    private func menu(_ arguments: [String], in sandbox: Sandbox, rows: Int, columns: Int) async throws -> (CLITerminal, MenuDriver) {
        let terminal = try CLITerminal(
            executable: sandbox.cli.executable,
            arguments: arguments,
            environment: sandbox.environment,
            rows: rows,
            columns: columns
        )
        let driver = MenuDriver(terminal: terminal)
        _ = try #require(try await driver.waitForMenu(timeout: 120), "\(arguments.joined(separator: " ")) menu did not appear")
        return (terminal, driver)
    }

    /// A stand-in for a command, for the tests that don't run the real CLI.
    private func makeScript(_ body: String) throws -> (path: String, directory: String) {
        let directory = TestScratch.root + "burrow-script-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/script.sh"
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return (path, directory)
    }

    @Test(.hostIntegration) func installerMenuRemovesOnlyTheVerifiedSelection() async throws {
        let doomed = "burrowtest\(UUID().uuidString.prefix(6)).dmg"
        defer { removeTestFileFromTrash(named: doomed) }
        let sandbox = try await makeSandbox(files: ["keep-a.dmg", doomed, "keep-b.pkg"])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let downloads = sandbox.home + "/Downloads/"
        let (terminal, driver) = try await menu(["installer"], in: sandbox, rows: 200, columns: 220)

        let items = try await driver.readItems()
        let target = try #require(items.first { $0.name == doomed })
        #expect(items.count == 3)

        try await driver.select([target])
        #expect(driver.snapshot?.reportedSelectedCount == 1)
        try driver.confirm()

        // The CLI's own final question comes back to the caller, which relays it to the user.
        if let prompt = try await waitForPrompt(terminal), case .confirm = prompt {
            terminal.send("\r")
        }
        _ = await terminal.waitForExit()

        let fileManager = FileManager.default
        #expect(!fileManager.fileExists(atPath: downloads + doomed))
        #expect(fileManager.fileExists(atPath: downloads + "keep-a.dmg"))
        #expect(fileManager.fileExists(atPath: downloads + "keep-b.pkg"))
    }

    @Test(.hostIntegration) func quittingTheMenuChangesNothing() async throws {
        let sandbox = try await makeSandbox(files: ["a.dmg", "b.dmg"])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let (terminal, driver) = try await menu(["installer"], in: sandbox, rows: 200, columns: 180)
        driver.quit()
        _ = await terminal.waitForExit()

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: sandbox.home + "/Downloads/a.dmg"))
        #expect(fileManager.fileExists(atPath: sandbox.home + "/Downloads/b.dmg"))
    }

    @Test(.hostIntegration) func driverRefusesARowThatChangedUnderIt() async throws {
        let sandbox = try await makeSandbox(files: ["a.dmg", "b.dmg"])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let (terminal, driver) = try await menu(["installer"], in: sandbox, rows: 200, columns: 180)
        let items = try await driver.readItems()
        let real = try #require(items.last)

        // A stale pick: right index, different row text.
        let stale = MenuItem(
            index: real.index,
            rowText: "something-else.dmg   1.0MB | Downloads",
            name: "something-else.dmg",
            sizeText: "1.0MB",
            bytes: 1_000_000,
            tag: nil,
            age: nil,
            path: nil,
            preselected: false
        )
        await #expect(throws: MenuDriverError.self) {
            try await driver.select([stale])
        }
        driver.quit()
        _ = await terminal.waitForExit()
        #expect(FileManager.default.fileExists(atPath: sandbox.home + "/Downloads/a.dmg"))
        #expect(FileManager.default.fileExists(atPath: sandbox.home + "/Downloads/b.dmg"))
    }

    @Test(.hostIntegration) func purgeRowsReadTheirOwnPaths() async throws {
        let sandbox = try await makeSandbox(files: [])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let fileManager = FileManager.default
        let projects = ["alpha", "beta", "gamma"]
        for project in projects {
            let root = sandbox.home + "/Projects/" + project
            for artifact in ["node_modules", "dist"] {
                try fileManager.createDirectory(atPath: root + "/" + artifact, withIntermediateDirectories: true)
                try Data(repeating: 0x42, count: 1_000_000).write(to: URL(fileURLWithPath: root + "/" + artifact + "/data.bin"))
            }
            try Data("{}".utf8).write(to: URL(fileURLWithPath: root + "/package.json"))
        }

        let (terminal, driver) = try await menu(["purge", "--dry-run"], in: sandbox, rows: 400, columns: 220)
        let items = try await driver.readItems()
        driver.quit()
        _ = await terminal.waitForExit()

        #expect(items.count >= 3)
        for item in items {
            let path = try #require(item.path, "\(item.rowText) has no confirmed path")
            #expect(path.hasPrefix(item.name + "/"))
            #expect(path.hasSuffix("/" + (item.tag ?? "")))
        }
        #expect(Set(items.compactMap(\.path)).count == items.count)
    }

    @Test(.hostIntegration) func aSelectionPastTheFirstPageReachesTheRightFile() async throws {
        // Keep names below Mole's display truncation limit while retaining a unique namespace.
        let prefix = "burrowtest\(UUID().uuidString.prefix(12))p"
        let names = (0..<60).map { prefix + String(format: "%02d.dmg", $0) }
        let sandbox = try await makeSandbox(files: names)
        defer {
            for name in names { removeTestFileFromTrash(named: name) }
            try? FileManager.default.removeItem(atPath: sandbox.root)
        }
        let (terminal, driver) = try await menu(["installer"], in: sandbox, rows: 400, columns: 220)
        #expect(driver.snapshot?.rows.count == 50)
        #expect((driver.snapshot?.reportedTotal ?? 0) >= 60)

        let items = try await driver.readItems()
        #expect(items.filter { names.contains($0.name) }.count == 60)
        let target = try #require(items.first { $0.name == names[55] })
        try #require(target.index >= 50)
        try await driver.select([target])
        #expect(driver.snapshot?.reportedSelectedCount == 1)
        try driver.confirm()
        if let prompt = try await waitForPrompt(terminal), case .confirm = prompt {
            terminal.send("\r")
        }
        _ = await terminal.waitForExit()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: sandbox.home + "/Downloads")
        #expect(remaining.count == 59)
        #expect(!remaining.contains(target.name))
    }

    /// A stand-in menu with a preselected row on a later page, like old purge artifacts.
    private func fakeMenu(lieAboutCount: Bool = false) async throws -> (CLITerminal, String) {
        let lie = lieAboutCount ? "1" : "0"
        let (script, directory) = try makeScript(#"""
        #!/bin/bash
        selected=(0 0 0 0 1); cursor=0; page=3; top=0
        stty -echo -icanon
        draw() {
          printf '\033[H\033[2J'
          local count=0; for s in "${selected[@]}"; do count=$((count+s)); done
          [[ \#(lie) == 1 ]] && count=$((count+1))
          printf 'Select Things [%d/5], %d selected\r\n\r\n' "$((cursor+1))" "$count"
          local i
          for ((i=top; i<top+page; i++)); do
            local mark='○'; [[ ${selected[i]} == 1 ]] && mark='●'
            if [[ $i == "$cursor" ]]; then printf '➤ %s row%d   1.0MB\r\n' "$mark" "$i"
            else printf '  %s row%d   1.0MB\r\n' "$mark" "$i"; fi
          done
          printf '\r\n↑↓ | Space Select | Enter Confirm | Q Quit\r\n'
        }
        while true; do
          draw
          IFS= read -rsn1 key
          if [[ $key == $'\033' ]]; then
            read -rsn2 rest
            [[ $rest == '[B' && $cursor -lt 4 ]] && cursor=$((cursor+1))
            [[ $rest == '[A' && $cursor -gt 0 ]] && cursor=$((cursor-1))
            ((cursor < top)) && top=$cursor
            ((cursor >= top+page)) && top=$((cursor-page+1))
          elif [[ $key == ' ' ]]; then
            selected[cursor]=$((1-selected[cursor]))
          elif [[ $key == f ]]; then
            selected=(1 0 0 0 0)
            printf 'Fixture swapped marks\r\n'
          elif [[ $key == '' ]]; then
            printf 'CHOSEN:%s\r\n' "${selected[*]}" > "$(dirname "$0")/result"
            exit 0
          elif [[ $key == q ]]; then
            exit 2
          fi
        done
        """#)
        let terminal = try CLITerminal(
            executable: script,
            arguments: [],
            environment: CLILocator.environment(),
            rows: 400,
            columns: 120
        )
        return (terminal, directory)
    }

    @Test func aPreselectedRowOnAnotherPageIsCleared() async throws {
        let (terminal, directory) = try await fakeMenu()
        let driver = MenuDriver(terminal: terminal)
        _ = try #require(try await driver.waitForMenu(timeout: 20))

        let items = try await driver.readItems()
        #expect(items.count == 5)
        #expect(items.filter(\.preselected).map(\.index) == [4])

        try await driver.select([items[1]])
        try driver.confirm()
        _ = await terminal.waitForExit()

        let result = try String(contentsOfFile: directory + "/result", encoding: .utf8)
        #expect(result.contains("CHOSEN:0 1 0 0 0"))
    }

    @Test func aSameCountSelectionSwapStopsBeforeEnter() async throws {
        let (terminal, directory) = try await fakeMenu()
        defer { terminal.cancel() }
        let driver = MenuDriver(terminal: terminal)
        _ = try #require(try await driver.waitForMenu(timeout: 20))
        let items = try await driver.readItems()
        terminal.send("f")
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while driver.snapshot?.cursor?.isSelected != true, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(driver.snapshot?.cursor?.isSelected == true)
        await #expect(throws: MenuDriverError.self) { try await driver.select([items[4]]) }
        driver.quit()
        _ = await terminal.waitForExit()
        #expect(!FileManager.default.fileExists(atPath: directory + "/result"))
    }

    @Test func aCountThatDoesNotAddUpStopsBeforeEnter() async throws {
        let (terminal, directory) = try await fakeMenu(lieAboutCount: true)
        let driver = MenuDriver(terminal: terminal)
        _ = try #require(try await driver.waitForMenu(timeout: 20))

        await #expect(throws: MenuDriverError.self) {
            _ = try await driver.readItems()
        }
        driver.quit()
        _ = await terminal.waitForExit()
        #expect(!FileManager.default.fileExists(atPath: directory + "/result"))
    }

    @Test func cancellingAnUnconfirmedFocusedPathStopsTheRead() async throws {
        let (script, directory) = try makeScript(#"""
        #!/bin/bash
        stty -echo -icanon
        printf 'Select Artifacts, 0 selected\r\n'
        printf '➤ ○ ~/project   1.0MB | .build\r\n'
        printf 'Path: ~/previous/.build\r\n'
        printf '↑↓ | Space Select | Enter Confirm | Q Quit\r\n'
        while IFS= read -rsn1 key; do
          if [[ $key == q ]]; then exit 0; fi
          printf '%s' "$key" >> "$(dirname "$0")/input"
        done
        """#)
        let terminal = try CLITerminal(executable: script, arguments: [], environment: CLILocator.environment())
        defer { terminal.cancel() }
        let driver = MenuDriver(terminal: terminal)
        _ = try #require(try await driver.waitForMenu(timeout: 20))

        let read = Task { try await driver.readItems() }
        defer { read.cancel() }
        // The initial 40 ms settle completes before the unconfirmed path's 1.5 s wait.
        try await Task.sleep(for: .milliseconds(250))
        let cancellationStart = ContinuousClock.now
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        #expect(cancellationStart.duration(to: .now) < .seconds(1))

        driver.quit()
        #expect(await terminal.waitForExit() == 0)
        #expect(!FileManager.default.fileExists(atPath: directory + "/input"))
    }

    @Test func echoStateIsVisibleToThePasswordCheck() async throws {
        let (script, _) = try makeScript("#!/bin/bash\nprintf 'Password:'\nsleep 1\nstty -echo\nsleep 5\n")

        let terminal = try CLITerminal(executable: script, arguments: [], environment: CLILocator.environment())
        try await Task.sleep(for: .milliseconds(300))
        #expect(!terminal.isEchoOff)
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(terminal.isEchoOff)
        terminal.cancel()
        _ = await terminal.waitForExit()
    }

    @Test(.hostIntegration) func historyAndStatusDecodeFromTheRealCLI() async throws {
        let sandbox = try await makeSandbox(files: [])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let history = try await CommandRunner.run(
            executable: sandbox.cli.executable,
            arguments: ["history", "--json", "--limit", "5"],
            environment: sandbox.environment,
            timeout: 30
        )
        #expect(history.succeeded)
        _ = try HistoryReport.decode(Data(history.stdout.utf8))

        let status = try await CommandRunner.run(
            executable: sandbox.cli.executable,
            arguments: ["status", "--json"],
            environment: sandbox.environment,
            timeout: 40
        )
        #expect(status.succeeded)
        let snapshot = try StatusSnapshot.decode(Data(status.stdout.utf8))
        #expect(snapshot.healthScore != nil)
        #expect(snapshot.cpu != nil)
    }

    @Test(.hostIntegration) func analyzeDecodesFromTheRealCLI() async throws {
        let sandbox = try await makeSandbox(files: ["x.dmg"])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let result = try await CommandRunner.run(
            executable: sandbox.cli.executable,
            arguments: ["analyze", "--json", sandbox.home + "/Downloads"],
            environment: sandbox.environment,
            timeout: 60
        )
        #expect(result.succeeded)
        let parsed = try AnalyzeResult.decode(Data(result.stdout.utf8))
        #expect(parsed.entries?.contains { $0.name == "x.dmg" } == true)
    }

    /// Mole matches apps by name, so two copies sharing one must still be told apart.
    @Test(.hostIntegration) func uninstallTargetsTheChosenCopyOfASharedName() async throws {
        let sandbox = try await makeSandbox(files: [])
        defer { try? FileManager.default.removeItem(atPath: sandbox.root) }
        let name = "BurrowDup" + UUID().uuidString.prefix(6)
        for folder in [name, name + "-beta"] {
            let contents = sandbox.home + "/Applications/" + folder + ".app/Contents"
            try FileManager.default.createDirectory(atPath: contents + "/MacOS", withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleName": name, "CFBundleDisplayName": name,
                "CFBundleIdentifier": "local.burrow.test." + folder, "CFBundleExecutable": "x",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: contents + "/Info.plist"))
        }
        let list = try await CommandRunner.run(
            executable: sandbox.cli.executable, arguments: ["uninstall", "--list"],
            environment: sandbox.environment, timeout: 120
        )
        let apps = try InstalledApp.decodeList(Data(list.stdout.utf8))
        let copies = apps.filter { $0.name == name }
        try #require(copies.count == 2, "Mole should list both copies under one name")
        let beta = try #require(copies.first { $0.path?.hasSuffix("-beta.app") == true })

        let terms = UninstallTargeting.terms(for: [beta], among: apps)
        #expect(terms == [name + "-beta"])
        // On a terminal, as in the app, so that the plan is read just as the app reads it.
        let terminal = try CLITerminal(
            executable: sandbox.cli.executable,
            arguments: ["uninstall", "--dry-run"] + terms,
            environment: sandbox.environment,
            rows: 60,
            columns: 180
        )
        var lines: [String] = []
        terminal.onLine = { lines.append($0) }
        let prompt = try #require(try await waitForPrompt(terminal), "the CLI didn't ask before removing")
        guard case .confirm = prompt else { throw MenuDriverError.menuClosed }
        #expect(UninstallPlan.appPaths(in: lines, home: sandbox.home) == [try #require(beta.path)])
        // Mole discards input as it asks, so a key sent this early could be lost. This
        // is a dry run with its plan already checked, so stopping it is the simple way out.
        terminal.cancel()
        _ = await terminal.waitForExit()
    }

    @Test func cancellingARunningCommandEndsIt() async throws {
        let terminal = try CLITerminal(
            executable: "/bin/sleep",
            arguments: ["60"],
            environment: CLILocator.environment()
        )
        terminal.cancel()
        let status = await terminal.waitForExit()
        #expect(status != 0)
    }

    @Test func missingExecutableReportsFailure() async throws {
        let terminal = try CLITerminal(
            executable: "/nonexistent/mo",
            arguments: [],
            environment: CLILocator.environment()
        )
        #expect(await terminal.waitForExit() == 127)
    }
}
