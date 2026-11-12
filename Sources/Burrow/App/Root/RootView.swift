import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(selection: $model.selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 280)
        } detail: {
            PageHost()
                .toolbar { AppToolbar() }
        }
        .navigationTitle(model.selection.title)
        .navigationSubtitle(model.subtitle)
        .task { await model.locateCLI() }
        #if DEBUG
        .onAppear { model.openSettingsForDebug = { openSettings() } }
        .tint(ProcessInfo.processInfo.environment["BURROW_ACCENT"] == nil ? nil : Color(hex: Theme.accent))
        #endif
        .background { WindowVisibilityObserver(changed: model.setWindowVisible).frame(width: 0, height: 0) }
        .disabled(model.isShuttingDown)
    }
}
