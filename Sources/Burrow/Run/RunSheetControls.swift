import SwiftUI

/// Inline controls for a run shown in a sheet.
struct RunSheetControls: View {
    @Bindable var run: RunController
    let close: (() -> Void)?

    var body: some View {
        HStack {
            Toggle("Terminal", systemImage: "terminal", isOn: $run.isTerminalVisible)
                .toggleStyle(.button)
                .disabled(run.terminal == nil)
            Spacer()
            if run.isRunning {
                Button("Cancel", role: .cancel) { run.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else if let close {
                Button("Done", action: close)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.group)
    }
}
