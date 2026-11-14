import Foundation

/// A small VT100/xterm screen model.
///
/// It covers what Mole's shell menus and the Bubble Tea programs emit. It serves two
/// jobs: drawing the live terminal panel, and letting `MenuDriver` read the real menu
/// state so that each key it sends can be checked against what the CLI displays.
public struct TerminalScreen: Sendable {
    public private(set) var rows: Int
    public private(set) var columns: Int
    public private(set) var cursorRow = 0
    public private(set) var cursorColumn = 0
    public private(set) var cursorVisible = true
    public private(set) var usingAlternateScreen = false
    /// Increments on every change, so views and drivers can detect a repaint cheaply.
    public private(set) var revision = 0

    private var cells: [[TerminalCell]]
    private var savedPrimary: [[TerminalCell]]?
    private var savedCursor: (row: Int, column: Int) = (0, 0)
    private var style = CellStyle()
    private var scrollTop = 0
    private var scrollBottom: Int
    private var wrapPending = false

    private var tokenizer = EscapeTokenizer()
    private var utf8Buffer: [UInt8] = []
    private var utf8Expected = 0
    private var pendingResponses: [UInt8] = []
    private var csiParameters: [Int?] = []
    private var styleBuffer: [Int] = []

    /// The terminal panel's colors, reported to programs that ask, as `rgb:rr/gg/bb` values.
    private static let reportedForeground = "f2f2/f2f2/f7f7"
    private static let reportedBackground = "1c1c/1c1c/1e1e"

    public init(rows: Int, columns: Int) {
        self.rows = max(rows, 1)
        self.columns = max(columns, 1)
        scrollBottom = max(rows, 1) - 1
        cells = Array(repeating: Array(repeating: TerminalCell(), count: max(columns, 1)), count: max(rows, 1))
    }

    public mutating func resize(rows newRows: Int, columns newColumns: Int) {
        let targetRows = max(newRows, 1)
        let targetColumns = max(newColumns, 1)
        guard targetRows != rows || targetColumns != columns else { return }
        // Keep the bottom of the old screen, where the cursor usually sits.
        let offset = max(0, cursorRow - targetRows + 1)
        cells = Self.fitted(cells, droppingTop: offset, rows: targetRows, columns: targetColumns)
        // A program using the alternate screen gets resized too, and leaving it must still
        // bring back what was underneath.
        if let saved = savedPrimary {
            let savedOffset = max(0, savedCursor.row - targetRows + 1)
            savedPrimary = Self.fitted(saved, droppingTop: savedOffset, rows: targetRows, columns: targetColumns)
            savedCursor = (
                savedCursor.row - savedOffset,
                min(savedCursor.column, targetColumns - 1)
            )
        }
        rows = targetRows
        columns = targetColumns
        scrollTop = 0
        scrollBottom = targetRows - 1
        cursorRow -= offset
        cursorColumn = min(cursorColumn, targetColumns - 1)
        wrapPending = false
        revision &+= 1
    }

    private static func fitted(_ grid: [[TerminalCell]], droppingTop offset: Int, rows: Int, columns: Int) -> [[TerminalCell]] {
        var resized = Array(repeating: Array(repeating: TerminalCell(), count: columns), count: rows)
        for row in 0..<max(min(grid.count - offset, rows), 0) {
            for column in 0..<min(grid[row + offset].count, columns) {
                resized[row][column] = grid[row + offset][column]
            }
        }
        return resized
    }

    /// Answers to questions the program asked the terminal, waiting to be sent back.
    public mutating func takeResponses() -> [UInt8] {
        defer { pendingResponses.removeAll(keepingCapacity: true) }
        return pendingResponses
    }

