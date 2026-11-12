import SwiftUI

/// A file size that counts up from zero, for the moment a result lands.
@Animatable
struct CountingBytes: View {
    var bytes: Double

    var body: some View {
        // Double(Int64.max) rounds up to 2^63, which cannot be converted back to Int64.
        let count = bytes < Double(Int64.max) ? Int64(bytes) : Int64.max
        Text(count.countedSize)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
