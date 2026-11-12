import BurrowCore
import SwiftUI

struct MenuItemRow: View {
    let item: MenuItem
    let largestBytes: Int64
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.cluster) {
            SelectionCheckbox(title: item.name, isSelected: isSelected, toggle: toggle)
            VStack(alignment: .leading, spacing: Theme.Space.micro) {
                Text(item.path?.abbreviatingHome ?? item.name)
                    .font(.body)
                    .bold(isSelected)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path ?? item.rowText)
                if item.path != nil {
                    Text(item.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let tag = item.tag {
                FactTag(text: tag, tint: .blue)
            }
            if let age = item.age {
                FactTag(text: age)
            }
            VStack(alignment: .trailing, spacing: Theme.Space.tight) {
                Text(item.sizeText ?? "")
                    .font(.callout)
                    .monospacedDigit()
                LevelBar(part: item.bytes, of: largestBytes, height: 3)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
        .animation(Motion.snap, value: isSelected)
    }
}
