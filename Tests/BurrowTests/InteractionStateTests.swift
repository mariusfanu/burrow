import Testing
@testable import Burrow

@MainActor
struct InteractionStateTests {
    @Test func aRealizedRowStaysVisibleWhenSortingMovesItIntoTheEntranceWave() {
        var arrival = ArrivalState()
        #expect(arrival.isVisible(at: 25))
        arrival.appear()
        // Stable row identity keeps this state when measurements move it near the top.
        #expect(arrival.isVisible(at: 3))
        #expect(arrival.isVisible(at: 0))
        arrival.appear()
        #expect(arrival.isVisible(at: 16))
    }

    @Test func contentGrowthDoesNotCancelFollowingButUserScrollingDoes() {
        var follow = LogFollowState()
        follow.updateViewport(offset: 400, contentHeight: 1000, viewportHeight: 600)
        #expect(follow.isFollowing)
        // New output extends the content before the view can scroll to its new bottom.
        follow.updateViewport(offset: 400, contentHeight: 1200, viewportHeight: 600)
        #expect(follow.isFollowing)
        follow.updateViewport(offset: 600, contentHeight: 1200, viewportHeight: 600)
        follow.userScrolling(true)
        follow.updateViewport(offset: 200, contentHeight: 1200, viewportHeight: 600)
        follow.userScrolling(false)
        #expect(!follow.isFollowing)
        follow.updateViewport(offset: 200, contentHeight: 1600, viewportHeight: 600)
        #expect(!follow.isFollowing)
        follow.jumpToLatest()
        #expect(follow.isFollowing)
    }

    @Test func scrollingBackToTheBottomResumesFollowing() {
        var follow = LogFollowState()
        follow.updateViewport(offset: 500, contentHeight: 1000, viewportHeight: 500)
        follow.userScrolling(true)
        follow.updateViewport(offset: 150, contentHeight: 1000, viewportHeight: 500)
        #expect(!follow.isFollowing)
        follow.updateViewport(offset: 500, contentHeight: 1000, viewportHeight: 500)
        follow.userScrolling(false)
        #expect(follow.isFollowing)
    }

    @Test func keyboardScrollAwayAndReturnDoNotNeedATrackpadPhase() {
        var follow = LogFollowState()
        follow.finishSettling()
        follow.updateViewport(offset: 500, contentHeight: 1000, viewportHeight: 500)
        follow.updateViewport(offset: 100, contentHeight: 1000, viewportHeight: 500, movedUp: true)
        #expect(!follow.isFollowing)
        follow.updateViewport(offset: 100, contentHeight: 1200, viewportHeight: 500)
        #expect(!follow.isFollowing)
        follow.updateViewport(offset: 700, contentHeight: 1200, viewportHeight: 500)
        #expect(follow.isFollowing)
    }
}
