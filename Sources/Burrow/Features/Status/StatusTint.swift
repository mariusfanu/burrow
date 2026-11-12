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

    static func disk(_ percent: Double) -> Color {
        switch percent {
        case 90...: .red
        case 75..<90: .orange
        default: .accentColor
        }
    }
}
