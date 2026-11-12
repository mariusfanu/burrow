import AppKit
import BurrowCore
import SwiftUI

/// The command's real terminal. Keystrokes go straight to the running program, so any
/// interactive screen the CLI offers stays reachable from the app.
struct TerminalPanel: NSViewRepresentable {
    let terminal: CLITerminal
    let revision: Int
    let run: RunController

    func makeNSView(context: Context) -> TerminalCanvas {
        let view = TerminalCanvas()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: TerminalCanvas, context: Context) {
        view.terminal = terminal
        if run.allowsTerminalInput {
            view.sendInput = { [weak run, weak terminal] text in
                guard let run, let terminal, run.terminal === terminal else { return }
                run.send(text)
            }
        } else {
            view.sendInput = nil
        }
        view.needsDisplay = true
    }
}
