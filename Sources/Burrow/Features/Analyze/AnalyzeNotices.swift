import BurrowCore
import SwiftUI

struct AnalyzeNotices: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    var body: some View {
        VStack(spacing: Theme.Space.row) {
            if let notice = model.noticeMessage {
                GlassToast(
                    text: notice,
                    undo: undoAction,
                    dismiss: model.dismissNotice
                )
            }
            if let error = model.errorMessage {
                InlineNotice(text: error, tint: .red) { model.errorMessage = nil }
                    .frame(maxWidth: 520)
            }
        }
    }

    private var undoAction: (() -> Void)? {
        guard model.noticeShowsUndo, model.lastTrashed != nil else { return nil }
        return { model.undoTrash(cli: cli) }
    }
}
