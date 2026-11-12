import SwiftUI

/// Ground whose level eases between values while its layers drift.
@Animatable
struct AnimatedGround: View {
    var level: Double
    var drift: Double
    @AnimatableIgnored var layers: [Gradient]

    var body: some View {
        Canvas { context, size in
            // The ground stays below the page's text, even on a full disk.
            let surface = size.height * (1 - 0.1 - 0.3 * min(max(level, 0), 1))
            for (index, gradient) in layers.enumerated() {
                let depth = CGFloat(index) / CGFloat(layers.count)
                let top = surface + (size.height - surface) * depth
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                let amplitude = 5 + CGFloat(index) * 2.5
                let travel = 0.6 + Double(index) * 0.22
                for step in 0...60 {
                    let x = size.width * CGFloat(step) / 60
                    let angle = Double(step) / 60 * .pi * 2.4 + Double(index) * 1.7 + drift * travel
                    let y = top + amplitude * CGFloat(sin(angle)) + amplitude * 0.4 * CGFloat(sin(angle * 2.3 + 1))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: top - amplitude * 1.4),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}
