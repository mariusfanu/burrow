import SwiftUI

/// Says that the log has let go of its oldest rows.
struct HiddenLinesNote: View {
    let count: Int

    var body: some View {
        Text("\(count.formatted()) earlier lines aren’t shown.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
