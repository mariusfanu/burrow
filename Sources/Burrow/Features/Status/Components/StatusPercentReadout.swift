import SwiftUI

struct StatusPercentReadout: View {
    let percent: Double

    var body: some View {
        if (0...100).contains(percent) {
            StatusValueLine(value: percent.formatted(.number.precision(.fractionLength(0))), unit: "%", number: percent)
        } else {
            StatusValueLine(value: "—", unit: "")
        }
    }
}
