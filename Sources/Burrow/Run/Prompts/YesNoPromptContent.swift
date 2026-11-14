import SwiftUI

struct YesNoPromptContent: View {
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
                .keyboardShortcut((run.isPreview || !run.isIrreversible) ? .defaultAction : nil)
        }
    }

    private func declineAnswer() {
        run.answerYesNo(false)
    }

    private func acceptAnswer() {
        run.answerYesNo(true)
    }
}
