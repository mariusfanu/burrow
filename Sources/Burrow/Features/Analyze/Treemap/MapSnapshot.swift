import BurrowCore
import Foundation

/// What a map layer shows, captured so that the outgoing layer stays still while it leaves.
struct MapSnapshot: Equatable {
    let id: String
    let name: String
    let tint: UInt32?
    let entries: [AnalyzeResult.Entry]
    let isLoading: Bool
}
