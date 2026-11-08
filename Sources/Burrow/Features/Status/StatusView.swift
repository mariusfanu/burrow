import BurrowCore
import SwiftUI

/// Colors that report a level. The number beside each bar says the same thing in words.
enum StatusTint {
    static func load(_ percent: Double) -> Color {
        switch percent {
        case 90...: .red
        case 70..<90: .orange
        default: .accentColor
        }
    }

    /// A battery being charged isn't a problem at any level.
    static func battery(percent: Double?, status: String?) -> Color {
        guard let percent, status?.lowercased() != "charging" else { return .green }
        switch percent {
        case ...10: return .red
        case ...20: return .orange
        default: return .green
        }
    }
}

struct StatusView: View {
    let store: StatusStore
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            if let snapshot = store.snapshot {
                StatusDashboard(store: store, snapshot: snapshot)
                    .transition(Motion.materialize)
            } else if let message = store.errorMessage {
                ContentUnavailableView("Live Status Isn’t Available", systemImage: "waveform.path.ecg", description: Text(message))
            } else {
                WorkingView(title: "Reading This Mac’s Vital Signs")
            }
        }
        .animation(Motion.glide, value: store.snapshot == nil)
        .toolbar {
            if store.errorMessage != nil, let cli = app.cli {
                ToolbarItem(placement: .automatic) {
                    Button("Retry", systemImage: "arrow.clockwise") { store.retry(cli: cli) }
                }
            }
        }
    }
}

private struct StatusDashboard: View {
    let store: StatusStore
    let snapshot: StatusSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.cluster) {
                HealthStrip(snapshot: snapshot, sampleID: store.sampleCount, isLive: store.isRunning && store.errorMessage == nil)
                    .arrives()
                if let message = store.errorMessage {
                    InlineNotice(text: message)
                }
                Grid(horizontalSpacing: Theme.Space.cluster, verticalSpacing: Theme.Space.cluster) {
                    GridRow {
                        CPUCard(snapshot: snapshot, store: store).arrives(index: 1)
                        MemoryCard(snapshot: snapshot, store: store).arrives(index: 2)
                        NetworkCard(snapshot: snapshot, store: store).arrives(index: 3)
                    }
                    GridRow {
                        DiskCard(snapshot: snapshot).arrives(index: 4)
                        GPUCard(snapshot: snapshot).arrives(index: 5)
                        PowerCard(snapshot: snapshot).arrives(index: 6)
                    }
                }
                if let bluetooth = snapshot.bluetooth, bluetooth.contains(where: { $0.connected == true }) {
                    BluetoothCard(devices: bluetooth)
                        .arrives(index: 7)
                        .transition(Motion.rise)
                }
                ProcessCard(snapshot: snapshot).arrives(index: 8)
            }
            .padding(Theme.Space.page)
        }
    }
}

/// A small dot that pulses when a sample actually arrives, so it means "this is fresh".
private struct LiveDot: View {
    let sampleID: Int

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .keyframeAnimator(initialValue: PulseValues(), trigger: sampleID) { dot, values in
                dot
                    .background {
                        Circle()
                            .stroke(.green.opacity(values.ring), lineWidth: 1.5)
                            .scaleEffect(values.scale)
                    }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    CubicKeyframe(Motion.isReduced ? 1 : 2.6, duration: 0.9)
                }
                KeyframeTrack(\.ring) {
                    LinearKeyframe(Motion.isReduced ? 0 : 0.7, duration: 0.01)
                    CubicKeyframe(0, duration: 0.9)
                }
            }
            // The slot is as wide as the ring at its largest, so the pulse never touches
            // the word beside it.
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private struct PulseValues {
        var scale: CGFloat = 1
        var ring: Double = 0
    }
}

private struct HealthStrip: View {
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
                            LiveDot(sampleID: sampleID)
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

private struct CardTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline)
            .bold()
            .foregroundStyle(.secondary)
    }
}

private struct ValueLine: View {
    let value: String
    let unit: String
    var number: Double = 0

