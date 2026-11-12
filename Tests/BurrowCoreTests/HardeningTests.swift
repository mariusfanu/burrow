import Foundation
import Testing
@testable import BurrowCore

/// Output a CLI could print through a file name must never bring the app down.
struct OutputHardeningTests {
    @Test(arguments: [
        "a\r\nb\u{1B}[9223372036854775807B",
        "\u{1B}[-9223372036854775808G",
        "\u{1B}[9223372036854775807C",
        "\u{1B}[9223372036854775807;9223372036854775807H",
        "\u{1B}[99999999999999999999999A",
    ])
    func hugeCursorParametersStayOnScreen(sequence: String) {
        var screen = TerminalScreen(rows: 10, columns: 40)
        screen.feed(Data(sequence.utf8))
        // The screen keeps working: the cursor is on it, wherever the sequence sent it.
        screen.feed(Data("\u{1B}[Hstill here".utf8))
        #expect(screen.lines.contains { $0.contains("still here") })
    }

    @Test(arguments: ["\u{FEFF}", "\u{00AD}", "\u{200B}"])
    func aMarkAfterAFormatCharacterIsDropped(format: String) {
        var screen = TerminalScreen(rows: 5, columns: 40)
        screen.feed(Data("x\(format)\u{0301}y".utf8))
        #expect(screen.lines[0].contains("y"))
    }

    @Test func aMarkStillJoinsAnOrdinaryLetter() {
        var screen = TerminalScreen(rows: 5, columns: 40)
        screen.feed(Data("e\u{0301}".utf8))
        #expect(screen.lines[0].hasPrefix("e\u{0301}"))
    }

    @Test func hugeSizesSaturateInsteadOfTrapping() {
        #expect(SizeText.bytes(from: "x · 10000000TB") == Int64.max)
        #expect(SizeText.bytes(from: "10TB") == 10_000_000_000_000)
        #expect(LogLine(id: 0, raw: "  ○ x · 10000000TB").bytes == Int64.max)
    }

    @Test func sumsSaturate() {
        #expect([Int64.max, Int64.max, 5].saturatingSum == Int64.max)
        #expect([Int64(2), 3].saturatingSum == 5)
        #expect([Int64]().saturatingSum == 0)
    }

    @Test func rowsThatCantBeToldApartAppearOnce() throws {
        let json = """
        [{"name":"A","uninstall_name":"Same"},{"name":"B","uninstall_name":"Same"},
         {"name":"C","uninstall_name":"Same","path":"/Applications/C.app"}]
        """
        let apps = try InstalledApp.decodeList(Data(json.utf8))
        #expect(apps.map(\.name) == ["A", "C"])
    }
}

struct CleanReportTrashTests {
    private func report(_ rows: String) -> CleanReport {
        CleanReport.parse(preview: "➤ User essentials\n\(rows)\n", pathList: nil)
    }

    @Test func aPreviewThatWouldEmptyTheTrashSaysSo() {
        #expect(report("  ○ Trash · would empty, 3 items").emptiesTrash)
    }

    @Test func otherRowsDoNotCount() {
        #expect(!report("  ○ User app cache · 2MB").emptiesTrash)
        #expect(!report("  ⚠ Trash · skipped, grant Full Disk Access to your terminal").emptiesTrash)
    }
}

struct CLICompatibilityTests {
    @Test(arguments: [
        ("1.69.0", CLICompatibility.checked),
        ("1.69", .checked),
        ("v1.69.0", .checked),
        ("1.69.1", .newer),
        ("1.70.0", .newer),
        ("2.0", .newer),
        ("1.68.9", .older),
        ("nightly-abc", .unknown),
        ("", .unknown),
    ])
    func comparesNumerically(version: String, expected: CLICompatibility) {
        #expect(CLICompatibility(version: version, checkedVersion: "1.69.0") == expected)
    }

