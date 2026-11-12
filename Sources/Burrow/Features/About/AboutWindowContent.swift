import SwiftUI

struct AboutWindowContent: View {
    var body: some View {
        ScrollView {
            AboutView()
                .padding(.top, Theme.Space.item)
        }
        .frame(width: 440, height: 520)
    }
}