    var body: some View {
        // The unit sits snug against the figure in the same rounded face, so "27%" reads
        // as one value rather than a number and a stray sign.
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: number))
                .animation(Motion.snap, value: value)
            Text(unit)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PercentReadout: View {
    let percent: Double

    var body: some View {
        if (0...100).contains(percent) {
            ValueLine(value: percent.formatted(.number.precision(.fractionLength(0))), unit: "%", number: percent)
        } else {
            ValueLine(value: "—", unit: "")
        }
    }
}

private struct CPUCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                CardTitle(title: "CPU", symbol: "cpu")
                PercentReadout(percent: snapshot.cpu?.usage ?? 0)
                Sparkline(values: store.cpuHistory, sampleID: store.sampleCount, maximum: 100)
                if let perCore = snapshot.cpu?.perCore, !perCore.isEmpty {
                    CoreBars(values: perCore)
                }
                Text("Load \(String(format: "%.2f", snapshot.cpu?.load1 ?? 0)) · \(snapshot.cpu?.coreCount ?? 0) cores")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(values.enumerated(), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .fill(Color.accentColor.opacity(0.45 + min(value, 100) / 100 * 0.55))
                    .frame(height: max(22 * min(value, 100) / 100, 2))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .animation(Motion.snap, value: values)
        .accessibilityHidden(true)
    }
}

