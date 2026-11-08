import Foundation

/// Content growth must not be mistaken for someone scrolling away from the log.
struct LogFollowState: Equatable {
    private(set) var isFollowing = true
    private(set) var isAtBottom = true
    private var isUserScrolling = false
    /// A lazy list's first layouts move the offset while it replaces estimated row heights.
    private var isSettling = true

    mutating func updateViewport(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, movedUp: Bool = false) {
        isAtBottom = contentHeight - viewportHeight - offset <= 24
        if isAtBottom {
            isFollowing = true
        } else if isUserScrolling || (movedUp && !isSettling) {
            isFollowing = false
        }
    }

    /// Layout has settled, so upward movement from now on means someone scrolled.
    mutating func finishSettling() { isSettling = false }

    mutating func userScrolling(_ active: Bool) {
        isUserScrolling = active
        if active {
            isSettling = false
            isFollowing = isAtBottom
        } else if isAtBottom {
            isFollowing = true
        }
    }

    mutating func jumpToLatest() { isFollowing = true }
}

struct LogViewport: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}
