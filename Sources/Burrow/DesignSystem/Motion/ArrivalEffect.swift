import SwiftUI

struct ArrivalEffect: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrival = ArrivalState()

    /// Rows further down a list arrive by scrolling, and must never lag behind the scroll.
    private var isPartOfWave: Bool { index <= ArrivalState.waveLimit }

    func body(content: Content) -> some View {
        content
            .opacity(arrival.isVisible(at: index) ? 1 : 0)
            .offset(y: arrival.isVisible(at: index) || Motion.isReduced(reduceMotion) ? 0 : 10)
            .onAppear {
                guard !arrival.hasArrived else { return }
                if isPartOfWave {
                    withAnimation(Motion.settle(reduced: reduceMotion).delay(Motion.stagger(index, reduced: reduceMotion))) { arrival.appear() }
                } else {
                    // This row may later move into the entrance wave without appearing again.
                    arrival.appear()
                }
            }
    }
}
