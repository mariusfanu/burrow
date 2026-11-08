import SwiftUI
import Testing
@testable import Burrow

@MainActor
struct MotionRenderingTests {
    @Test func countingBytesHandlesSaturatedTotalsAndTruncatesAnimationFractions() throws {
        // Both large values format to the same size, but only nextDown converts to Int64.
        let limit = Double(Int64.max)
        for (value, expected) in [(limit, limit.nextDown), (999.9, 999.0)] {
            let rendered = try pixels(CountingBytes(bytes: value).frame(width: 500, height: 100))
            let reference = try pixels(CountingBytes(bytes: expected).frame(width: 500, height: 100))
            #expect(rendered.contains { $0 != 0 })
            #expect(rendered == reference)
        }
    }

    @Test func reducedMotionDisclosuresRowsAndTilesMatchAnUnmovedFade() throws {
        let content = Rectangle().fill(.white).frame(width: 40, height: 20)
        let fade = try pixels(content.opacity(0.5).frame(width: 80, height: 60))
        // Exercise intermediate frames, where scale/offset transitions used to keep moving
        // even though their animation curve had changed to a short fade.
        for (scale, offset): (CGFloat, CGFloat) in [(1, -6), (0.96, 0), (0.7, 0), (0.3, 0)] {
            let reduced = content
                .modifier(ContentMotionEffect(progress: 0.5, scale: scale, y: offset, isReduced: true))
                .frame(width: 80, height: 60)
            #expect(try pixels(reduced) == fade)
        }
        let standard = content
            .modifier(ContentMotionEffect(progress: 0.5, scale: 0.7, y: -6, isReduced: false))
            .frame(width: 80, height: 60)
        #expect(try pixels(standard) != fade)
    }
}
