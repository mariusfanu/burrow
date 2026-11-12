import SwiftUI

struct SystemCleanPromptContent: View {
    let run: RunController

    var body: some View {
        Label("Clean System Caches Too?", systemImage: "lock.shield")
            .font(.title3)
            .bold()
        Text("System caches and logs need administrator access. If you skip them, cleanup continues with the files in your account. Escape stops the cleanup.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            // Escape has to mean stop. Skipping carries on removing files.
            Button("Stop Cleanup", role: .cancel, action: run.cancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Skip System Caches", action: skip)
            Button("Use Administrator Access", action: useAdmin)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func skip() {
        run.answerSystemClean(useAdmin: false)
    }

    private func useAdmin() {
        run.answerSystemClean(useAdmin: true)
    }
}
