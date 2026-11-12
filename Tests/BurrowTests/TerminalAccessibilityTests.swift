import AppKit
import BurrowCore
import Testing
@testable import Burrow

@MainActor
struct TerminalAccessibilityTests {
    @Test func visibleOutputCanBeReadSelectedAndCopiedWithoutRecordingHiddenInput() async throws {
        let terminal = try CLITerminal(
            executable: "/bin/sh",
            arguments: ["-c", "stty -echo; printf 'Ready for input:'; read line; printf '\\r\\nFinished\\r\\n'"],
            environment: CLILocator.environment()
        )
        defer { if terminal.isRunning { terminal.cancel() } }
        try await eventually { terminal.screen.lines.contains { $0.contains("Ready for input:") } && terminal.isEchoOff }
        let view = TerminalCanvas()
        view.terminal = terminal
        #expect(view.accessibilityRole() == .textArea)
        #expect((view.accessibilityValue() as? String)?.contains("Ready for input:") == true)
        terminal.send("unrecorded-test-input\r")
        _ = await terminal.waitForExit()
        try await eventually { !terminal.isRunning }
        view.refreshDiagnostics()
        #expect(view.diagnosticText.contains("Finished"))
        #expect(!view.diagnosticText.contains("unrecorded-test-input"))
        view.selectAll(nil)
        #expect(view.accessibilitySelectedText() == view.diagnosticText)
        #expect(view.accessibilitySelectedTextRange().length == view.diagnosticText.utf16.count)
        var copied: String?
        view.copyVisibleOutput { copied = $0 }
        #expect(copied == view.diagnosticText)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["BURROW_RUN_GUI_TESTS"] == "1",
                   "Set BURROW_RUN_GUI_TESTS=1 in a desktop session to test the system pasteboard"))
    func terminalOutputCanRoundTripThroughThePasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        TerminalCanvas.writeToPasteboard("Terminal output", pasteboard: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Terminal output")
    }
}
