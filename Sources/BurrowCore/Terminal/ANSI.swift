import Foundation

public enum ANSI {
    /// Removes escape sequences and carriage-return overwrites from captured output.
    public static func strip(_ text: String) -> String {
        var assembler = LineAssembler()
        let lines = assembler.feed(Data(text.utf8))
        let tail = assembler.partial
        var all = lines.map(\.text)
        if !tail.isEmpty { all.append(tail) }
        return all.joined(separator: "\n")
    }
}

extension String {
    /// The string with trailing whitespace removed. Runs for every line a command prints and
    /// every row of a screen read, so it doesn't use a regular expression.
    var droppingTrailingWhitespace: String {
        guard let end = unicodeScalars.last, end.properties.isWhitespace else { return self }
        var scalars = unicodeScalars[...]
        while let last = scalars.last, last.properties.isWhitespace {
            scalars.removeLast()
        }
        return String(scalars)
    }
}
