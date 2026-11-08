import AppKit
import SwiftUI

/// Burrow's motion vocabulary. Things rise a little and settle, as if lightened.
///
/// Every animation and transition comes from here, so that Reduce Motion is honored in
/// one place: movement, scale and blur become short fades, as the HIG asks.
enum Motion {
    /// True when the system asks for less motion.
    static var isReduced: Bool {
        freezesTransitions || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Debug captures need the settled view immediately. The system setting keeps short fades.
    private static let freezesTransitions: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["BURROW_REDUCE_MOTION"] == "1"
        #else
        false
        #endif
    }()

    private static let fade: Animation = freezesTransitions ? .linear(duration: 0.001) : .easeInOut(duration: 0.15)

    private static var reducedTransition: AnyTransition { freezesTransitions ? .identity : .opacity }

    /// Direct feedback: hover, selection, toggles.
    static var snap: Animation { isReduced ? fade : .snappy(duration: 0.2) }
    /// Moving between states and pages.
    static var glide: Animation { isReduced ? fade : .smooth(duration: 0.34) }
    /// Something arriving and coming to rest.
    static var settle: Animation { isReduced ? fade : .spring(duration: 0.5, bounce: 0.16) }
    /// Large, weighty changes such as a meter level or a treemap's layout.
    static var lift: Animation { isReduced ? fade : .spring(duration: 0.75, bounce: 0.06) }

    /// The delay for the item at `index`, so that groups arrive as a soft wave. It's capped,
    /// because nobody should wait for an animation.
    static func stagger(_ index: Int, step: Double = 0.028) -> Double {
        isReduced ? 0 : Double(min(index, 12)) * step
    }

    // MARK: - Transitions

    /// Fades in from a soft blur, the way Liquid Glass materializes instead of sliding.
    static var materialize: AnyTransition {
        isReduced ? reducedTransition : .modifier(
            active: MaterializeEffect(progress: 0),
            identity: MaterializeEffect(progress: 1)
        )
    }

    /// Rises slightly into place.
    static var rise: AnyTransition {
        isReduced ? reducedTransition : .asymmetric(
            insertion: .modifier(active: RiseEffect(progress: 0), identity: RiseEffect(progress: 1)),
            removal: .opacity
        )
    }

    /// Content entering a disclosure, tile or row follows the same motion policy.
    static func content(scale: CGFloat = 1, y: CGFloat = 0) -> AnyTransition {
        let reduced = isReduced
        return freezesTransitions ? .identity : .modifier(
            active: ContentMotionEffect(progress: 0, scale: scale, y: y, isReduced: reduced),
            identity: ContentMotionEffect(progress: 1, scale: scale, y: y, isReduced: reduced)
        )
    }

    /// A new page rises from the direction of travel in the sidebar. The old one just
    /// dissolves, because only where you're going matters.
    static func page(movingDown: Bool) -> AnyTransition {
        guard !isReduced else { return reducedTransition }
        return .asymmetric(
            insertion: .modifier(
                active: PageEffect(progress: 0, travel: movingDown ? 14 : -14),
                identity: PageEffect(progress: 1, travel: movingDown ? 14 : -14)
            ),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }
}

/// Content transitions fade without spatial movement when Reduce Motion is enabled.
struct ContentMotionEffect: ViewModifier {
    let progress: CGFloat
    let scale: CGFloat
    let y: CGFloat
    let isReduced: Bool

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(isReduced ? 1 : scale + (1 - scale) * progress)
            .offset(y: isReduced ? 0 : y * (1 - progress))
    }
}

private struct MaterializeEffect: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.97 + 0.03 * progress)
            .blur(radius: 8 * (1 - progress))
    }
}

private struct RiseEffect: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: 8 * (1 - progress))
    }
}

private struct PageEffect: ViewModifier {
    let progress: Double
    let travel: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .offset(y: travel * (1 - progress))
            .blur(radius: 5 * (1 - progress))
    }
}

extension View {
    /// Plays a short wave of arrival once, for the item at `index` in a group.
    func arrives(index: Int = 0) -> some View {
        modifier(ArrivalEffect(index: index))
    }

    /// Shakes sideways whenever `trigger` changes, the macOS way of saying "not accepted".
    func shake(on trigger: Int) -> some View {
        modifier(ShakeEffect(trigger: trigger, isReduced: Motion.isReduced))
    }
}

private struct ShakeEffect: ViewModifier {
    let trigger: Int
    let isReduced: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { [isReduced] view, offset in
            view.offset(x: isReduced ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack(\.self) {
                SpringKeyframe(-9, duration: 0.07)
                SpringKeyframe(8, duration: 0.09)
                SpringKeyframe(-5, duration: 0.08)
                SpringKeyframe(3, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}

private struct ArrivalEffect: ViewModifier {
    let index: Int
    @State private var arrival = ArrivalState()

    /// Rows further down a list arrive by scrolling, and must never lag behind the scroll.
    private var isPartOfWave: Bool { index <= 16 }

    func body(content: Content) -> some View {
        content
            .opacity(arrival.isVisible(at: index) ? 1 : 0)
            .offset(y: arrival.isVisible(at: index) || Motion.isReduced ? 0 : 10)
            .onAppear {
                guard !arrival.hasArrived else { return }
                if isPartOfWave {
                    withAnimation(Motion.settle.delay(Motion.stagger(index))) { arrival.appear() }
                } else {
                    // This row may later move into the entrance wave without appearing again.
                    arrival.appear()
                }
            }
    }
}
