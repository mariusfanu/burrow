import Foundation

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
