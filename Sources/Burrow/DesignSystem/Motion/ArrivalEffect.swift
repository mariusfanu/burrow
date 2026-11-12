import SwiftUI

struct ArrivalEffect: ViewModifier {
    let index: Int
    @State private var arrival = ArrivalState()

    /// Rows further down a list arrive by scrolling, and must never lag behind the scroll.
    private var isPartOfWave: Bool { index <= ArrivalState.waveLimit }

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