    public mutating func feed(_ data: Data) {
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                process(byte)
            }
        }
        revision &+= 1
    }

    /// The screen as trimmed text lines, one per row.
    public var lines: [String] {
        cells.map { Self.text(of: $0) }
    }

    public func row(_ row: Int) -> [TerminalCell] {
        guard row >= 0, row < rows else { return [] }
        return cells[row]
    }

    private static func text(of row: [TerminalCell]) -> String {
        // Most of a row is usually blank, so stop before building that part of the string.
        guard let last = row.lastIndex(where: { $0.character != " " }) else { return "" }
        var output = ""
        output.reserveCapacity(last + 1)
        for cell in row[...last] where !cell.isContinuation {
            output.append(cell.character)
        }
        return output.droppingTrailingWhitespace
    }

    // MARK: - Byte processing

    private mutating func process(_ byte: UInt8) {
        switch tokenizer.next(byte) {
        case nil:
            return
        case .text(let text):
            processText(text)
            return
        case .escape(let code):
            performEscape(code)
        case .csi(let final):
            performCSI(final: final)
        case .osc:
            performOSC()
        case .ignored:
            break
        }
        // A sequence interrupts a multi-byte character.
        utf8Buffer.removeAll(keepingCapacity: true)
        utf8Expected = 0
    }

    private mutating func processText(_ byte: UInt8) {
        if utf8Expected > 0 {
            if byte & 0xC0 == 0x80 {
                utf8Buffer.append(byte)
                if utf8Buffer.count == utf8Expected {
                    let scalarText = String(decoding: utf8Buffer, as: UTF8.self)
                    utf8Buffer.removeAll(keepingCapacity: true)
                    utf8Expected = 0
                    for character in scalarText { put(character, width: Self.displayWidth(of: character)) }
                }
                return
            }
            utf8Buffer.removeAll(keepingCapacity: true)
            utf8Expected = 0
        }

        switch byte {
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
        case 0x0D:
            cursorColumn = 0
            wrapPending = false
        case 0x08:
            cursorColumn = max(0, cursorColumn - 1)
            wrapPending = false
        case 0x09:
            cursorColumn = min(columns - 1, (cursorColumn / 8 + 1) * 8)
            wrapPending = false
        case 0x00..<0x20, 0x7F:
            break
        case 0x20..<0x7F:
            // This byte range already tells us the glyph occupies one cell.
            put(Character(UnicodeScalar(byte)), width: 1)
        case 0xC0..<0xE0:
            utf8Buffer = [byte]
            utf8Expected = 2
        case 0xE0..<0xF0:
            utf8Buffer = [byte]
            utf8Expected = 3
        case 0xF0..<0xF8:
            utf8Buffer = [byte]
            utf8Expected = 4
        default:
            break
        }
    }

    private mutating func performEscape(_ code: UInt8) {
        switch code {
        case UInt8(ascii: "7"):
            savedCursor = (cursorRow, cursorColumn)
        case UInt8(ascii: "8"):
            moveCursor(row: savedCursor.row, column: savedCursor.column)
        case UInt8(ascii: "D"):
            lineFeed()
        case UInt8(ascii: "E"):
            cursorColumn = 0
            lineFeed()
        case UInt8(ascii: "M"):
            reverseIndex()
        case UInt8(ascii: "c"):
            clearAll()
            cursorRow = 0
            cursorColumn = 0
            style = CellStyle()
        default:
            break
        }
    }

    private mutating func put(_ character: Character, width measured: Int) {
        if measured == 0 {
            // A combining mark or variation selector joins the previous glyph, which sits under
            // the cursor while a wrap is pending and starts one cell back if it's wide.
            var target = wrapPending ? cursorColumn : cursorColumn - 1
            if target > 0, target < columns, cells[cursorRow][target].isContinuation { target -= 1 }
            guard target >= 0 else { return }
            // A cell can hold a character a mark doesn't join, such as a format character.
            // Character(_:) traps on more than one grapheme, so those marks are dropped.
            let joined = String(cells[cursorRow][target].character) + String(character)
            if joined.count == 1, let glyph = joined.first {
                cells[cursorRow][target].character = glyph
            }
            return
        }
        // A wide glyph can't fit a one-column screen, which would index past the row.
        let width = min(measured, columns)
        if wrapPending || cursorColumn + width > columns {
            cursorColumn = 0
            lineFeed()
            wrapPending = false
        }
        clearWideGlyphsOverlapping(column: cursorColumn, width: width)
        var cell = TerminalCell()
        cell.character = character
        cell.style = style
        cells[cursorRow][cursorColumn] = cell
        if width == 2 {
            var continuation = TerminalCell()
            continuation.style = style
            continuation.isContinuation = true
            cells[cursorRow][cursorColumn + 1] = continuation
        }
        cursorColumn += width
        if cursorColumn >= columns {
            cursorColumn = columns - 1
            wrapPending = true
        }
    }

    /// Overwriting half of a wide glyph mustn't leave the other half behind.
    private mutating func clearWideGlyphsOverlapping(column: Int, width: Int) {
        clearWideGlyphsOverlapping(range: column..<min(column + width, columns))
    }

    private mutating func clearWideGlyphsOverlapping(range: Range<Int>) {
        guard !range.isEmpty else { return }
        if range.lowerBound > 0, cells[cursorRow][range.lowerBound].isContinuation {
            cells[cursorRow][range.lowerBound - 1] = blankCell()
        }
        if range.upperBound < columns, cells[cursorRow][range.upperBound].isContinuation {
            cells[cursorRow][range.upperBound] = blankCell()
        }
    }

    static func displayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        let value = scalar.value
        if character.unicodeScalars.count == 1, scalar.properties.generalCategory == .nonspacingMark
            || scalar.properties.generalCategory == .enclosingMark || value == 0xFE0F || value == 0x200D {
            return 0
        }
        switch value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x1F004, 0x1F0CF, 0x1F18E, 0x1F191...0x1F19A, 0x1F1E6...0x1F1FF, 0x1F200...0x1F265,
            0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F7E0...0x1F7EB, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
            0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    private mutating func lineFeed() {
        wrapPending = false
        if cursorRow == scrollBottom {
            removeLines(at: scrollTop, count: 1)
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    private mutating func reverseIndex() {
        wrapPending = false
        if cursorRow == scrollTop {
            insertBlankLines(at: scrollTop, count: 1)
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
    }

    private func blankRow() -> [TerminalCell] {
        Array(repeating: blankCell(), count: columns)
    }

    private mutating func moveCursor(row: Int? = nil, column: Int? = nil) {
        cursorRow = min(max(row ?? cursorRow, 0), rows - 1)
        cursorColumn = min(max(column ?? cursorColumn, 0), columns - 1)
        wrapPending = false
    }

    /// Removes rows from `start` down, closing the gap with blanks at the region's bottom.
    /// `start` is inside the scroll region and `count` is at least 1, so `amount` is too.
    private mutating func removeLines(at start: Int, count: Int) {
        let amount = min(count, scrollBottom - start + 1)
        cells.removeSubrange(start..<(start + amount))
        cells.insert(contentsOf: Array(repeating: blankRow(), count: amount), at: scrollBottom - amount + 1)
    }

    /// Inserts blanks at `start`, pushing the region's bottom rows off. The same bounds apply.
    private mutating func insertBlankLines(at start: Int, count: Int) {
        let amount = min(count, scrollBottom - start + 1)
        cells.removeSubrange((scrollBottom - amount + 1)...scrollBottom)
        cells.insert(contentsOf: Array(repeating: blankRow(), count: amount), at: start)
    }

    private mutating func clearAll() {
        cells = Array(repeating: blankRow(), count: rows)
    }

    // MARK: - CSI

    private static let maximumParameter = 65_535

    private mutating func performCSI(final: UInt8) {
        // Sequences with intermediate bytes, such as `ESC[ q` or `ESC[!p`, aren't implemented,
        // and acting on their parameters as if they were plain would do something else.
        let parameters = tokenizer.parameters
        guard !parameters.contains(where: { (0x20...0x2F).contains($0) }) else { return }
        var body = parameters[...]
        let prefix: UInt8?
        if let first = body.first,
           first == UInt8(ascii: "<") || first == UInt8(ascii: "=") || first == UInt8(ascii: ">") || first == UInt8(ascii: "?") {
            prefix = first
            body = body.dropFirst()
        } else {
            prefix = nil
        }
        let isPrivate = prefix == UInt8(ascii: "?")
        switch prefix {
        case UInt8(ascii: "?"):
            // Xterm extensions share these final bytes. `ESC[?4m`, for one, isn't a style.
            guard [UInt8(ascii: "h"), UInt8(ascii: "l"), UInt8(ascii: "J"), UInt8(ascii: "K"), UInt8(ascii: "n")].contains(final) else { return }
        case UInt8(ascii: ">"):
            if final == UInt8(ascii: "c") { respond("\u{1B}[>0;0;0c") }
            return
        case UInt8(ascii: "<"), UInt8(ascii: "="):
            return
        default:
            break
        }
        if final == UInt8(ascii: "m") {
            // Styles have their own grammar, so don't also parse them as cursor parameters.
            // An empty list here means nothing recognized, not a reset.
            Self.parseStyleCodes(body, into: &styleBuffer)
            if !styleBuffer.isEmpty { applyStyle(styleBuffer) }
            return
        }
        // Clamped because cursor arithmetic below would trap on a huge or negative value.
        Self.parseCSIParameters(body, into: &csiParameters)

        func value(_ index: Int, default fallback: Int) -> Int {
            guard index < csiParameters.count, let number = csiParameters[index] else { return fallback }
            return number
        }

        // Cursor and editing commands treat a missing or zero count as one.
        var count: Int { max(value(0, default: 1), 1) }
        switch final {
        case UInt8(ascii: "A"):
            moveCursor(row: cursorRow - count)
        case UInt8(ascii: "B"), UInt8(ascii: "e"):
            moveCursor(row: cursorRow + count)
        case UInt8(ascii: "C"), UInt8(ascii: "a"):
            moveCursor(column: cursorColumn + count)
        case UInt8(ascii: "D"):
            moveCursor(column: cursorColumn - count)
        case UInt8(ascii: "E"):
            moveCursor(row: cursorRow + count, column: 0)
        case UInt8(ascii: "F"):
            moveCursor(row: cursorRow - count, column: 0)
        case UInt8(ascii: "G"), UInt8(ascii: "`"):
            moveCursor(column: value(0, default: 1) - 1)
        case UInt8(ascii: "d"):
            moveCursor(row: value(0, default: 1) - 1)
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            moveCursor(row: value(0, default: 1) - 1, column: value(1, default: 1) - 1)
        case UInt8(ascii: "J"):
            eraseDisplay(value(0, default: 0))
        case UInt8(ascii: "K"):
            eraseLine(value(0, default: 0))
        case UInt8(ascii: "L"):
            if cursorRow >= scrollTop, cursorRow <= scrollBottom { insertBlankLines(at: cursorRow, count: count) }
        case UInt8(ascii: "M"):
            if cursorRow >= scrollTop, cursorRow <= scrollBottom { removeLines(at: cursorRow, count: count) }
        case UInt8(ascii: "P"):
            deleteCharacters(count)
        case UInt8(ascii: "@"):
            insertCharacters(count)
        case UInt8(ascii: "X"):
            let end = min(cursorColumn + count, columns)
            let range = cursorColumn..<end
            clearWideGlyphsOverlapping(range: range)
            for column in range { cells[cursorRow][column] = blankCell() }
        case UInt8(ascii: "S"):
            removeLines(at: scrollTop, count: count)
        case UInt8(ascii: "T"):
            insertBlankLines(at: scrollTop, count: count)
        case UInt8(ascii: "n"):
            switch value(0, default: 0) {
            case 5: respond("\u{1B}[0n")
            case 6: respond("\u{1B}[\(isPrivate ? "?" : "")\(cursorRow + 1);\(cursorColumn + 1)R")
            default: break
            }
        case UInt8(ascii: "c"):
            if value(0, default: 0) == 0 { respond("\u{1B}[?1;2c") }
        case UInt8(ascii: "r"):
            let top = max(value(0, default: 1) - 1, 0)
            let bottom = min(value(1, default: rows) - 1, rows - 1)
            if top < bottom {
                scrollTop = top
                scrollBottom = bottom
                cursorRow = 0
                cursorColumn = 0
            }
        case UInt8(ascii: "s"):
            savedCursor = (cursorRow, cursorColumn)
        case UInt8(ascii: "u"):
            moveCursor(row: savedCursor.row, column: savedCursor.column)
        case UInt8(ascii: "h") where isPrivate:
            setPrivateMode(csiParameters, enabled: true)
        case UInt8(ascii: "l") where isPrivate:
            setPrivateMode(csiParameters, enabled: false)
        default:
            break
        }
    }

    /// Real terminals answer these, and a program that asks can wait seconds for the reply.
    /// Answers hold no Return, so one printed through a file name can't confirm a question.
    private mutating func respond(_ text: String) {
        pendingResponses.append(contentsOf: text.utf8)
    }

    private mutating func performOSC() {
        switch tokenizer.oscText.map({ String(decoding: $0, as: UTF8.self) }) {
        case "10;?": respond("\u{1B}]10;rgb:\(Self.reportedForeground)\u{1B}\\")
        case "11;?": respond("\u{1B}]11;rgb:\(Self.reportedBackground)\u{1B}\\")
        default: break
        }
    }

    private static func parseOptionalInt(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard !bytes.isEmpty else { return nil }
        var result = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            let digit = Int(byte - UInt8(ascii: "0"))
            if result <= maximumParameter {
                result = min(result * 10 + digit, maximumParameter)
            }
        }
        return result
    }

    private static func parseCSIParameters(_ bytes: ArraySlice<UInt8>, into output: inout [Int?]) {
        output.removeAll(keepingCapacity: true)
        var start = bytes.startIndex
        while true {
            let delimiter = bytes[start...].firstIndex(of: UInt8(ascii: ";")) ?? bytes.endIndex
            output.append(parseOptionalInt(bytes[start..<delimiter]))
            guard delimiter < bytes.endIndex else { break }
            start = bytes.index(after: delimiter)
        }
    }

    /// SGR codes with colon forms such as `38:2::1:2:3` and `4:3` spelled the semicolon way.
    /// Read as plain numbers they'd count as 0, which resets the whole style.
    private static func parseStyleCodes(_ bytes: ArraySlice<UInt8>, into output: inout [Int]) {
        output.removeAll(keepingCapacity: true)
        var start = bytes.startIndex
        while true {
            let delimiter = bytes[start...].firstIndex(of: UInt8(ascii: ";")) ?? bytes.endIndex
            let field = bytes[start..<delimiter]
            if !field.contains(UInt8(ascii: ":")) {
                output.append(parseOptionalInt(field) ?? 0)
            } else {
                var parts: [Int?] = []
                var partStart = field.startIndex
                while true {
                    let colon = field[partStart...].firstIndex(of: UInt8(ascii: ":")) ?? field.endIndex
                    parts.append(parseOptionalInt(field[partStart..<colon]))
                    guard colon < field.endIndex else { break }
                    partStart = field.index(after: colon)
                }
                switch (parts.first ?? nil, parts.count > 1 ? parts[1] : nil) {
                case (38?, 5?), (48?, 5?):
                    if parts.count > 2 {
                        output.append(parts[0] ?? 0)
                        output.append(5)
                        output.append(parts[2] ?? 0)
                    }
                case (38?, 2?), (48?, 2?):
                    // The color-space field between the 2 and the components is optional.
                    if parts.count >= 5 {
                        output.append(parts[0] ?? 0)
                        output.append(2)
                        let tail = parts.suffix(3)
                        for component in tail { output.append(component ?? 0) }
                    }
                case (4?, 0?):
                    output.append(24)
                case (4?, _):
                    output.append(4)
                default:
                    break
                }
            }
            guard delimiter < bytes.endIndex else { break }
            start = bytes.index(after: delimiter)
        }
    }

    private func blankCell() -> TerminalCell {
        var cell = TerminalCell()
        cell.style.background = style.background
        return cell
    }

    private mutating func eraseDisplay(_ mode: Int) {
        wrapPending = false
        switch mode {
        case 0:
            eraseLine(0)
            for row in (cursorRow + 1)..<rows { cells[row] = blankRow() }
        case 1:
            eraseLine(1)
            for row in 0..<cursorRow { cells[row] = blankRow() }
        default:
            clearAll()
        }
    }

    private mutating func eraseLine(_ mode: Int) {
        wrapPending = false
        switch mode {
        case 0:
            let range = cursorColumn..<columns
            clearWideGlyphsOverlapping(range: range)
            for column in range { cells[cursorRow][column] = blankCell() }
        case 1:
            let range = 0..<(min(cursorColumn, columns - 1) + 1)
            clearWideGlyphsOverlapping(range: range)
            for column in range { cells[cursorRow][column] = blankCell() }
        default:
            cells[cursorRow] = blankRow()
        }
    }

    private mutating func deleteCharacters(_ count: Int) {
        let amount = min(count, columns - cursorColumn)
        clearWideGlyphsOverlapping(range: cursorColumn..<(cursorColumn + amount))
        cells[cursorRow].removeSubrange(cursorColumn..<(cursorColumn + amount))
        cells[cursorRow].append(contentsOf: Array(repeating: blankCell(), count: amount))
    }

    private mutating func insertCharacters(_ count: Int) {
        let amount = min(count, columns - cursorColumn)
        if cursorColumn > 0, cells[cursorRow][cursorColumn].isContinuation {
            cells[cursorRow][cursorColumn - 1] = blankCell()
            cells[cursorRow][cursorColumn] = blankCell()
        }
        clearWideGlyphsOverlapping(range: (columns - amount)..<columns)
        cells[cursorRow].removeLast(amount)
        cells[cursorRow].insert(contentsOf: Array(repeating: blankCell(), count: amount), at: cursorColumn)
    }

    private mutating func setPrivateMode(_ modes: [Int?], enabled: Bool) {
        for case let mode? in modes {
            switch mode {
            case 25:
                cursorVisible = enabled
            case 47, 1047, 1049:
                if enabled, !usingAlternateScreen {
                    savedPrimary = cells
                    savedCursor = (cursorRow, cursorColumn)
                    usingAlternateScreen = true
                    clearAll()
                } else if !enabled, usingAlternateScreen {
                    usingAlternateScreen = false
                    if let savedPrimary, savedPrimary.count == rows {
                        cells = savedPrimary
                    }
                    savedPrimary = nil
                    moveCursor(row: savedCursor.row, column: savedCursor.column)
                }
                scrollTop = 0
                scrollBottom = rows - 1
                wrapPending = false
            default:
                break
            }
        }
    }

    private mutating func applyStyle(_ codes: [Int]) {
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = CellStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22:
                style.bold = false
                style.dim = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .palette(UInt8(code - 30))
            case 39: style.foreground = .standard
            case 40...47: style.background = .palette(UInt8(code - 40))
            case 49: style.background = .standard
            case 90...97: style.foreground = .palette(UInt8(code - 90 + 8))
            case 100...107: style.background = .palette(UInt8(code - 100 + 8))
            case 38, 48:
                let isForeground = code == 38
                if index + 2 < codes.count, codes[index + 1] == 5 {
                    let color = TerminalColor.palette(UInt8(clamping: codes[index + 2]))
                    if isForeground { style.foreground = color } else { style.background = color }
                    index += 2
                } else if index + 4 < codes.count, codes[index + 1] == 2 {
                    let color = TerminalColor.rgb(
                        UInt8(clamping: codes[index + 2]),
                        UInt8(clamping: codes[index + 3]),
                        UInt8(clamping: codes[index + 4])
                    )
                    if isForeground { style.foreground = color } else { style.background = color }
                    index += 4
                }
            default:
                break
            }
            index += 1
        }
    }
}
