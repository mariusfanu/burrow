import BurrowCore
import SwiftUI

extension RunController {
    var completionSymbol: String {
        if wasDeclined { return "xmark.circle" }
        if wasCancelled { return "stop.circle" }
        return didSucceed ? "checkmark.circle" : "xmark.circle"
    }

    var completionTint: Color {
        if wasCancelled || wasDeclined { return .secondary }
        return didSucceed ? .green : .red
    }

    var completionHeadline: String {
        if wasDeclined { return "Cancelled" }
        if wasCancelled { return "Stopped" }
        return didSucceed ? doneTitle : "Couldn’t Finish"
    }

    var completionBannerHeadline: String {
        if let summary = summary, didSucceed {
            return summary.isEstimate ? "\(summary.bytes.fileSize) would be freed" : "\(summary.bytes.fileSize) freed"
        }
        return completionHeadline
    }

    var completionDetail: String {
        if wasDeclined { return "Nothing was changed." }
        if wasCancelled { return "Anything already finished stays finished." }
        switch phase {
        case .failedToStart:
            return "The command couldn’t start."
        case .finished(let status) where status != 0:
            return "The command ended with status \(status). The log has the details."
        default:
            let time = Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 2))
            return "Finished in \(time)."
        }
    }
}
