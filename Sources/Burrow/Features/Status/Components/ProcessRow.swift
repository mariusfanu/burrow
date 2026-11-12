import BurrowCore
import SwiftUI

struct ProcessRow: View {
    let process: StatusSnapshot.Process

    var body: some View {
        HStack {
            Text(process.name ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(process.command ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\((process.cpu ?? 0).formatted(.number.precision(.fractionLength(1))))%")
                .foregroundStyle((process.cpu ?? 0) > 50 ? Color.orange : Color.primary)
                .frame(width: 70, alignment: .trailing)
            Text((process.memoryBytes ?? 0).memorySize)
                .frame(width: 84, alignment: .trailing)
            Text("\(process.pid ?? 0)")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}