    @Test func onlyADifferenceProducesAWarning() {
        #expect(CLICompatibility.checked.warning(version: "1.69.0") == nil)
        #expect(CLICompatibility.newer.warning(version: "9.0")?.contains("9.0") == true)
        #expect(CLICompatibility.unknown.warning(version: "x") != nil)
    }
}

struct CLITrustTests {
    private func makeFile(mode: Int) throws -> String {
        let path = TestScratch.root + "burrow-trust-" + UUID().uuidString
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        return path
    }

    @Test func aProgramOnlyItsOwnerCanChangeIsAccepted() throws {
        #expect(CLILocator.isSafeToRun(try makeFile(mode: 0o755)))
    }

    @Test(arguments: [0o775, 0o757, 0o777])
    func aProgramOthersCanChangeIsSkipped(mode: Int) throws {
        #expect(!CLILocator.isSafeToRun(try makeFile(mode: mode)))
    }

    @Test func aMissingFileIsSkipped() {
        #expect(!CLILocator.isSafeToRun("/nonexistent/mo"))
    }

    @Test func aTrustedLeafIsRefusedThroughAReplaceableDirectoryOrSymlink() throws {
        let fileManager = FileManager.default
        let folder = URL(fileURLWithPath: TestScratch.root).appendingPathComponent(UUID().uuidString)
        let replaceable = folder.appendingPathComponent("replaceable")
        let leaf = replaceable.appendingPathComponent("mo")
        try fileManager.createDirectory(at: replaceable, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: leaf, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: leaf.path)
        let link = folder.appendingPathComponent("alias")
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "replaceable/mo")
        #expect(CLILocator.isSafeToRun(link.path))
        try fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: replaceable.path)
        #expect(!CLILocator.isSafeToRun(leaf.path))
        #expect(!CLILocator.isSafeToRun(link.path))
    }

    @Test func systemToolsComeFirstOnPath() throws {
        let path = try #require(CLILocator.environment(base: ["PATH": "/evil/bin:/usr/bin"])["PATH"])
        let parts = path.split(separator: ":").map(String.init)
        #expect(Array(parts.prefix(4)) == ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        let sudoDirectory = try #require(parts.firstIndex(of: "/usr/bin"))
        for writable in [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/evil/bin"] {
            #expect(try #require(parts.firstIndex(of: writable)) > sudoDirectory)
        }
    }
}

struct TerminalEscapeHandlingTests {
    private func screen(_ text: String) -> TerminalScreen {
        var screen = TerminalScreen(rows: 5, columns: 20)
        screen.feed(Data(text.utf8))
        return screen
    }

    private func style(after sequence: String) -> CellStyle {
        screen("\u{1B}[1m\(sequence)x").row(0)[0].style
    }

    @Test(arguments: ["\u{1B}[>4;2m", "\u{1B}[?4m", "\u{1B}[=1m", "\u{1B}[<1m"])
    func extensionsAreNotStyles(sequence: String) {
        let found = style(after: sequence)
        #expect(found.bold, "A style reset was applied")
        #expect(!found.dim)
    }

    @Test func aPrefixedRestoreDoesntMoveTheCursor() {
        let screen = screen("abc\u{1B}[<ux")
        #expect(screen.lines[0] == "abcx")
    }

    @Test func sequencesWithIntermediateBytesAreIgnored() {
        #expect(screen("a\u{1B}[2 qb").lines[0] == "ab")
        #expect(screen("abc\u{1B}[!pd").lines[0] == "abcd")
    }

    @Test func colonColorsApplyWithoutResettingTheStyle() {
        let rgb = style(after: "\u{1B}[38:2::1:2:3m")
        #expect(rgb.bold)
        #expect(rgb.foreground == .rgb(1, 2, 3))
        #expect(style(after: "\u{1B}[48:2:4:5:6m").background == .rgb(4, 5, 6))
        #expect(style(after: "\u{1B}[38:5:9m").foreground == .palette(9))
    }

