import BurrowCore
import Foundation
import Testing
@testable import Burrow

struct HistoryPresentationTests {
    private func session(_ json: String) throws -> HistoryReport.Session {
        let report = try HistoryReport.decode(Data(#"{"sessions":[\#(json)]}"#.utf8))
        return try #require(report.sessions?.first)
    }

    @Test func commandsReadAsPageNames() throws {
        #expect(try session(#"{"command":"installer"}"#).title == "Installers")
        #expect(try session(#"{"command":"analyze"}"#).title == "Disk Explorer")
        #expect(try session(#"{"command":"touchid"}"#).title == "Touch ID")
        #expect(try session(#"{"command":"purge-dry-run"}"#).title == "Project Purge")
        #expect(try session(#"{"command":"something-new"}"#).title == "Something-New")
    }

    @Test func commandSymbolsComeFromTheExactPage() throws {
        #expect(try session(#"{"command":"clean"}"#).symbol == "sparkles")
        #expect(try session(#"{"command":"installer"}"#).symbol == "shippingbox")
        #expect(try session(#"{"command":"touchid"}"#).symbol == "touchid")
        #expect(try session(#"{"command":"something-new"}"#).symbol == "terminal")
        #expect(try session(#"{"command":""}"#).symbol == "terminal")
    }

    @Test func emptyColumnsStayEmptyAndCountsInflect() throws {
        let nothing = try session(#"{"command":"update","items":0,"size":"0B"}"#)
        #expect(nothing.sizeText == nil)
        #expect(nothing.itemsText == nil)

        let one = try session(#"{"command":"optimize","items":1,"size":"0B"}"#)
        #expect(one.itemsText.map { String($0.characters) } == "1 item")

        let many = try session(#"{"command":"clean","items":1974,"size":"15.74GB","actions":{"removed":2145,"skipped":271}}"#)
        #expect(many.sizeText != nil)
        #expect(many.actionSummary.contains("2,145 removed") || many.actionSummary.contains("2.145 removed") || many.actionSummary.contains("2 145 removed"))
    }

    @Test func historyDateParsesAllCLITimestampFormats() throws {
        #expect(HistoryDate.parse("2026-11-01 23:39:10") != nil)
        let compact = try #require(HistoryDate.parse("2026-11-01T23:39:10+0200"))
        let separated = try #require(HistoryDate.parse("2026-11-01T23:39:10+02:00"))
        #expect(compact == separated)
        #expect(HistoryDate.parse("sometime") == nil)
    }

    @Test func timestampsBecomeDatesAndUnreadableOnesStayAsWritten() throws {
        let dated = try session(#"{"command":"clean","started_at":"2026-11-05 00:00:39"}"#)
        let date = try #require(dated.startedDate)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .second], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 5 && parts.hour == 0 && parts.second == 39)

        let odd = try session(#"{"command":"clean","started_at":"sometime"}"#)
        #expect(odd.startedText == "sometime")
    }
}
