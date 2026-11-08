import BurrowCore
import SwiftUI

/// The moment a command ends. A checkmark draws itself, the space freed counts up, and a
/// soft light rises behind it and fades. It plays once, then gets out of the way.
struct CompletionView: View {
    let run: RunController
    @Binding var showsDetails: Bool
    var isCompact = false

    @State private var shownBytes = 0.0
    @State private var isDrawn = false
    @State private var glow = 0.0
    /// Bumps once when a success lands, which plays the bounce and the ripple.
    @State private var landings = 0

    var body: some View {
        Group {
            if isCompact {
                compactBody
            } else {
                fullBody
            }
        }
        .onAppear(perform: celebrate)
    }

    private var fullBody: some View {
        VStack(spacing: Theme.Space.card) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.32), .clear], center: .center, startRadius: 0, endRadius: 130))
                    .frame(width: 260, height: 260)
                    .opacity(glow)
                    .scaleEffect(0.7 + 0.3 * glow)
                    .accessibilityHidden(true)
                LandingRipple(tint: tint, trigger: landings)
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(tint)
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
                Text(headline)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
            }

            Text(detail)
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
    }

    private var compactBody: some View {
        HStack(spacing: Theme.Space.item) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(compactHeadline)
                    .font(.title3)
                    .bold()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsDetails, !run.keepsLogAtEnd {
                Button("Hide Details") { showsDetails = false }
                    .buttonStyle(.link)
            }
        }
        .padding([.horizontal, .top], Theme.Space.page)
        .padding(.bottom, Theme.Space.item)
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

    private var symbol: String {
        if run.wasDeclined { return "xmark.circle" }
        if run.wasCancelled { return "stop.circle" }
        return run.didSucceed ? "checkmark.circle" : "xmark.circle"
    }

    private var tint: Color {
        if run.wasCancelled || run.wasDeclined { return .secondary }
        return run.didSucceed ? .green : .red
    }

    private var headline: String {
        if run.wasDeclined { return "Cancelled" }
        if run.wasCancelled { return "Stopped" }
        return run.didSucceed ? run.doneTitle : "Couldn’t Finish"
    }

    private var compactHeadline: String {
        if let summary = run.summary, run.didSucceed {
            return summary.isEstimate ? "\(summary.bytes.fileSize) would be freed" : "\(summary.bytes.fileSize) freed"
        }
        return headline
    }

    private var detail: String {
        if run.wasDeclined { return "Nothing was changed." }
        if run.wasCancelled { return "Anything already finished stays finished." }
        switch run.phase {
        case .failedToStart:
            return "The command couldn’t start."
        case .finished(let status) where status != 0:
            return "The command ended with status \(status). The log has the details."
        default:
            let time = Duration.seconds(run.duration).formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 2))
            return "Finished in \(time)."
        }
    }
}

/// One ring that leaves the checkmark as it lands, then is gone. It's hidden at rest, so it
/// shows only while its keyframes play.
private struct LandingRipple: View {
    let tint: Color
    let trigger: Int

    var body: some View {
        Circle()
            .strokeBorder(tint, lineWidth: 2)
            .frame(width: 64, height: 64)
            .keyframeAnimator(initialValue: Values(), trigger: trigger) { ring, values in
                ring
                    .scaleEffect(values.scale)
                    .opacity(values.opacity)
            } keyframes: { _ in
                // It fades faster than it grows, so it's gone before it reaches the figure below.
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(1.75, duration: 0.9)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.7, duration: 0.01)
                    CubicKeyframe(0, duration: 0.7)
                }
            }
            .accessibilityHidden(true)
    }

    private struct Values {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}