    @Test func colonUnderlineStylesApply() {
        #expect(style(after: "\u{1B}[4:3m").underline)
        #expect(!style(after: "\u{1B}[4m\u{1B}[4:0m").underline)
        #expect(style(after: "\u{1B}[58:2::1:2:3m").bold)
    }

    @Test func leavingTheAlternateScreenAfterAResizeBringsBackWhatWasUnder() {
        var screen = TerminalScreen(rows: 5, columns: 20)
        screen.feed(Data("underneath\u{1B}[?1049hTUI".utf8))
        screen.resize(rows: 8, columns: 30)
        screen.feed(Data("\u{1B}[?1049l".utf8))
        #expect(screen.lines[0] == "underneath")
        #expect(!screen.lines.contains { $0.contains("TUI") })
        screen.feed(Data("!".utf8))
        #expect(screen.lines[0] == "underneath!")
    }

    @Test func aMarkAfterAWideGlyphJoinsIt() {
        let screen = screen("漢\u{0301}")
        #expect(screen.row(0)[0].character == "漢\u{0301}")
        #expect(screen.lines[0] == "漢\u{0301}")
    }

    @Test func aMarkWhileAWrapIsPendingJoinsTheLastGlyph() {
        var screen = TerminalScreen(rows: 3, columns: 3)
        screen.feed(Data("abe\u{0301}".utf8))
        #expect(screen.lines[0] == "abe\u{0301}")
    }

    @Test func overwritingHalfAWideGlyphClearsTheOtherHalf() {
        #expect(screen("漢\rx").lines[0] == "x")
        #expect(screen("a漢\u{1B}[3Gx").lines[0] == "a x")
    }

    @Test(arguments: [0x1FA70, 0x1FAFF, 0x1F200, 0x1F004, 0x1F1E6] as [UInt32])
    func emojiOutsideTheOldRangesAreWide(value: UInt32) throws {
        let character = Character(try #require(Unicode.Scalar(value)))
        #expect(TerminalScreen.displayWidth(of: character) == 2)
    }

    @Test func aWideGlyphFitsAOneColumnScreen() {
        var screen = TerminalScreen(rows: 2, columns: 1)
        screen.feed(Data("漢漢".utf8))
        #expect(screen.lines.joined().contains("漢"))
    }
}

struct TerminalQueryTests {
    private func responses(to text: String, rows: Int = 5) -> String {
        var screen = TerminalScreen(rows: rows, columns: 20)
        screen.feed(Data(text.utf8))
        return String(decoding: screen.takeResponses(), as: UTF8.self)
    }

    @Test func reportsTheCursorPosition() {
        #expect(responses(to: "ab\r\nc\u{1B}[6n") == "\u{1B}[2;2R")
        #expect(responses(to: "\u{1B}[?6n") == "\u{1B}[?1;1R")
    }

    @Test func reportsStatusAndIdentity() {
        #expect(responses(to: "\u{1B}[5n") == "\u{1B}[0n")
        #expect(responses(to: "\u{1B}[c") == "\u{1B}[?1;2c")
        #expect(responses(to: "\u{1B}[0c") == "\u{1B}[?1;2c")
        #expect(responses(to: "\u{1B}[>c") == "\u{1B}[>0;0;0c")
    }

    @Test func reportsColorsWithEitherTerminator() {
        #expect(responses(to: "\u{1B}]11;?\u{07}") == "\u{1B}]11;rgb:1c1c/1c1c/1e1e\u{1B}\\")
        #expect(responses(to: "\u{1B}]10;?\u{1B}\\") == "\u{1B}]10;rgb:f2f2/f2f2/f7f7\u{1B}\\")
    }

    @Test(arguments: ["\u{1B}]0;title\u{07}", "\u{1B}]11;rgb:0/0/0\u{07}", "\u{1B}P11;?\u{1B}\\", "\u{1B}[3n", "plain"])
    func everythingElseGetsNoAnswer(text: String) {
        #expect(responses(to: text).isEmpty)
    }

