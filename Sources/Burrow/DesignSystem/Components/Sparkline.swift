import SwiftUI

/// A live trace that glides one step when a sample arrives, then rests. Resting between
/// samples keeps a dashboard that's left open from costing CPU all day.
struct Sparkline: View {
    let values: [Double]
    /// Bumps once per sample and starts each scroll.
    let sampleID: Int
    var tint: Color = .accentColor
    var maximum: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            guard !Motion.isReduced(reduceMotion) else { return }
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
                .animation(Motion.isReduced(reduceMotion) ? nil : .smooth(duration: 0.45), value: level)
        }
    }

    /// Where the oldest drawn sample sits, as a fraction of the width.
    private var traceStart: Double {
        Self.traceStart(sampleCount: values.count, capacity: capacity)
    }

    static func traceStart(sampleCount: Int, capacity: Int = 45) -> Double {
        guard sampleCount > 0 else { return 1 }
        let drawn = min(sampleCount, capacity + 1)
        return max(1 - Double(drawn - 1) / Double(capacity - 1), 0)
    }

    private var resolvedMaximum: Double {
        let peak = max(values.suffix(capacity).max() ?? 1, 0.01)
        return maximum ?? min(peak * 1.15, .greatestFiniteMagnitude)
    }
}
