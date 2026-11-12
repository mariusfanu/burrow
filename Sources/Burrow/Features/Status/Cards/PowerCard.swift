import BurrowCore
import SwiftUI

struct PowerCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                if let battery = snapshot.batteries?.first {
                    StatusCardTitle(title: "Battery", symbol: "battery.75percent")
                    StatusValueLine(value: (battery.percent ?? 0).formatted(.number.precision(.fractionLength(0))), unit: "%", number: battery.percent ?? 0)
                    LevelBar(fraction: (battery.percent ?? 0) / 100, tint: StatusTint.battery(percent: battery.percent, status: battery.status))
                    Text(batteryLine(battery))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    StatusCardTitle(title: "Power", symbol: "bolt")
                    StatusValueLine(
                        value: (snapshot.thermal?.systemPower ?? 0).formatted(.number.precision(.fractionLength(1))),
                        unit: "W",
                        number: snapshot.thermal?.systemPower ?? 0
                    )
                }
                if !readings.isEmpty {
                    Text(readings.joined(separator: " · "))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func batteryLine(_ battery: StatusSnapshot.Battery) -> String {
        [battery.status, battery.health, battery.cycleCount.map { "\($0) cycles" }, battery.timeLeft]
            .compactMap { ($0 ?? "").isEmpty ? nil : $0 }
            .joined(separator: " · ")
    }

    private var readings: [String] {
        let thermal = snapshot.thermal
        return [
            temperature("CPU", thermal?.cpuTemp),
            temperature("GPU", thermal?.gpuTemp),
            (thermal?.fanCount ?? 0) > 0 ? "Fan \(thermal?.fanSpeed ?? 0) RPM" : nil,
        ].compactMap { $0 }
    }

    private func temperature(_ label: String, _ value: Double?) -> String? {
        guard let value, value > 0, let degrees = Int(exactly: value.rounded(.towardZero)) else { return nil }
        return "\(label) \(degrees)°C"
    }
}