    @Test func anAnswerIsSentOnce() {
        var screen = TerminalScreen(rows: 5, columns: 20)
        screen.feed(Data("\u{1B}[c".utf8))
        #expect(!screen.takeResponses().isEmpty)
        #expect(screen.takeResponses().isEmpty)
    }

    @Test func noAnswerContainsAReturn() {
        for query in ["\u{1B}[6n", "\u{1B}[5n", "\u{1B}[c", "\u{1B}[>c", "\u{1B}]10;?\u{07}", "\u{1B}]11;?\u{07}"] {
            let answer = responses(to: query)
            #expect(!answer.isEmpty)
            #expect(!answer.contains("\r") && !answer.contains("\n"))
        }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CLITerminalTests {
    private func run(_ script: String) async throws -> (terminal: CLITerminal, lines: () -> [String]) {
        let box = LineBox()
        let terminal = try CLITerminal(executable: "/bin/bash", arguments: ["-c", script], environment: CLILocator.environment())
        terminal.onLine = { box.lines.append($0) }
        return (terminal, { box.lines })
    }

    @MainActor private final class LineBox { var lines: [String] = [] }

    private func finish(_ terminal: CLITerminal) async throws {
        _ = await terminal.waitForExit()
        while terminal.isRunning { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aClosingLineWithNoNewlineIsKept() async throws {
        let (terminal, lines) = try await run("printf 'first\\nSpace freed: 1GB'")
        try await finish(terminal)
        #expect(lines() == ["first", "Space freed: 1GB"])
    }

    @Test func aSpinnerLeftOnScreenIsNotALine() async throws {
        let (terminal, lines) = try await run("printf 'first\\n⠴ Scanning...'")
        try await finish(terminal)
        #expect(lines() == ["first"])
    }

    @Test func aProgramThatAsksTheTerminalGetsAnAnswer() async throws {
        let (terminal, lines) = try await run("""
        stty -echo -icanon
        printf '\\033[6n'
        IFS= read -r -s -d R -t 5 answer || echo TIMEOUT
        echo "got ${answer#*[}"
        """)
        try await finish(terminal)
        #expect(lines().contains("got 1;1"))
        #expect(!lines().contains("TIMEOUT"))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct PTYOutputTests {
    @Test func aFastCommandWaitsForASlowReader() async throws {
        let session = try PTYSession(
            executable: "/usr/bin/yes", arguments: [], environment: CLILocator.environment(),
            lifecycle: ProcessLifecycle(), highWaterMark: 64_000
        )
        defer { session.terminate(grace: 0) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.bufferedByteCount() < 64_000, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let buffered = session.bufferedByteCount()
        #expect(buffered >= 64_000, "Reading should have reached the limit")
        #expect(buffered < 64_000 + 65_536, "Reading should have stopped there")
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.bufferedByteCount() == buffered, "A paused reader must keep buffering bounded")
        session.terminate(grace: 0)
        _ = await session.waitForExit()
    }

    @Test func nothingIsLostToBackpressure() async throws {
        let count = 400_000
        let session = try PTYSession(
            executable: "/bin/sh", arguments: ["-c", "stty -opost; head -c \(count) /dev/zero | tr '\\000' x"],
            environment: CLILocator.environment(), lifecycle: ProcessLifecycle(), highWaterMark: 16_000
        )
        var total = 0
        for await chunk in session.output {
            total += chunk.count
            if total % 5 == 0 { try await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(total == count)
    }

    @Test func aSessionDroppedWhileReadsAreHeldBackDoesntCrash() async throws {
        var session: PTYSession? = try PTYSession(
            executable: "/usr/bin/yes", arguments: [], environment: CLILocator.environment(),
            lifecycle: ProcessLifecycle(), highWaterMark: 4_000
        )
        try await Task.sleep(for: .milliseconds(200))
        session?.terminate(grace: 0)
        _ = await session?.waitForExit()
        session = nil
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func theTerminalClosesAfterTheCommandEnds() async throws {
        let session = try PTYSession(
            executable: "/usr/bin/true", arguments: [], environment: CLILocator.environment(), lifecycle: ProcessLifecycle()
        )
        for await _ in session.output {}
        #expect(session.isEchoEnabled == nil)
    }

    /// Each delivery adds a line, so a second signal on top of the first would show. Cancel
    /// has to arrive exactly once with the terminal's own signals on, and with them turned off.
    @Test(arguments: [":", "stty -isig"])
    func cancelReachesTheCommandExactlyOnce(setup: String) async throws {
        let path = TestScratch.root + "burrow-int-" + UUID().uuidString
        let script = "\(setup)\ntrap 'echo x >> \(path); sleep 0.2; exit 0' INT\nprintf READY\nwhile :; do sleep 0.05; done"
        let session = try PTYSession(
            executable: "/bin/bash", arguments: ["-c", script], environment: CLILocator.environment(), lifecycle: ProcessLifecycle()
        )
        #expect(await terminalReady(session))
        session.terminate(grace: 3)
        _ = await session.waitForExit()
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        #expect(text.split(separator: "\n").count == 1)
    }
}

struct ClosingLineTests {
    private func listing(_ count: Int) -> [String] {
        (0..<count).map { "  ✓ removed file \($0) · 2MB" }
    }

    @Test func theSummaryIsFoundAfterAVeryLongListing() throws {
        let summary = try #require(RunSummary.parse(lines: listing(50_000) + ["Space freed: 2.02GB", "Tip: run again"]))
        #expect(summary.sizeText == "2.02GB")
        #expect(!summary.isEstimate)
    }

    @Test func aLongListingWithNoSummaryStaysFast() {
        let start = ContinuousClock.now
        #expect(RunSummary.parse(lines: listing(200_000)) == nil)
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test(arguments: [("a  ", "a"), ("a\t \n", "a"), ("  a b", "  a b"), ("   ", ""), ("", ""), ("漢\u{3000}", "漢"), ("e\u{0301} ", "e\u{0301}")])
    func trailingWhitespaceIsDropped(text: String, expected: String) {
        #expect(text.droppingTrailingWhitespace == expected)
    }

    @Test func aBlankRowReadsAsEmptyAndAWideGlyphIsKept() {
        var screen = TerminalScreen(rows: 3, columns: 8)
        screen.feed(Data("漢\r\n\r\na  b".utf8))
        #expect(screen.lines == ["漢", "", "a  b"])
    }
}

struct EntryMapTests {
    private func entries(_ count: Int) -> [AnalyzeResult.Entry] {
        (0..<count).map { AnalyzeResult.Entry(name: "e\($0)", path: "/e\($0)", size: Int64(1_000 - $0), isDir: true) }
    }

    @Test func aSmallFolderHasATileForEachEntry() {
        let map = EntryMap(entries: entries(5), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(map.tiles.map(\.id).sorted() == entries(5).map(\.path).sorted())
        #expect(map.restCount == 0)
        #expect(map.restSize == 0)
    }

    @Test func entriesPastTheLimitShareOneTile() {
        let map = EntryMap(entries: entries(40), in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(map.shown.count == 32)
        #expect(map.restCount == 8)
        #expect(map.tiles.count == 33)
        #expect(map.tiles.contains { $0.id == EntryMap.restID })
    }

    /// A folder grows from its tile, so the same map at another size must place it the same way.
    @Test func aTilesPlaceIsTheSameFractionAtAnySize() throws {
        let unit = EntryMap(entries: entries(40), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let drawn = EntryMap(entries: entries(40), in: CGRect(x: 0, y: 0, width: 1, height: 1).applying(.init(scaleX: 800, y: 800)))
        let first = try #require(unit.tiles.first { $0.id == "/e3" }?.rect)
        let second = try #require(drawn.tiles.first { $0.id == "/e3" }?.rect)
        #expect(abs(first.minX * 800 - second.minX) < 0.001)
        #expect(abs(first.width * 800 - second.width) < 0.001)
    }
}
