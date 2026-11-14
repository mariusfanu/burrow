import SwiftUI

struct SmallItemsTile: View {
    let count: Int
    let size: Int64
    let rect: CGRect

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .fill(Color(hex: 0x6E6E73))
            TileLabel(title: "\(count) smaller items", size: size.fileSize, symbol: "square.grid.2x2.fill", rect: rect)
        }
        .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
        .help("See these in the list")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) smaller items, \(size.fileSize)")
        .accessibilityHint("See these in the list")
        .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
    }
}
