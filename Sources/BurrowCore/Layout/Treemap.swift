import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing and van Wijk).
public enum Treemap {
    public struct Tile<ID: Hashable & Sendable>: Sendable {
        public let id: ID
        public let rect: CGRect
    }

    /// Lays items out inside `bounds`. Items with no size are left out. A result is
    /// produced in descending size order regardless of the input order.
    public static func layout<ID: Hashable & Sendable>(
        items: [(id: ID, size: Double)],
        in bounds: CGRect
    ) -> [Tile<ID>] {
        let sorted = items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        let total = sorted.reduce(0) { $0 + $1.size }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        let scale = Double(bounds.width * bounds.height) / total
        let scaled = sorted.map { (id: $0.id, area: $0.size * scale) }
        var free = bounds
        var tiles: [Tile<ID>] = []
        tiles.reserveCapacity(scaled.count)

        var start = 0
        while start < scaled.count {
            let side = Double(min(free.width, free.height))
            // Sizes descend, so a row's largest item is its first and its smallest its last.
            let largest = scaled[start].area
            var rowArea = largest
            var end = start + 1
            while end < scaled.count {
                let candidate = scaled[end].area
                let current = worstRatio(largest: largest, smallest: scaled[end - 1].area, area: rowArea, side: side)
                let next = worstRatio(largest: largest, smallest: candidate, area: rowArea + candidate, side: side)
                if next > current { break }
                rowArea += candidate
                end += 1
            }
            place(row: scaled[start..<end], area: rowArea, in: &free, tiles: &tiles)
            start = end
        }
        return tiles
    }

    private static func worstRatio(largest: Double, smallest: Double, area: Double, side: Double) -> Double {
        guard area > 0, side > 0, smallest > 0 else { return .infinity }
        let sideSquared = side * side
        let areaSquared = area * area
        return max(sideSquared * largest / areaSquared, areaSquared / (sideSquared * smallest))
    }

    private static func place<ID: Hashable & Sendable>(
        row: ArraySlice<(id: ID, area: Double)>,
        area: Double,
        in free: inout CGRect,
        tiles: inout [Tile<ID>]
    ) {
        if free.width >= free.height {
            // A column along the left edge.
            let width = free.height > 0 ? CGFloat(area / Double(free.height)) : 0
            var y = free.minY
            for item in row {
                let height = width > 0 ? CGFloat(item.area / Double(width)) : 0
                tiles.append(Tile(id: item.id, rect: CGRect(x: free.minX, y: y, width: width, height: height)))
                y += height
            }
            free = CGRect(x: free.minX + width, y: free.minY, width: max(free.width - width, 0), height: free.height)
        } else {
            // A row along the top edge.
            let height = free.width > 0 ? CGFloat(area / Double(free.width)) : 0
            var x = free.minX
            for item in row {
                let width = height > 0 ? CGFloat(item.area / Double(height)) : 0
                tiles.append(Tile(id: item.id, rect: CGRect(x: x, y: free.minY, width: width, height: height)))
                x += width
            }
            free = CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(free.height - height, 0))
        }
    }
}
