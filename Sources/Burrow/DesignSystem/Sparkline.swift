import SwiftUI

/// A live trace that glides one step when a sample arrives, then rests. Resting between
/// samples keeps a dashboard that's left open from costing CPU all day.
struct Sparkline: View {
    let values: [Double]
    /// Bumps once per sample and starts each scroll.
    let sampleID: Int
    var tint: Color = .accentColor
    var maximum: Double?

    @State private var scroll: Double = 0

    private let capacity = 45

    private let height: CGFloat = 40
    private let headSize: CGFloat = 6

    var body: some View {
        ZStack {
            // A hairline floor across the full width, so a trace that has only just begun
            // reads as the start of a chart rather than a stray mark.
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            SparkShape(values: values, capacity: capacity, maximum: resolvedMaximum, scroll: scroll, closesArea: true)
                .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                // A young trace's fill eases in from its first sample instead of starting at
                // a hard vertical edge.
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: traceStart), .init(color: .black, location: min(traceStart + 0.1, 1))],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            SparkShape(values: values, capacity: capacity, maximum: resolvedMaximum, scroll: scroll, closesArea: false)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .clipped()
        // The oldest samples fade out instead of ending at the card's edge.
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .padding(.trailing, headSize / 2)
        .overlay(alignment: .bottomTrailing) { head }
        .frame(height: height)
        .onChange(of: sampleID) {
            guard !Motion.isReduced else { return }
            var start = Transaction()
            start.disablesAnimations = true
            withTransaction(start) { scroll = 1 }
            withAnimation(.smooth(duration: 0.45)) { scroll = 0 }
        }
        .accessibilityHidden(true)
    }

    /// The newest sample, marked so the eye finds "now" at once.
    @ViewBuilder
    private var head: some View {
        if let latest = values.last {
            let level = CGFloat(min(max(latest / resolvedMaximum, 0), 1))
            Circle()
                .fill(tint)
                .frame(width: headSize, height: headSize)
                .background(Circle().fill(tint.opacity(0.22)).padding(-3))
                .offset(y: headSize / 2 - level * height)
                .animation(Motion.isReduced ? nil : .smooth(duration: 0.45), value: level)
        }
    }

    /// Where the oldest drawn sample sits, as a fraction of the width.
    private var traceStart: Double {
        let drawn = min(values.count, capacity + 1)
        return max(1 - Double(drawn - 1) / Double(capacity - 1), 0)
    }

    private var resolvedMaximum: Double {
        let peak = max(values.suffix(capacity).max() ?? 1, 0.01)
        return maximum ?? min(peak * 1.15, .greatestFiniteMagnitude)
    }
}

/// The trace itself. `scroll` shifts it by a fraction of one sample.
@Animatable
private struct SparkShape: Shape {
    @AnimatableIgnored var values: [Double]
    @AnimatableIgnored var capacity: Int
    @AnimatableIgnored var maximum: Double
    var scroll: Double
    @AnimatableIgnored var closesArea: Bool

    func path(in rect: CGRect) -> Path {
        let recent = values.suffix(capacity + 1)
        guard recent.count > 1, maximum > 0 else { return Path() }
        let step = rect.width / CGFloat(capacity - 1)
        var points: [CGPoint] = []
        points.reserveCapacity(recent.count)
        let newest = recent.count - 1
        for (index, value) in recent.enumerated() {
            let fromEnd = CGFloat(newest - index) - CGFloat(scroll)
            let x = rect.maxX - fromEnd * step
            let y = rect.maxY - rect.height * CGFloat(min(max(value / maximum, 0), 1))
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
