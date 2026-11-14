import SwiftUI

/// The trace itself. `scroll` shifts it by a fraction of one sample.
@Animatable
struct SparkShape: Shape {
    @AnimatableIgnored var values: [Double]
    @AnimatableIgnored var capacity: Int
    @AnimatableIgnored var maximum: Double
    var scroll: Double
    @AnimatableIgnored var closesArea: Bool

    func path(in rect: CGRect) -> Path {
        let recent = values.suffix(max(capacity, 0) + 1)
        guard capacity > 1, recent.count > 1, maximum.isFinite, maximum > 0, scroll.isFinite else {
            return Path()
        }
        let step = rect.width / CGFloat(capacity - 1)
        var points: [CGPoint] = []
        points.reserveCapacity(recent.count)
        let newest = recent.count - 1
        for (index, value) in recent.enumerated() {
            let fromEnd = CGFloat(newest - index) - CGFloat(scroll)
            let x = rect.maxX - fromEnd * step
            let normalized = value.isFinite ? min(max(value / maximum, 0), 1) : 0
            let y = rect.maxY - rect.height * CGFloat(normalized)
            points.append(CGPoint(x: x, y: y))
        }

        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            // Horizontal tangents keep the curve from overshooting between samples.
            let previous = points[index - 1]
            let current = points[index]
            let middle = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: middle, y: previous.y),
                control2: CGPoint(x: middle, y: current.y)
            )
        }
        if closesArea, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
