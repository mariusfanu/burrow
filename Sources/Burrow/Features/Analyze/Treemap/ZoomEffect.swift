import SwiftUI

@Animatable
struct ZoomEffect: ViewModifier {
    enum Role { case incoming, outgoing }

    var progress: CGFloat
    @AnimatableIgnored var rect: CGRect?
    @AnimatableIgnored var size: CGSize
    @AnimatableIgnored var isZoomingIn: Bool
    @AnimatableIgnored var role: Role

    func body(content: Content) -> some View {
        let transform = currentTransform
        return content
            .scaleEffect(transform.scale)
            .offset(transform.offset)
            .opacity(transform.opacity)
    }

    /// Where a map sits when the opened tile fills the view, using one scale so nothing distorts.
    private var zoomed: (scale: CGFloat, offset: CGSize) {
        guard let rect, rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else {
            return (1.08, .zero)
        }
        let scale = max(1 / rect.width, 1 / rect.height)
        let centerX = (rect.midX - 0.5) * size.width
        let centerY = (rect.midY - 0.5) * size.height
        return (scale, CGSize(width: -centerX * scale, height: -centerY * scale))
    }

    private var currentTransform: (scale: CGFloat, offset: CGSize, opacity: Double) {
        let amount = min(max(progress, 0), 1)
        switch (role, isZoomingIn) {
        case (.outgoing, true):
            // The old map zooms past behind the growing plate.
            return mix(from: (1, .zero), to: zoomed, amount: amount, opacity: 1 - ramp(amount, start: 0.1, end: 0.55))
        case (.incoming, true):
            // The contents appear inside the plate once it's large enough to hold them.
            return mix(from: (0.965, .zero), to: (1, .zero), amount: amount, opacity: ramp(amount, start: 0.42, end: 0.85))
        case (.outgoing, false):
            // The contents leave first, uncovering the plate.
            return mix(from: (1, .zero), to: (0.965, .zero), amount: amount, opacity: 1 - ramp(amount, start: 0, end: 0.35))
        case (.incoming, false):
            // The parent map settles back from the zoomed position.
            return mix(from: zoomed, to: (1, .zero), amount: amount, opacity: ramp(amount, start: 0.1, end: 0.6))
        }
    }

    private func ramp(_ amount: CGFloat, start: CGFloat, end: CGFloat) -> Double {
        Double(min(max((amount - start) / (end - start), 0), 1))
    }

    private func mix(
        from start: (scale: CGFloat, offset: CGSize),
        to end: (scale: CGFloat, offset: CGSize),
        amount: CGFloat,
        opacity: Double
    ) -> (scale: CGFloat, offset: CGSize, opacity: Double) {
        // Mixing scale in log space keeps the zoom's speed even across a large change.
        let scale = exp(log(start.scale) + (log(end.scale) - log(start.scale)) * amount)
        let width = start.offset.width + (end.offset.width - start.offset.width) * amount
        let height = start.offset.height + (end.offset.height - start.offset.height) * amount
        return (scale, CGSize(width: width, height: height), opacity)
    }
}
