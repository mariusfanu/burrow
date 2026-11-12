import SwiftUI

struct RunTerminalToggle: View {
    @Bindable var run: RunController

    var body: some View {
        Toggle("Terminal", systemImage: "terminal", isOn: $run.isTerminalVisible)
            .disabled(run.terminal == nil)
            .help(run.allowsTerminalInput && run.isRunning
                  ? "Show the live terminal and type an answer"
                  : "Show and copy the command’s terminal output")
    }
}
