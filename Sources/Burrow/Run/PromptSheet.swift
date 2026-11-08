import BurrowCore
import SwiftUI

/// A native sheet for a question the CLI is asking on its terminal.
///
/// The CLI remains the decision point: nothing happens until it reads the answer, and the
/// sheet shows the CLI's own plan, so that what you confirm is what it will do.
struct PromptSheet: View {
    let request: PromptRequest
    let run: RunController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.group) {
            switch request.prompt {
            case .password:
                PasswordPromptContent(run: run)
            case .systemCleanChoice:
                SystemCleanPromptContent(run: run)
            case .confirm(let text):
                ConfirmPromptContent(text: text, run: run)
            case .yesNo(let text):
                YesNoPromptContent(text: text, run: run)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 500)
        .interactiveDismissDisabled()
    }
}

private struct PasswordPromptContent: View {
    let run: RunController

    @State private var password = ""
    @State private var shakes = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        Label("Administrator Access", systemImage: "lock.fill")
            .font(.title3)
            .bold()
        Text(message)
            .font(.callout)
            .foregroundStyle(run.passwordRejections > 0 ? .red : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        SecureField("Password", text: $password)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit(submit)
            .shake(on: shakes)
            .onAppear {
                isFocused = true
                if run.passwordRejections > 0 {
                    shakes += 1
                    Announcer.say(message)
                }
            }
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Continue", action: submit)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
        }
    }

    private var message: String {
        if run.passwordRejections > 0 {
            return "That password wasn’t accepted. Try again, or click Cancel to stop."
        }
        return "This step needs your Mac password for system-level work. Burrow sends it to the running command’s terminal only when terminal echo is off. Burrow doesn’t save it."
    }

    private func submit() {
        guard !password.isEmpty else { return }
        run.answerPassword(password)
        password = ""
    }

    private func cancel() {
        password = ""
        run.answerPasswordCancel()
    }
}

private struct SystemCleanPromptContent: View {
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

private struct ConfirmPromptContent: View {
    let text: String
    let run: RunController

    var body: some View {
        Text(CLIPrompt.question(from: text))
            .font(.title3)
            .bold()
            .fixedSize(horizontal: false, vertical: true)
        if run.isPreview {
            Label("This is a preview, so nothing will change.", systemImage: "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let consequence = run.consequence {
            Label(consequence, systemImage: run.isIrreversible ? "exclamationmark.triangle.fill" : "arrow.uturn.backward")
                .font(.callout)
                .foregroundStyle(run.isIrreversible ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !run.lines.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if run.hiddenLineCount > 0 {
                        HiddenLinesNote(count: run.hiddenLineCount)
                    }
                    ForEach(run.lines) { LogRow(line: $0) }
                }
                .padding(Theme.Space.item)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            .background(.fill.quinary, in: .rect(cornerRadius: Theme.Radius.card))
        }
        HStack {
            Button("Show Terminal", action: run.showTerminalForPrompt)
                .help("Answer in the real terminal, for options such as choosing personal data")
            Spacer()
            Button("Cancel", role: .cancel, action: run.answerDecline)
                .keyboardShortcut(.cancelAction)
            Button(run.isPreview ? "Continue" : CLIPrompt.confirmTitle(from: text), action: run.answerConfirm)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(confirmsWithReturn ? .defaultAction : nil)
        }
    }

    /// Return mustn't be the way something permanent happens.
    private var confirmsWithReturn: Bool {
        run.isPreview || !run.isIrreversible
    }
}

private struct YesNoPromptContent: View {
    let text: String
    let run: RunController

    var body: some View {
        Text(text)
            .font(.title3)
            .bold()
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Spacer()
            Button("No", role: .cancel, action: declineAnswer)
                .keyboardShortcut(.cancelAction)
            Button("Yes", action: acceptAnswer)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func declineAnswer() {
        run.answerYesNo(false)
    }

    private func acceptAnswer() {
        run.answerYesNo(true)
    }
}