private struct MemoryCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        let memory = snapshot.memory
        return Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                CardTitle(title: "Memory", symbol: "memorychip")
                PercentReadout(percent: memory?.usedPercent ?? 0)
                Sparkline(values: store.memoryHistory, sampleID: store.sampleCount, tint: .blue, maximum: 100)
                Text("\((memory?.used ?? 0).memorySize) of \((memory?.total ?? 0).memorySize) · \((memory?.swapUsed ?? 0).memorySize) swap")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetworkCard: View {
    let snapshot: StatusSnapshot
    let store: StatusStore

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                CardTitle(title: "Network", symbol: "network")
                HStack(spacing: Theme.Space.wide) {
                    RateTile(label: "Down", symbol: "arrow.down", rate: snapshot.totalDownload)
                    RateTile(label: "Up", symbol: "arrow.up", rate: snapshot.totalUpload)
                }
                Sparkline(values: store.downloadHistory, sampleID: store.sampleCount, tint: .green)
                if let address = snapshot.network?.first(where: { !($0.ip ?? "").isEmpty }) {
                    Text("\(address.name ?? "") · \(address.ip ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if snapshot.proxy?.enabled == true {
                    Text("Proxy \(snapshot.proxy?.type ?? "") · \(snapshot.proxy?.host ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RateTile: View {
    let label: String
    let symbol: String
    let rate: Double

    var body: some View {
        let bytes = bytesPerSecond(rate)
        let formatted = bytes?.rate ?? "—"
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
            Text(formatted)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(bytes == nil ? .opacity : .numericText(value: rate))
                .animation(Motion.snap, value: formatted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct DiskCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                CardTitle(title: "Disk", symbol: "internaldrive")
                ForEach(snapshot.disks ?? [], id: \.mount) { disk in
                    DiskRow(disk: disk)
                }
                Text("Read \(rate(snapshot.diskIo?.readRate)) · Write \(rate(snapshot.diskIo?.writeRate))")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let trash = snapshot.trashSize, trash > 0 {
                    Text("Trash holds \(trash.fileSize)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rate(_ megabytesPerSecond: Double?) -> String {
        bytesPerSecond(megabytesPerSecond ?? 0)?.rate ?? "—"
    }
}

private func bytesPerSecond(_ megabytesPerSecond: Double) -> Int64? {
    Int64(exactly: (megabytesPerSecond * 1_048_576).rounded(.towardZero))
}

private struct DiskRow: View {
    let disk: StatusSnapshot.Disk

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text(FileManager.default.displayName(atPath: disk.mount ?? "/"))
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text("\(disk.usedPercent ?? 0, format: .number.precision(.fractionLength(0)))%")
                    .monospacedDigit()
            }
            .font(.callout)
            LevelBar(fraction: (disk.usedPercent ?? 0) / 100, tint: tint)
            Text("\((disk.used ?? 0).fileSize) of \((disk.total ?? 0).fileSize)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var tint: Color {
        switch disk.usedPercent ?? 0 {
        case 90...: .red
        case 75..<90: .orange
        default: .accentColor
        }
    }
}

private struct GPUCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        let gpu = snapshot.gpu?.first
        return Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                CardTitle(title: "GPU", symbol: "display")
                if let usage = gpu?.usage, usage >= 0 {
                    ValueLine(value: String(format: "%.0f", usage), unit: "%", number: usage)
                    LevelBar(fraction: usage / 100, tint: StatusTint.load(usage))
                } else {
                    Text("Usage isn’t reported")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text([gpu?.name, gpu?.coreCount.map { "\($0) cores" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PowerCard: View {
    let snapshot: StatusSnapshot

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                if let battery = snapshot.batteries?.first {
                    CardTitle(title: "Battery", symbol: "battery.75percent")
                    ValueLine(value: String(format: "%.0f", battery.percent ?? 0), unit: "%", number: battery.percent ?? 0)
                    LevelBar(fraction: (battery.percent ?? 0) / 100, tint: StatusTint.battery(percent: battery.percent, status: battery.status))
                    Text(batteryLine(battery))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    CardTitle(title: "Power", symbol: "bolt")
                    ValueLine(
                        value: String(format: "%.1f", snapshot.thermal?.systemPower ?? 0),
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

/// Connected devices, shown only when there are some.
private struct BluetoothCard: View {
    let devices: [StatusSnapshot.Bluetooth]

    private var connected: [StatusSnapshot.Bluetooth] {
        devices.filter { $0.connected == true }
    }

    var body: some View {
        Surface {
            HStack(spacing: Theme.Space.wide) {
                CardTitle(title: "Bluetooth", symbol: "wave.3.right")
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

/// Processes glide to their new positions when the order changes, so you can follow one.
private struct ProcessCard: View {
    let snapshot: StatusSnapshot
    @State private var sortsByMemory = false

    private var sortedProcesses: [StatusSnapshot.Process] {
        let all = snapshot.topProcesses ?? []
        return sortsByMemory
            ? all.sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
            : all.sorted { ($0.cpu ?? 0) > ($1.cpu ?? 0) }
    }

    var body: some View {
        let processes = sortedProcesses
        Surface {
            VStack(alignment: .leading, spacing: Theme.Space.item) {
                HStack {
                    CardTitle(title: "Top Processes", symbol: "list.bullet")
                    Spacer()
                    Picker("Sort Processes By", selection: $sortsByMemory) {
                        Text("CPU").tag(false)
                        Text("Memory").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                ProcessHeaderRow()
                // Rows update in place, as in Activity Monitor. This table reorders every
                // couple of seconds, and sliding or fading rows smeared names across each
                // other mid-move.
                VStack(spacing: Theme.Space.snug) {
                    ForEach(processes) { ProcessRow(process: $0) }
                }
                .transaction { $0.animation = nil }
            }
        }
    }
}

private struct ProcessHeaderRow: View {
    var body: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 70, alignment: .trailing)
            Text("Memory")
                .frame(width: 84, alignment: .trailing)
            Text("PID")
                .frame(width: 60, alignment: .trailing)
        }
        .font(.subheadline)
        .bold()
        .foregroundStyle(.secondary)
    }
}

private struct ProcessRow: View {
    let process: StatusSnapshot.Process

    var body: some View {
        HStack {
            Text(process.name ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
                .help(process.command ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.1f%%", process.cpu ?? 0))
                .foregroundStyle((process.cpu ?? 0) > 50 ? Color.orange : Color.primary)
                .frame(width: 70, alignment: .trailing)
            Text((process.memoryBytes ?? 0).memorySize)
                .frame(width: 84, alignment: .trailing)
            Text("\(process.pid ?? 0)")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}
