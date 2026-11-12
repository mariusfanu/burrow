import BurrowCore
import Foundation

/// The question to ask before a selection that includes a high-risk item goes to the Trash.
struct TrashConfirmation: Equatable {
    let paths: Set<String>
    let title: String
    let message: String

    init(selected: [AnalyzeResult.Entry], risks: [String: TrashRisk.Reason]) {
        paths = Set(selected.map(\.path))
        let risky = selected.filter { risks[$0.path] != nil }
        title = selected.count == 1
            ? "Move “\(selected[0].name)” to the Trash?"
            : "Move \(selected.count) Items to the Trash?"

        var parts: [String] = []
        if selected.count > 1 {
            let names = risky.prefix(3).map(\.name).joined(separator: ", ")
            let extra = risky.count > 3 ? ", and \(risky.count - 3) more" : ""
            parts.append("Check these first: \(names)\(extra).")
        }
        let reasons = Set(risky.compactMap { risks[$0.path] })
        parts += TrashRisk.Reason.allCases.filter(reasons.contains).map(Self.explanation)
        parts.append("You can put items back from the Trash.")
        message = parts.joined(separator: " ")
    }

    private static func explanation(of reason: TrashRisk.Reason) -> String {
        switch reason {
        case .credentials: "Keys and passwords kept here sign you in to other services."
        case .iCloud: "Items in iCloud are also removed from your other devices."
        case .appData: "Apps keep settings and data here, and may stop working without them."
        case .topLevelFolder: "A folder at the top of your home goes with everything in it."
        case .outsideHome: "Items outside your home folder may be needed by other apps or accounts."
        }
    }
}
