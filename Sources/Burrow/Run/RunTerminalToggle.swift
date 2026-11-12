import SwiftUI

struct RunTerminalToggle: View {
    @Bindable var run: RunController

    var body: some View {
        Toggle("Terminal", systemImage: "terminal", isOn: $run.isTerminalVisible)
            .disabled(run.terminal == nil)
            .help("Show the command's real terminal, where you can type directly")
    }
}
