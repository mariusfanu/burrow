import AppKit
import BurrowCore
import SwiftUI

/// The command's real terminal. Keystrokes go straight to the running program, so any
/// interactive screen the CLI offers stays reachable from the app.
struct TerminalPanel: NSViewRepresentable {
    let terminal: CLITerminal
    let revision: Int

    func makeNSView(context: Context) -> TerminalCanvas {
        let view = TerminalCanvas()
        view.terminal = terminal
        return view
    }

    func updateNSView(_ view: TerminalCanvas, context: Context) {
        view.terminal = terminal
        view.needsDisplay = true
    }
}
