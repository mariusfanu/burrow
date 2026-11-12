import SwiftUI

struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.enumerated(), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .fill(Color.accentColor.opacity(0.45 + min(value, 100) / 100 * 0.55))
                    .frame(height: max(22 * min(value, 100) / 100, 2))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .animation(Motion.snap, value: values)
        .accessibilityHidden(true)
    }
}
