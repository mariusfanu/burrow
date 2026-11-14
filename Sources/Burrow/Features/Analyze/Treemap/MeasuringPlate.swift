import SwiftUI

/// The folder's color filling the map while its contents are measured, with a slow sheen.
struct MeasuringPlate: View {
    let name: String
    let tint: UInt32?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .fill(tint.map { Color(hex: $0) } ?? Color.secondary.opacity(0.18))
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .fill(.black.opacity(0.08))
                .phaseAnimator([false, true]) { view, isBright in
                    view.opacity(Motion.isReduced(reduceMotion) ? 0.5 : (isBright ? 1 : 0.1))
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            VStack(spacing: Theme.Space.row) {
                ProgressView()
                    .controlSize(.small)
                Text("Measuring \(name)")
                    .font(.callout)
            }
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
        }
        .accessibilityElement(children: .combine)
    }
}
