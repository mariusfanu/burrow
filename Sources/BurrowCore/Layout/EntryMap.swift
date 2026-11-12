import Foundation

/// Disk Explorer's map of a folder: its largest entries as tiles, with the rest combined into
/// one, so what's drawn and the rectangle a folder grows from can't disagree.
public struct EntryMap: Sendable {
    /// Beyond this many tiles the labels stop being readable, so the rest are combined.
    private static let tileLimit = 32
    public static let restID = "\u{0}rest"

    public let shown: [AnalyzeResult.Entry]
    public let restCount: Int
    public let restSize: Int64
    public let tiles: [Treemap.Tile<String>]

    public init(entries: [AnalyzeResult.Entry], in bounds: CGRect) {
        shown = Array(entries.prefix(Self.tileLimit))
        let rest = entries.dropFirst(Self.tileLimit)
        restCount = rest.count
        restSize = rest.map(\.size).saturatingSum
        let items = shown.map { (id: $0.path, size: Double($0.size)) }
            + (restSize > 0 ? [(id: Self.restID, size: Double(restSize))] : [])
        tiles = Treemap.layout(items: items, in: bounds)
    }
}
