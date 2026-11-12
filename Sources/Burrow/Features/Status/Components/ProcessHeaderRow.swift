import SwiftUI

struct ProcessHeaderRow: View {
    var body: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 70, alignment: .trailing)
            Text("Memory")
                .frame(width: 84, alignment: .trailing)
            Text("PID")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.subheadline)
        .bold()
        .foregroundStyle(.secondary)
    }
}
