import Foundation

/// A running CLI command with its parsed screen and output lines.
///
/// All state is on the main actor. Views observe it through `RunController`, and
/// `MenuDriver` reads `screen` to verify each key it sends.
@MainActor
public final class CLITerminal {
    public private(set) var screen: TerminalScreen
    public private(set) var isRunning = true
    public private(set) var partial = ""

    public var onLine: ((String) -> Void)?
    public var onChange: (() -> Void)?
    public var onExit: ((Int32) -> Void)?

    private let session: PTYSession
    private var assembler = LineAssembler()

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        rows: Int = 50,
        columns: Int = 120
    ) throws {
        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        // Set by the size below, not inherited from whatever launched the app.
        env.removeValue(forKey: "LINES")
        env.removeValue(forKey: "COLUMNS")
        screen = TerminalScreen(rows: rows, columns: columns)
        session = try PTYSession(
            executable: executable,
            arguments: arguments,
            environment: env,
            rows: UInt16(rows),
            columns: UInt16(columns)
        )
        Task { [weak self, session] in
            for await chunk in session.output {
                self?.consume(chunk)
            }
            let status = await session.waitForExit()
            self?.finish(status: status)
        }
    }

    private func consume(_ data: Data) {
        screen.feed(data)
        let responses = screen.takeResponses()
        if !responses.isEmpty { session.write(responses) }
        for line in assembler.feed(data) where !line.fromAlternateScreen {
            onLine?(line.text)
        }
        partial = assembler.partial
        onChange?()
    }

    private func finish(status: Int32) {
        isRunning = false
        // A closing line needn't end in a newline. A spinner left on screen isn't a result.
        let last = assembler.partialLine
        let isSpinner = last.trimmingCharacters(in: .whitespaces).startsWithSpinner
        if !last.isEmpty, !assembler.inAlternateScreen, !isSpinner { onLine?(last) }
        partial = ""
        onChange?()
        onExit?(status)
    }

    /// True only when a program has turned terminal echo off, as `sudo` does while it
    /// reads a password. Unknown state counts as false, so nothing secret is sent on it.
    public var isEchoOff: Bool {
        session.isEchoEnabled == false
    }

    public func send(_ bytes: [UInt8]) {
        session.write(bytes)
    }

    public func send(_ text: String) {
        session.write(text)
    }

    public func resize(rows: Int, columns: Int) {
        screen.resize(rows: rows, columns: columns)
        session.resize(rows: UInt16(rows), columns: UInt16(columns))
        onChange?()
    }

    public func cancel() {
        session.terminate()
    }

    /// Waits until the command has exited.
    public func waitForExit() async -> Int32 {
        await session.waitForExit()
    }
}
