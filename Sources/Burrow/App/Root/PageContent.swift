import BurrowCore
import SwiftUI

struct PageContent: View {
    let screen: Screen
    let cli: CLIInfo
    @Environment(AppModel.self) private var model

    var body: some View {
        if !cli.hasBundledTools, screen == .status || screen == .analyze {
            ContentUnavailableView(
                "This Copy of Mole Is Missing a Tool",
                systemImage: "wrench.adjustable",
                description: Text("\(screen.title) uses the status and analyze programs that come with Mole releases. Install a release with Homebrew, or choose another copy in Settings.")
            )
        } else {
            switch screen {
            case .overview: OverviewView(cli: cli)
            case .clean: CleanView(model: model.clean, cli: cli)
            case .uninstall: UninstallView(model: model.uninstall, cli: cli)
            case .purge: MenuFlowView(model: model.purge, cli: cli)
            case .installers: MenuFlowView(model: model.installers, cli: cli)
            case .slim: MenuFlowView(model: model.slim, cli: cli)
            case .optimize: OptimizeView(model: model.optimize, cli: cli)
            case .analyze: AnalyzeView(model: model.analyze, cli: cli)
            case .status: StatusView(store: model.status)
            case .history: HistoryView(model: model.history, cli: cli)
            }
        }
    }
}
