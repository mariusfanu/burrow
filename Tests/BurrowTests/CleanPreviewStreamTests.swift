import Foundation
import Testing
import BurrowCore
@testable import Burrow

struct CleanPreviewStreamTests {
    @Test func completionFlushesEveryChunkTailAndPathList() async throws {
        let folder = URL(fileURLWithPath: TestScratch.root).appendingPathComponent("burrow-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let list = folder.appendingPathComponent("clean-list.txt")
        try "=== Caches ===\n/tmp/cache  # 2MB\n".write(to: list, atomically: true, encoding: .utf8)
        let stream = CleanPreviewStream()
        stream.append(Data("➤ Caches\n".utf8))
        for index in 0..<1000 { stream.append(Data("  ○ item \(index) · 2MB dry\n".utf8)) }
        stream.append(Data("Potential space: 2GB · 1000 items".utf8))
        let report = await stream.finish(pathListURL: list)
        #expect(report.sections[0].rows.count == 1000)
        #expect(report.sections[0].paths.map(\.path) == ["/tmp/cache"])
        #expect(report.itemCount == 1000)
        #expect(report.potentialBytes == 2_000_000_000)
        var latest: CleanReport?
        for await update in stream.updates { latest = update }
        #expect(latest == report)
    }

    @Test func rapidInputOnlyBuffersTheNewestPublishedReport() async throws {
        let stream = CleanPreviewStream()
        stream.append(Data("➤ Caches\n  ○ first · 1MB dry\n".utf8))
        try await Task.sleep(for: .milliseconds(150))
        stream.append(Data("  ○ second · 2MB dry\n".utf8))
        let final = await stream.finish(pathListURL: URL(fileURLWithPath: "/nonexistent/burrow-list"))
        var updates: [CleanReport] = []
        for await update in stream.updates { updates.append(update) }
        #expect(updates == [final])
        #expect(final.sections[0].rows.map(\.title) == ["first", "second"])
    }

    @Test func cancellationClosesUpdatesAndRefusesLateChunks() async {
        let stream = CleanPreviewStream()
        stream.cancel()
        stream.append(Data("➤ Late\n  ○ unwanted · 99GB dry\n".utf8))
        var updates: [CleanReport] = []
        for await update in stream.updates { updates.append(update) }
        #expect(updates.isEmpty)
    }
}
