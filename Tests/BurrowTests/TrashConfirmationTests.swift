import BurrowCore
import Foundation
import Testing
@testable import Burrow

@MainActor
struct TrashConfirmationTests {
    private func entry(_ name: String, path: String) throws -> AnalyzeResult.Entry {
        let json = try JSONSerialization.data(withJSONObject: [
            "path": "/Users/me",
            "entries": [[
                "name": name,
                "path": path,
                "size": 1024,
                "is_dir": true,
            ]],
        ])
        let result = try AnalyzeResult.decode(json)
        return try #require(result.entries?.first)
    }

    @Test func singleItemTitleOmitsRiskyListAndIncludesReason() throws {
        let item = try entry(".ssh", path: "/Users/me/.ssh")
        let confirmation = TrashConfirmation(
            selected: [item],
            risks: [item.path: .credentials]
        )
        #expect(confirmation.paths == [item.path])
        #expect(confirmation.title == "Move “.ssh” to the Trash?")
        #expect(!confirmation.message.contains("Check these first:"))
        #expect(confirmation.message.contains("Keys and passwords kept here sign you in to other services."))
        #expect(confirmation.message.hasSuffix("You can put items back from the Trash."))
    }

    @Test func multiItemCapsRiskyNamesAtThreeAndSummarizesOverflow() throws {
        let items = [
            try entry("safe.txt", path: "/Users/me/Downloads/safe.txt"),
            try entry(".ssh", path: "/Users/me/.ssh"),
            try entry("iCloud", path: "/Users/me/Library/Mobile Documents"),
            try entry("AppSupport", path: "/Users/me/Library/Application Support"),
            try entry("Desktop", path: "/Users/me/Desktop"),
        ]
        let risks: [String: TrashRisk.Reason] = [
            items[1].path: .credentials,
            items[2].path: .iCloud,
            items[3].path: .appData,
            items[4].path: .topLevelFolder,
        ]

        let confirmation = TrashConfirmation(selected: items, risks: risks)
        #expect(confirmation.title == "Move 5 Items to the Trash?")
        #expect(confirmation.message.contains("Check these first: .ssh, iCloud, AppSupport, and 1 more."))
        #expect(!confirmation.message.contains("Desktop"))
        #expect(!confirmation.message.contains("safe.txt"))
    }

    @Test func reasonsFollowAllCasesOrderAndAreDeduplicated() throws {
        let items = [
            try entry("b", path: "/etc/b"),
            try entry("a", path: "/Users/me/.ssh"),
            try entry("a2", path: "/Users/me/.aws"),
            try entry("c", path: "/Users/me/Library/Mobile Documents"),
        ]
        let risks: [String: TrashRisk.Reason] = [
            items[0].path: .outsideHome,
            items[1].path: .credentials,
            items[2].path: .credentials,
            items[3].path: .iCloud,
        ]

        let confirmation = TrashConfirmation(selected: items, risks: risks)
        let credentialsText = "Keys and passwords kept here sign you in to other services."
        let iCloudText = "Items in iCloud are also removed from your other devices."
        let outsideText = "Items outside your home folder may be needed by other apps or accounts."

        let credRange = confirmation.message.range(of: credentialsText)
        let iCloudRange = confirmation.message.range(of: iCloudText)
        let outsideRange = confirmation.message.range(of: outsideText)

        #expect(credRange != nil)
        #expect(iCloudRange != nil)
        #expect(outsideRange != nil)
        if let credRange, let iCloudRange, let outsideRange {
            #expect(credRange.lowerBound < iCloudRange.lowerBound)
            #expect(iCloudRange.lowerBound < outsideRange.lowerBound)
        }

        // Duplicate .credentials entries must only explain credentials once.
        let occurrences = confirmation.message.components(separatedBy: credentialsText).count - 1
        #expect(occurrences == 1)
    }
}
