import Foundation

/// One sample from `mo status --json` or `mo status --watch`.
///
/// Every field is optional so a newer CLI that adds or drops a field keeps decoding.
public struct StatusSnapshot: Decodable, Sendable, Equatable {
    public struct Hardware: Decodable, Sendable, Equatable {
        public var model: String?
        public var cpuModel: String?
        public var osVersion: String?
    }

    public struct CPU: Decodable, Sendable, Equatable {
        public var usage: Double?
        public var perCore: [Double]?
        public var load1: Double?
        public var coreCount: Int?
        public var pCoreCount: Int?
    }

    public struct GPU: Decodable, Sendable, Equatable {
        public var name: String?
        public var usage: Double?
        public var coreCount: Int?
    }

    public struct Memory: Decodable, Sendable, Equatable {
        public var used: Int64?
        public var total: Int64?
        public var usedPercent: Double?
        public var swapUsed: Int64?
    }

    public struct Disk: Decodable, Sendable, Equatable, Identifiable {
        public var id: String { mount ?? "" }

        public var mount: String?
        public var used: Int64?
        public var total: Int64?
        public var usedPercent: Double?
    }

    public struct DiskIO: Decodable, Sendable, Equatable {
        public var readRate: Double?
        public var writeRate: Double?
    }

    public struct Network: Decodable, Sendable, Equatable {
        public var name: String?
        public var rxRateMbs: Double?
        public var txRateMbs: Double?
        public var ip: String?
    }

    public struct Proxy: Decodable, Sendable, Equatable {
        public var enabled: Bool?
        public var type: String?
        public var host: String?
    }

    public struct Battery: Decodable, Sendable, Equatable {
        public var percent: Double?
        public var status: String?
        public var timeLeft: String?
        public var health: String?
        public var cycleCount: Int?
    }

    public struct Thermal: Decodable, Sendable, Equatable {
        public var cpuTemp: Double?
        public var gpuTemp: Double?
        public var fanSpeed: Int?
        public var fanCount: Int?
        public var systemPower: Double?
    }

    public struct Bluetooth: Decodable, Sendable, Equatable, Identifiable {
        public var name: String?
        public var connected: Bool?
        public var battery: String?
        public var id: String { name ?? "" }
    }

    public struct Process: Decodable, Sendable, Equatable, Identifiable {
        public var pid: Int?
        public var name: String?
        public var command: String?
        public var cpu: Double?
        public var memory: Double?
        public var memoryBytes: Int64?
        public var id: Int { pid ?? 0 }
    }

    public var host: String?
    public var uptime: String?
    public var procs: Int?
    public var hardware: Hardware?
    public var healthScore: Int?
    public var healthScoreMsg: String?
    public var cpu: CPU?
    public var gpu: [GPU]?
    public var memory: Memory?
    public var disks: [Disk]?
    public var trashSize: Int64?
    public var diskIo: DiskIO?
    public var network: [Network]?
    public var proxy: Proxy?
    public var batteries: [Battery]?
    public var thermal: Thermal?
    public var bluetooth: [Bluetooth]?
    public var topProcesses: [Process]?
    public var zombieCount: Int?

    public static func decode(_ data: Data) throws -> StatusSnapshot {
        try decode(data, using: JSONDecoder.forCLI())
    }

    static func decode(_ data: Data, using decoder: JSONDecoder) throws -> StatusSnapshot {
        try decoder.decode(StatusSnapshot.self, from: data)
    }

    var containsReadings: Bool {
        host != nil || uptime != nil || procs != nil || hardware != nil || healthScore != nil
            || healthScoreMsg != nil || cpu != nil || gpu != nil || memory != nil || disks != nil
            || trashSize != nil || diskIo != nil || network != nil || proxy != nil || batteries != nil
            || thermal != nil || bluetooth != nil || topProcesses != nil || zombieCount != nil
    }

    public var totalDownload: Double {
        (network ?? []).compactMap(\.rxRateMbs).reduce(0, +)
    }

    public var totalUpload: Double {
        (network ?? []).compactMap(\.txRateMbs).reduce(0, +)
    }

    public var rootDisk: Disk? {
        disks?.first { $0.mount == "/" } ?? disks?.first
    }
}
