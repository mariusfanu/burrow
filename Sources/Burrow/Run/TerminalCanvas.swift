import AppKit
import BurrowCore

final class TerminalCanvas: NSView {
    var terminal: CLITerminal? { didSet { refreshDiagnostics() } }
    var sendInput: ((String) -> Void)? {
        didSet {
            setAccessibilityHelp(sendInput == nil
                ? "Use Select All and Copy to copy the visible output."
                : "Type to answer the command. Use Select All and Copy to copy the visible output.")
        }
    }
    private(set) var diagnosticText = ""
    private var selectsAllOutput = false

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private let background = NSColor(hex: 0x1C1C1E)
    private let foreground = NSColor(hex: 0xF2F2F7)
    private var lastSize: (rows: Int, columns: Int) = (0, 0)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Since macOS 14 a view can draw outside its bounds unless told otherwise.
        clipsToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Terminal output")
        setAccessibilityHelp("Use Select All and Copy to copy the visible output.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Uses only cells received from the program, never the input buffer or a password field.
    func refreshDiagnostics() {
        let text = terminal?.screen.lines.joined(separator: "\n").trimmingCharacters(in: .newlines) ?? ""
        guard text != diagnosticText else { return }
        diagnosticText = text
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    override func accessibilityValue() -> Any? { diagnosticText }
    override func accessibilityNumberOfCharacters() -> Int { diagnosticText.utf16.count }
    override func accessibilitySelectedText() -> String? { selectsAllOutput ? diagnosticText : "" }
    override func accessibilitySelectedTextRange() -> NSRange {
        NSRange(location: 0, length: selectsAllOutput ? diagnosticText.utf16.count : 0)
    }

    @objc override func selectAll(_ sender: Any?) {
        selectsAllOutput = true
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }

    @objc func copy(_ sender: Any?) { copyVisibleOutput(to: .general) }

    /// Copies the current screen even when no range is selected, for quick diagnostics.
    func copyVisibleOutput(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(diagnosticText, forType: .string)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    private let cellSize: CGSize = {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let width = ("M" as NSString).size(withAttributes: [.font: font]).width
        return CGSize(width: ceil(width), height: ceil(font.ascender - font.descender + font.leading) + 2)
    }()

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let terminal, terminal.isRunning else { return }
        // The panel is never shown while the app operates a menu, so resizing here
        // can't disturb the tall terminal that the menu driver relies on.
        let columns = max(Int((newSize.width - 16) / cellSize.width), 20)
        let rows = max(Int((newSize.height - 16) / cellSize.height), 5)
        guard rows != lastSize.rows || columns != lastSize.columns else { return }
        lastSize = (rows, columns)
        terminal.resize(rows: rows, columns: columns)
    }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        bounds.fill()
        if selectsAllOutput {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
            bounds.fill()
        }
        guard let terminal else { return }
        let screen = terminal.screen
        let cell = cellSize

        for rowIndex in 0..<screen.rows {
            let y = 8 + CGFloat(rowIndex) * cell.height
            guard y + cell.height >= dirtyRect.minY, y <= dirtyRect.maxY else { continue }
            let row = screen.row(rowIndex)
            var column = 0
            while column < row.count {
                let style = row[column].style
                var text = ""
                let start = column
                while column < row.count, row[column].style == style {
                    if !row[column].isContinuation { text.append(row[column].character) }
                    column += 1
                }
                let rect = CGRect(
                    x: 8 + CGFloat(start) * cell.width,
                    y: y,
                    width: CGFloat(column - start) * cell.width,
                    height: cell.height
                )
                var (fg, bg) = (color(style.foreground, fallback: foreground), color(style.background, fallback: background))
                if style.inverse { swap(&fg, &bg) }
                if style.dim { fg = fg.withAlphaComponent(0.6) }
                if bg != background {
                    bg.setFill()
                    rect.fill()
                }
                guard text.contains(where: { $0 != " " }) else { continue }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: style.bold ? boldFont : font,
                    .foregroundColor: fg,
                ]
                if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                (text as NSString).draw(at: CGPoint(x: rect.minX, y: rect.minY + 1), withAttributes: attributes)
            }
        }

        if screen.cursorVisible, terminal.isRunning {
            NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
            CGRect(
                x: 8 + CGFloat(screen.cursorColumn) * cell.width,
                y: 8 + CGFloat(screen.cursorRow) * cell.height,
                width: cell.width,
                height: cell.height
            ).fill()
        }
    }

    private func color(_ color: TerminalColor, fallback: NSColor) -> NSColor {
        switch color {
        case .standard:
            return fallback
        case .rgb(let red, let green, let blue):
            return NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        case .palette(let index):
            return Self.paletteColor(index)
        }
    }

    private static let basePalette: [UInt32] = [
        0x2C2C2E, 0xFF6961, 0x63D471, 0xFFD426, 0x5AA9FF, 0xDA8FFF, 0x5AD8E6, 0xD1D1D6,
        0x8E8E93, 0xFF8A84, 0x86E68F, 0xFFE066, 0x8AC4FF, 0xE5ACFF, 0x8CE8F2, 0xFFFFFF,
    ]
    private static let cubeLevels: [CGFloat] = [0, 95, 135, 175, 215, 255]

    private static func paletteColor(_ index: UInt8) -> NSColor {
        switch index {
        case 0..<16:
            return NSColor(hex: basePalette[Int(index)])
        case 16..<232:
            let value = Int(index) - 16
            return NSColor(
                srgbRed: cubeLevels[value / 36] / 255,
                green: cubeLevels[(value / 6) % 6] / 255,
                blue: cubeLevels[value % 6] / 255,
                alpha: 1
            )
        default:
            let gray = (CGFloat(Int(index) - 232) * 10 + 8) / 255
            return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        }
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": selectAll(nil); return
            case "c": copy(nil); return
            default: break
            }
        }
        guard let sendInput, terminal?.isRunning == true else {
            super.keyDown(with: event)
            return
        }
        selectsAllOutput = false
        if let sequence = Self.sequence(for: event) {
            sendInput(sequence)
        } else if event.modifierFlags.contains(.control), let characters = event.charactersIgnoringModifiers,
                  let scalar = characters.lowercased().unicodeScalars.first,
                  (97...122).contains(scalar.value) {
            sendInput(String(UnicodeScalar(UInt8(scalar.value - 96))))
        } else if let characters = event.characters, !event.modifierFlags.contains(.command) {
            sendInput(characters)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let sendInput, terminal?.isRunning == true else { return }
        selectsAllOutput = false
        if let text = NSPasteboard.general.string(forType: .string) {
            sendInput(text)
        }
    }

    private static func sequence(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case 36, 76: "\r"
        case 48: "\t"
        case 51: "\u{7F}"
        case 53: "\u{1B}"
        case 117: "\u{1B}[3~"
        case 123: "\u{1B}[D"
        case 124: "\u{1B}[C"
        case 125: "\u{1B}[B"
        case 126: "\u{1B}[A"
        case 115: "\u{1B}[H"
        case 119: "\u{1B}[F"
        case 116: "\u{1B}[5~"
        case 121: "\u{1B}[6~"
        default: nil
        }
    }
}
