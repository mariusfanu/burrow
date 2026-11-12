import SwiftUI

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
