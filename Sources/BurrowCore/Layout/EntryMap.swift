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

    /// Normalizes `rect` into unit `[0, 1]` coordinates within `size`, or `nil` if `size` is empty.
    public static func normalized(_ rect: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                      width: rect.width / size.width, height: rect.height / size.height)
    }
}
