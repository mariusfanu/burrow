import SwiftUI

struct SidebarView: View {
    @Binding var selection: Screen

    var body: some View {
        List(selection: $selection) {
            ForEach(Screen.groups) { group in
                if let title = group.title {
                    Section(title) { SidebarRows(screens: group.screens) }
                } else {
                    SidebarRows(screens: group.screens)
                }
            }
        }
        .listStyle(.sidebar)
    }
}
