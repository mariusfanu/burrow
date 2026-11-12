import BurrowCore
import SwiftUI

struct TreemapTile: View {
    let entry: AnalyzeResult.Entry
    let rank: Int
    let color: UInt32
    let rect: CGRect
    let container: CGSize
    let isSelected: Bool
    let isInteractive: Bool
    let model: AnalyzeModel
    let cli: CLIInfo

    @State private var hasArrived = false

    /// Read here, not in the map, so that moving the pointer doesn't lay out every tile again.
    private var isHovered: Bool { model.hovered == entry.path }

    private var accessibilityDescription: String {
        let base = "\(entry.name), \(entry.size.fileSize)"
        return model.canTrash(entry) ? base : "\(base), protected"
    }

    var body: some View {
        TileFace(title: entry.name, size: entry.size.fileSize, symbol: entry.isDir ? "folder.fill" : "doc.fill", rect: rect, color: color, isHovered: isHovered, isSelected: isSelected)
            .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
            .scaleEffect(arrivalScale)
            .opacity(hasArrived || !isInteractive ? 1 : 0)
            .contentShape(.rect(cornerRadius: Theme.Radius.tile))
            .onHover { inside in model.setHovered(entry.path, inside: inside) }
            .gesture(selectionGesture)
            .allowsHitTesting(isInteractive)
            // With Keyboard Navigation on, Tab reaches each tile, Space selects and Return opens.
            .focusable(isInteractive)
            .onKeyPress(.space) {
                select(extending: true)
                return .handled
            }
            .onKeyPress(.return) {
                open()
                return .handled
            }
            .help("\(entry.path)\n\(entry.size.fileSize)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(extending: false) }
            .accessibilityAction(named: "Open", open)
            .contextMenu {
                Button(entry.isDir ? "Open" : "Show in Finder", action: open)
                if entry.isDir {
                    Button("Show in Finder", action: reveal)
                }
                Button(isSelected ? "Deselect" : "Select") { select(extending: true) }
                    .disabled(!model.canTrash(entry))
            }
            .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
            .animation(Motion.snap, value: isSelected)
            .onAppear(perform: arrive)
    }

    private var arrivalScale: CGFloat {
        guard isInteractive, !hasArrived, !Motion.isReduced else { return 1 }
        return 0.94
    }

    /// One exclusive recognizer prevents an ordinary tap from replacing a Command-click.
    private var selectionGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture().modifiers(.command).exclusively(before: TapGesture()))
            .onEnded { value in
                switch value {
                case .first: open()
                case .second(.first): select(extending: true)
                case .second(.second): select(extending: false)
                }
            }
    }

    private func arrive() {
        guard isInteractive, !hasArrived else { return }
        withAnimation(Motion.settle.delay(Motion.stagger(rank, step: 0.016))) {
            hasArrived = true
        }
    }

    private func select(extending: Bool) {
        model.click(entry, extending: extending)
    }

    private func open() {
        guard entry.isDir else {
            reveal()
            return
        }
        let normalized = CGRect(
            x: rect.minX / max(container.width, 1),
            y: rect.minY / max(container.height, 1),
            width: rect.width / max(container.width, 1),
            height: rect.height / max(container.height, 1)
        )
        model.open(entry, tint: color, rect: normalized, cli: cli)
    }

    private func reveal() {
        FilePicker.reveal(entry.path)
    }
}
