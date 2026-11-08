import Foundation
import Testing
@testable import BurrowCore

struct CleanReportParserTests {
    @Test func chunkBoundariesPreserveUnicodeANSIRedrawsAndFinalSummary() throws {
        let output = "\u{1B}[35m➤ User caches\u{1B}[0m\n  ○ 名前 · 12.3MB dry\n\r⠴ Scanning\r\u{1B}[2K\r\n➤ Other\n  ✓ Nothing to clean\nPotential space: 12.3MB · 1 item"
        let pathList = "=== User caches ===\n/tmp/big  # 10MB\n/tmp/small  # 1KB\n"
        let expected = CleanReport.parse(preview: output, pathList: pathList)
        for chunkSize in [1, 2, 5, 17, 256] {
            var parser = CleanReportParser()
            let data = Array(output.utf8)
            for start in stride(from: 0, to: data.count, by: chunkSize) {
                parser.feed(Data(data[start..<min(start + chunkSize, data.count)]))
            }
            let report = parser.finish(pathList: pathList)
            #expect(report == expected)
            #expect(report.sections.map(\.name) == ["User caches", "Other"])
            #expect(report.sections[0].rows.map(\.title) == ["名前"])
            #expect(report.sections[0].paths.map(\.path) == ["/tmp/big", "/tmp/small"])
            #expect(report.potentialBytes == 12_300_000)
            #expect(report.itemCount == 1)
            #expect(report.sections[1].isEmpty)
            #expect(parser.finish(pathList: pathList) == report)
        }
    }

    @Test func publishedSnapshotsStayImmutableAsMoreRowsArrive() throws {
        var parser = CleanReportParser()
        parser.feed(Data("◎ Skip system caches\n➤ First\n  ○ one · 1MB dry\n".utf8))
        let first = parser.snapshot
        parser.feed(Data("  ○ two · 2MB dry\n➤ Second\n  ○ three · 3MB dry\n".utf8))
        let final = parser.finish()
        #expect(first.sections.count == 1)
        #expect(first.sections[0].rows.map(\.title) == ["one"])
        #expect(final.sections.count == 2)
        #expect(final.sections[0].rows.map(\.title) == ["one", "two"])
        #expect(Set(final.sections.flatMap(\.rows).map(\.id)).count == 3)
        #expect(final.notes == ["Skip system caches"])
    }

    @Test func finalTailIsConsumedOnceAndLateOutputIsIgnored() {
        var parser = CleanReportParser()
        parser.feed(Data("➤ First\n  ○ one · 1MB dry".utf8))
        #expect(parser.snapshot.sections[0].rows.isEmpty)
        let report = parser.finish()
        #expect(report.sections[0].rows.count == 1)
        parser.feed(Data("\n➤ Late\n  ○ old · 99GB dry\n".utf8))
        #expect(parser.finish() == report)
    }

    @Test func unfinishedPlainDetailRetainsItsIndentation() {
        var parser = CleanReportParser()
        parser.feed(Data("➤ Caches\n  unfinished detail".utf8))
        let report = parser.finish()
        #expect(report.sections[0].rows.map(\.title) == ["unfinished detail"])
        #expect(report.sections[0].rows.first?.kind == .plain)
    }

    @Test func aSectionTotalsOnlyItsPreviewRows() {
        let report = CleanReport.parse(preview: "➤ First\n  ○ one · 1MB dry\n  ✓ done · 5MB\n  ○ two · 2MB dry\n  ○ no size\n", pathList: nil)
        #expect(report.sections[0].bytes == 3_000_000)
        #expect(report.potentialBytes == 3_000_000)
    }
}
