import SwiftUI

struct AnalyzePathStep: View {
    let level: AnalyzeLevel
    let isCurrent: Bool
    let jump: () -> Void

    var body: some View {
        Button(action: jump) {
            HStack(spacing: 5) {
                if let tint = level.tint {
                    Circle()
                        .fill(Color(hex: tint))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(level.name)
                    .bold(isCurrent)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(level.path ?? "The overview of this Mac")
    }
}
