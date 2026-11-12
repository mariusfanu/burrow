import BurrowCore
import SwiftUI

struct StatusHealthStrip: View {
    let snapshot: StatusSnapshot
    let sampleID: Int
    let isLive: Bool

    /// A missing score isn't a bad one, so it stays out of the red.
    private var score: Int? { snapshot.healthScore }

    private var tint: Color {
        switch score {
        case nil: .secondary
        case .some(80...): .green
        case .some(50..<80): .orange
        default: .red
        }
    }

    var body: some View {
        Surface(padding: Theme.Space.wide) {
            HStack(spacing: Theme.Space.wide) {
                RingGauge(fraction: Double(score ?? 0) / 100, tint: tint, lineWidth: 7) {
                    Text(score.map { "\($0)" } ?? "—")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(score ?? 0)))
                }
                .frame(width: 66, height: 66)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(score.map { "Health score \($0) of 100" } ?? "Health score unavailable")
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.healthScoreMsg ?? "Health")
                        .font(.title2)
                        .bold()
                    Text(deviceLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: Theme.Space.micro) {
                        if isLive {
                            StatusLiveDot(sampleID: sampleID)
                        } else {
                            Circle()
                                .fill(.secondary)
                                .frame(width: 7, height: 7)
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                        }
                        Text(isLive ? "Live" : "Not Updating")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text(uptimeLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var deviceLine: String {
        [snapshot.hardware?.model, snapshot.hardware?.cpuModel, snapshot.hardware?.osVersion]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var uptimeLine: String {
        let parts = [snapshot.uptime.map { "Up \($0)" }, snapshot.procs.map { "\($0) processes" }]
        var line = parts.compactMap { $0 }.joined(separator: " · ")
        if let zombies = snapshot.zombieCount, zombies > 0 { line += " · \(zombies) zombies" }
        return line
    }
}
