import BurrowCore
import SwiftUI

struct ConfirmPromptContent: View {
    let text: String
    let requestID: UUID
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
            if run.allowsTerminalInput {
                Button("Show Terminal", action: run.showTerminalForPrompt)
                    .help("Answer in the real terminal")
            }
            Spacer()
            Button("Cancel", role: .cancel, action: run.answerDecline)
                .keyboardShortcut(.cancelAction)
            Button(run.isPreview ? "Continue" : CLIPrompt.confirmTitle(from: text)) {
                run.answerConfirm(requestID: requestID)
            }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(confirmsWithReturn ? .defaultAction : nil)
        }
    }

    /// Return mustn't be the way something permanent happens.
    private var confirmsWithReturn: Bool {
        run.isPreview || !run.isIrreversible
    }
}
