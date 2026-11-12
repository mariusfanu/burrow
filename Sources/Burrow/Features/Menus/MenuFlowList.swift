import AppKit
import BurrowCore
import SwiftUI

struct MenuFlowList: View {
    let model: MenuFlowModel
    /// The row under keyboard focus, which arrow keys move and Space toggles.
    @State private var focusedRow: MenuItem.ID?

    var body: some View {
        let largestBytes = model.items.map(\.bytes).max() ?? 0
        List(selection: $focusedRow) {
            ForEach(model.items.enumerated(), id: \.element.id) { index, item in
                MenuItemRow(
                    item: item,
                    largestBytes: largestBytes,
                    isSelected: model.selection.contains(item.index),
                    toggle: { toggle(item) }
                )
                .tag(item.id)
                .arrives(index: index)
            }
        }
        .onKeyPress(.space, action: toggleFocused)
        .onCommand(#selector(NSResponder.selectAll(_:)), perform: selectAll)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            NoticeBar(text: model.configuration.subtitle, symbol: "")
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu("Select", systemImage: "checklist") {
                    Button("Select All", action: selectAll)
                    Button("Deselect All", action: deselectAll)
                }
                .help("Select or deselect every row")
            }
        }
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView(model.configuration.emptyTitle, systemImage: model.configuration.screen.symbol)
            }
        }
    }

    private func toggleFocused() -> KeyPress.Result {
        guard let item = model.items.first(where: { $0.id == focusedRow }) else { return .ignored }
        toggle(item)
        return .handled
    }

    private func toggle(_ item: MenuItem) {
        focusedRow = item.id
        withAnimation(Motion.snap) {
            if model.selection.contains(item.index) {
                model.selection.remove(item.index)
            } else {
                model.selection.insert(item.index)
            }
        }
    }

    private func selectAll() {
        withAnimation(Motion.snap) { model.selection = Set(model.items.map(\.index)) }
    }

    private func deselectAll() {
        withAnimation(Motion.snap) { model.selection = [] }
    }
}
