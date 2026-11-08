/// Tracks a row's first appearance independently of its changing sort position.
struct ArrivalState: Equatable {
    private(set) var hasArrived = false

    func isVisible(at index: Int) -> Bool { hasArrived || index > 16 }

    mutating func appear() { hasArrived = true }
}
