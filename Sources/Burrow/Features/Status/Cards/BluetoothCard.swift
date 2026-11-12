import BurrowCore
import SwiftUI

/// Connected devices, shown only when there are some.
struct BluetoothCard: View {
    let devices: [StatusSnapshot.Bluetooth]

    private var connected: [StatusSnapshot.Bluetooth] {
        devices.filter { $0.connected == true }
    }

    var body: some View {
        Surface {
            HStack(spacing: Theme.Space.wide) {
                StatusCardTitle(title: "Bluetooth", symbol: "wave.3.right")
                // By position, because two devices can share a name.
                ForEach(connected.enumerated(), id: \.offset) { _, device in
                    HStack(spacing: 5) {
                        Text(device.name ?? "")
                            .lineLimit(1)
                        Text(device.battery ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
