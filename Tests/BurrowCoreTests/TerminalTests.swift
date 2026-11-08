import Foundation
import Testing
@testable import BurrowCore

@Suite struct LineAssemblerTests {
    @Test func spinnerRedrawsNeverBecomeLines() {
        var assembler = LineAssembler()
        let lines = assembler.feed(Data("\r\u{1B}[1;34m⠴\u{1B}[0m Scanning...\r\u{1B}[1;34m⠦\u{1B}[0m Scanning...\r\u{1B}[2K\r\nDone\n".utf8))
        #expect(lines.map(\.text) == ["Done"])
    }

    @Test func partialExposesPromptsWithoutNewline() {
        var assembler = LineAssembler()
        _ = assembler.feed(Data("\u{1B}[0;35m➤\u{1B}[0m Remove 1 app  \u{1B}[0;32mEnter\u{1B}[0m confirm, \u{1B}[0;38;5;244mESC\u{1B}[0m cancel: ".utf8))
        #expect(assembler.partial == "➤ Remove 1 app  Enter confirm, ESC cancel:")
    }

    @Test func alternateScreenLinesAreMarked() {
        var assembler = LineAssembler()
        let lines = assembler.feed(Data("before\n\u{1B}[?1049hmenu\n\u{1B}[?1049lafter\n".utf8))
        #expect(lines.map(\.fromAlternateScreen) == [false, true, false])
    }

    @Test func multibyteSplitAcrossChunksSurvives() {
        var assembler = LineAssembler()
        let bytes = Array("✓ ok\n".utf8)
        var lines = assembler.feed(Data(bytes[0..<1]))
        lines += assembler.feed(Data(bytes[1...]))
        #expect(lines.map(\.text) == ["✓ ok"])
    }
}

@Suite struct TerminalScreenTests {
    @Test func cursorAddressingAndErase() {
        var screen = TerminalScreen(rows: 4, columns: 10)
        screen.feed(Data("hello\r\nworld\u{1B}[1;1HJ\u{1B}[2;3H\u{1B}[K".utf8))
        #expect(screen.lines[0] == "Jello")
        #expect(screen.lines[1] == "wo")
    }

    @Test func alternateScreenRestoresPrimary() {
        var screen = TerminalScreen(rows: 3, columns: 10)
        screen.feed(Data("keep\u{1B}[?1049h\u{1B}[2J\u{1B}[Hmenu".utf8))
        #expect(screen.lines[0] == "menu")
        #expect(screen.usingAlternateScreen)
        screen.feed(Data("\u{1B}[?1049l".utf8))
        #expect(screen.lines[0] == "keep")
        #expect(!screen.usingAlternateScreen)
    }

    @Test func scrollsAtBottom() {
        var screen = TerminalScreen(rows: 2, columns: 5)
        screen.feed(Data("a\r\nb\r\nc".utf8))
        #expect(screen.lines == ["b", "c"])
    }

    @Test func wideGlyphsTakeTwoCells() {
        var screen = TerminalScreen(rows: 1, columns: 5)
        screen.feed(Data("爱x".utf8))
        #expect(screen.lines[0] == "爱x")
        #expect(screen.cursorColumn == 3)
    }

    @Test func colorsAreRecorded() {
        var screen = TerminalScreen(rows: 1, columns: 5)
        screen.feed(Data("\u{1B}[1;38;5;244mx\u{1B}[0my".utf8))
        let row = screen.row(0)
        #expect(row[0].style.foreground == .palette(244))
        #expect(row[0].style.bold)
        #expect(row[1].style.foreground == .standard)
    }

    @Test func deferredWrapMatchesTerminals() {
        var screen = TerminalScreen(rows: 2, columns: 3)
        screen.feed(Data("abc\r\nd".utf8))
        // Filling the last column must not add a blank line before the CRLF.
        #expect(screen.lines == ["abc", "d"])
    }
}

@Suite struct TreemapTests {
    @Test func tilesCoverBoundsWithoutOverlap() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let items: [(id: Int, size: Double)] = [(0, 60), (1, 30), (2, 20), (3, 10), (4, 5), (5, 0)]
        let tiles = Treemap.layout(items: items, in: bounds)
        #expect(tiles.count == 5)

        let area = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(area - 120_000) < 1)
        for (index, tile) in tiles.enumerated() {
            #expect(bounds.insetBy(dx: -0.5, dy: -0.5).contains(tile.rect))
            for other in tiles[(index + 1)...] {
                #expect(tile.rect.insetBy(dx: 0.5, dy: 0.5).intersects(other.rect) == false)
            }
        }
    }

    @Test func areaIsProportionalToSize() throws {
        let tiles = Treemap.layout(items: [(id: "a", size: 3), (id: "b", size: 1)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let a = try #require(tiles.first { $0.id == "a" })
        #expect(abs(Double(a.rect.width * a.rect.height) - 7_500) < 1)
    }

    @Test func emptyInputIsEmpty() {
        #expect(Treemap.layout(items: [(id: 1, size: 0)], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }
}

/// Both readers of a stream now share one grammar. These are cases where they used to differ.
struct SharedEscapeGrammarTests {
    @Test func aSequenceThatRestartsDoesntLeakIntoTheLine() {
        var assembler = LineAssembler()
        let lines = assembler.feed(Data("done\u{1B}[1\u{1B}[2K\nnext\n".utf8))
        #expect(lines.map(\.text) == ["next"])
    }

    @Test(arguments: ["\u{1B}[?25;1049h", "\u{1B}[?1049;25h", "\u{1B}[?1049h"])
    func aModeListEntersTheAlternateScreen(sequence: String) {
        var assembler = LineAssembler()
        let lines = assembler.feed(Data("\(sequence)row\n\u{1B}[?1049lafter\n".utf8))
        #expect(lines.map(\.fromAlternateScreen) == [true, false])
        #expect(!assembler.inAlternateScreen)

        var screen = TerminalScreen(rows: 3, columns: 10)
        screen.feed(Data(sequence.utf8))
        #expect(screen.usingAlternateScreen)
    }

    @Test func otherModesDontChangeWhichScreenIsInUse() {
        var assembler = LineAssembler()
        _ = assembler.feed(Data("\u{1B}[?25h\u{1B}[1049h".utf8))
        #expect(!assembler.inAlternateScreen)
    }

    @Test func aSequenceInterruptsAMultiByteCharacter() {
        var screen = TerminalScreen(rows: 2, columns: 10)
        screen.feed(Data([0xE6, 0xBC, 0x1B, 0x5B, 0x30, 0x6D, 0xA2, 0x61]))
        #expect(screen.lines[0] == "a")
    }
}
