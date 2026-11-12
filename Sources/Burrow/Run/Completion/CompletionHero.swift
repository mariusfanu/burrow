import SwiftUI

/// The moment a command ends. A checkmark draws itself, the space freed counts up, and a
/// soft light rises behind it and fades. It plays once, then gets out of the way.
struct CompletionHero: View {
    let run: RunController
    @Binding var showsDetails: Bool

    @State private var shownBytes = 0.0
    @State private var isDrawn = false
    @State private var glow = 0.0
    /// Bumps once when a success lands, which plays the bounce and the ripple.
    @State private var landings = 0

    var body: some View {
        VStack(spacing: Theme.Space.card) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [run.completionTint.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 130))
                    .frame(width: 260, height: 260)
                    .opacity(glow)
                    .scaleEffect(0.7 + 0.3 * glow)
                    .accessibilityHidden(true)
                LandingRipple(tint: run.completionTint, trigger: landings)
                Image(systemName: run.completionSymbol)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(run.completionTint)
                    .symbolEffect(.drawOn, isActive: !isDrawn && !Motion.isReduced)
                    .symbolEffect(.bounce, options: .speed(1.2), value: landings)
                    .accessibilityHidden(true)
            }
            .frame(height: 96)

            if let summary = run.summary, run.didSucceed {
                CountingBytes(bytes: shownBytes)
                Text(summary.isEstimate ? "would be freed" : "freed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text(run.completionHeadline)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
            }

            Text(run.completionDetail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !run.lines.isEmpty {
                Button("Show Details") { showsDetails = true }
                    .buttonStyle(.link)
                    .padding(.top, Theme.Space.tight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .onAppear(perform: celebrate)
    }

    private func celebrate() {
        let bytes = Double(run.summary?.bytes ?? 0)
        guard !Motion.isReduced else {
            shownBytes = bytes
            isDrawn = true
            return
        }
        withAnimation(.easeOut(duration: 0.7)) {
            isDrawn = true
        } completion: {
            // Success lands with a ripple. A failure or a stop just stays drawn.
            guard run.didSucceed, !run.wasCancelled, !run.wasDeclined else { return }
            landings += 1
        }
        withAnimation(.easeOut(duration: 1.0).delay(0.1)) { shownBytes = bytes }
        withAnimation(.easeOut(duration: 0.5)) {
            glow = 1
        } completion: {
            withAnimation(.easeIn(duration: 1.2)) { glow = 0 }
        }
    }
}
