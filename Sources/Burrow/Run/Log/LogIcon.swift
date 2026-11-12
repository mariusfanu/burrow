import BurrowCore
import SwiftUI

struct LogIcon: View {
    let kind: LogLine.Kind
    @State private var isDrawn = false

    var body: some View {
        Group {
            if kind == .plain {
                Color.clear
            } else {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
                    .symbolEffect(.drawOn, isActive: kind == .success && !isDrawn)
                    .accessibilityLabel(label)
            }
        }
        .frame(width: 14, height: 12)
        .onAppear {
            withAnimation(.easeOut(duration: Motion.isReduced ? 0 : 0.35)) { isDrawn = true }
        }
    }

    private var symbol: String {
        switch kind {
        case .section, .plain: "minus"
        case .success: "checkmark.circle.fill"
        case .preview: "circle"
        case .note: "exclamationmark.circle"
        case .review: "info.circle"
        case .meta: "gearshape"
        case .failure: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .success: .green
        case .preview: .accentColor
        case .note: .orange
        case .failure: .red
        default: .secondary
        }
    }

    private var label: String {
        switch kind {
        case .success: "Done"
        case .preview: "Would change"
        case .note: "Note"
        case .failure: "Failed"
        default: ""
        }
    }
}
