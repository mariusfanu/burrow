/// Tracks a row's first appearance independently of its changing sort position.
struct ArrivalState: Equatable {
    static let waveLimit = 16

    private(set) var hasArrived = false

    func isVisible(at index: Int) -> Bool { hasArrived || index > Self.waveLimit }

    mutating func appear() { hasArrived = true }
}
