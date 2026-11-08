import Foundation
import IOKit

/// One GPU's current activity, as published in the IOKit registry.
public struct GPUReading: Sendable, Equatable {
    public var model: String?
    /// Percent busy, from 0 to 100.
    public var utilization: Double

    public init(model: String?, utilization: Double) {
        self.model = model
        self.utilization = utilization
    }

    /// Returns `nil` when the statistics have no usable utilization figure.
    init?(model: String?, performanceStatistics: [String: Any]) {
        guard let value = (performanceStatistics["Device Utilization %"] as? NSNumber)?.doubleValue,
              (0...100).contains(value)
        else { return nil }
        self.init(model: model, utilization: value)
    }
}

/// Reads GPU activity directly from macOS, for when `mo status` has no figure.
///
/// `PerformanceStatistics` isn't a documented API, so a GPU that doesn't publish it,
/// or a macOS release that changes it, produces no reading rather than a wrong one.
public enum GPUStatistics {
    public static func read() -> [GPUReading] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var readings: [GPUReading] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = property("PerformanceStatistics", of: service) as? [String: Any],
                  let reading = GPUReading(model: property("model", of: service) as? String, performanceStatistics: statistics)
            else { continue }
            readings.append(reading)
        }
        return readings
    }

    private static func property(_ key: String, of service: io_object_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

extension StatusSnapshot {
    /// Fills in usage for GPUs the CLI has no figure for, which it reports as a negative number.
    ///
    /// `readings` only runs when a GPU needs it. A reading is used when its model matches the GPU's
    /// name, or when there's only one GPU and one reading, so usage is never shown for the wrong GPU.
    public func fillingMissingGPUUsage(from readings: () -> [GPUReading]) -> StatusSnapshot {
        guard let gpus = gpu, gpus.contains(where: \.isMissingUsage) else { return self }
        let current = readings()
        var filled = self
        for index in gpus.indices where gpus[index].isMissingUsage {
            let onlyReading = gpus.count == 1 && current.count == 1 ? current.first : nil
            let reading = current.first { $0.model != nil && $0.model == gpus[index].name } ?? onlyReading
            if let reading { filled.gpu?[index].usage = reading.utilization }
        }
        return filled
    }
}

private extension StatusSnapshot.GPU {
    var isMissingUsage: Bool { (usage ?? -1) < 0 }
}
