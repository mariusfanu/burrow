import SwiftUI

struct SidebarRows: View {
    let screens: [Screen]
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(screens) { screen in
            SidebarRow(
                screen: screen,
                isSelected: model.selection == screen,
                isWorking: model.isWorking(screen),
                needsAttention: model.needsAttention(screen),
                badge: model.badge(for: screen)
            )
            .tag(screen)
        }
    }
}
