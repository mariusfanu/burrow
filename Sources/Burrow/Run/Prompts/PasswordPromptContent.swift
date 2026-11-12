import SwiftUI

struct PasswordPromptContent: View {
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
