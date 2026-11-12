import SwiftUI

struct StatusCardTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline)
            .bold()
            .foregroundStyle(.secondary)
    }
}
