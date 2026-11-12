import AppKit
import BurrowCore
import SwiftUI

/// Shows the current page and carries the transition between pages.
struct PageHost: View {
    @Environment(AppModel.self) private var model
    /// Bumps when the system accent changes, so that derived colors follow it.
    @State private var accentRevision = 0
    /// The CLI version whose compatibility note has been dismissed.
    @AppStorage("dismissedCLINotice") private var dismissedNoticeVersion = ""

    private var compatibilityNotice: String? {
        guard let cli = model.cli, cli.version != dismissedNoticeVersion else { return nil }
        return CLICompatibility(version: cli.version).warning(version: cli.version)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if model.isLocating, model.cli == nil {
                    WorkingView(title: "Looking for the Mole CLI")
                } else if let cli = model.cli {
                    PageContent(screen: model.selection, cli: cli)
                        .id("\(model.selection.rawValue)-\(accentRevision)")
                        .transition(Motion.page(movingDown: model.movedDown))
                } else {
                    MissingCLIView()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            if let notice = compatibilityNotice {
                Divider()
                NoticeBar(text: notice) { dismissedNoticeVersion = model.cli?.version ?? "" }
            }
        }
        .animation(Motion.glide, value: model.selection)
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            accentRevision += 1
        }
    }
}
