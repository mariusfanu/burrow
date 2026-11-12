import BurrowCore
import SwiftUI

struct CleanSectionHeader: View {
    let section: CleanReport.Section
    let largestBytes: Int64
    @Binding var isExpanded: Bool

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: Theme.Space.item) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .transaction { transaction in
                            if Motion.isReduced { transaction.animation = nil }
                        }
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Image(systemName: Self.symbol(for: section.name))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(section.name)
                        .font(.headline)
                    Spacer()
                    if section.bytes > 0 {
                        Text(section.bytes.fileSize)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(section.bytes)))
                    } else if section.rows.contains(where: { $0.kind == .review }) {
                        // These are pointers for you to look at. Clean leaves them alone, so
                        // they add nothing to the total.
                        FactTag(text: "For Review")
                            .help("Clean doesn’t remove these. Look at them yourself, for example in Disk Explorer.")
                    }
                }
                if section.bytes > 0, largestBytes > 0 {
                    LevelBar(part: section.bytes, of: largestBytes, height: 3)
                        .padding(.leading, 52)
                }
            }
            .padding(.horizontal, Theme.Space.card)
            .padding(.vertical, Theme.Space.cluster)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(isExpanded ? "Hide the files in this group" : "Show the files in this group")
    }

    private func toggle() {
        withAnimation(Motion.glide) { isExpanded.toggle() }
    }

    private static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case let value where value.contains("user"): "person"
        case let value where value.contains("app cache"): "square.stack.3d.up"
        case let value where value.contains("browser"): "safari"
        case let value where value.contains("cloud"): "icloud"
        case let value where value.contains("developer"): "hammer"
        case let value where value.contains("apps &"): "app.badge"
        case let value where value.contains("virtual"): "cube"
        case let value where value.contains("application support"): "folder"
        case let value where value.contains("leftover"): "shippingbox"
        case let value where value.contains("silicon"): "cpu"
        case let value where value.contains("backup"): "iphone"
        case let value where value.contains("time machine"): "clock.arrow.circlepath"
        case let value where value.contains("large"): "doc.badge.ellipsis"
        case let value where value.contains("project"): "folder.badge.gearshape"
        case let value where value.contains("system"): "gearshape"
        default: "tray"
        }
    }
}
