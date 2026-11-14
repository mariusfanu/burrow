import SwiftUI

/// A file size that counts up from zero, for the moment a result lands.
@Animatable
struct CountingBytes: View {
    var bytes: Double

    var body: some View {
        let count = Self.clampedCount(bytes)
        Text(count.countedSize)
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    static func clampedCount(_ bytes: Double) -> Int64 {
        // Double(Int64.max) rounds up to 2^63, which cannot be converted back to Int64.
        guard bytes.isFinite else { return 0 }
        return bytes < Double(Int64.max) ? Int64(max(bytes, 0)) : Int64.max
    }
}
