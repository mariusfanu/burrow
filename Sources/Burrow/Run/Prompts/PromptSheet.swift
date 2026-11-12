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
                ConfirmPromptContent(text: text, requestID: request.id, run: run)
            case .yesNo(let text):
                YesNoPromptContent(text: text, run: run)
            }
        }
        .padding(Theme.Space.sheet)
        .frame(width: 500)
        .interactiveDismissDisabled()
    }
}
