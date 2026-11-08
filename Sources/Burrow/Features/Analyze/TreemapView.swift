import BurrowCore
import SwiftUI

/// The treemap and its signature move. Opening a folder grows its tile until the tile fills
/// the map, and the folder's contents appear inside it in shades of the same color. Going
/// back reverses the trip and comes to rest exactly on the tile you came from.
struct TreemapStage: View {
    let model: AnalyzeModel
    let cli: CLIInfo

    @State private var outgoing: MapSnapshot?
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if model.isZoomingIn {
                    outgoingLayer(in: proxy.size)
                    plate(in: proxy.size)
                    incomingLayer(in: proxy.size)
                } else {
                    incomingLayer(in: proxy.size)
                    plate(in: proxy.size)
                    outgoingLayer(in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .onChange(of: snapshot) { oldValue, newValue in
            if oldValue.id != newValue.id { startZoom(from: oldValue) }
        }
    }

    @ViewBuilder
    private func outgoingLayer(in size: CGSize) -> some View {
        if let outgoing {
            MapLayer(snapshot: outgoing, model: model, cli: cli, isInteractive: false)
                .modifier(ZoomEffect(progress: progress, rect: model.zoomRect, size: size, isZoomingIn: model.isZoomingIn, role: .outgoing))
        }
    }

    private func incomingLayer(in size: CGSize) -> some View {
        MapLayer(snapshot: snapshot, model: model, cli: cli, isInteractive: true)
            .modifier(ZoomEffect(progress: outgoing == nil ? 1 : progress, rect: model.zoomRect, size: size, isZoomingIn: model.isZoomingIn, role: .incoming))
    }

    @ViewBuilder
    private func plate(in size: CGSize) -> some View {
        if outgoing != nil, let rect = model.zoomRect, let tint = model.zoomTint {
            ZoomPlate(progress: progress, rect: rect, tint: tint, size: size, isZoomingIn: model.isZoomingIn)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var snapshot: MapSnapshot {
        MapSnapshot(
            id: model.current?.id ?? "/",
            name: model.current?.name ?? "",
            tint: model.current?.tint,
            entries: model.entries,
            isLoading: model.isLoading
        )
    }

    private func startZoom(from old: MapSnapshot) {
        guard !Motion.isReduced else { return }
        var start = Transaction()
        start.disablesAnimations = true
        withTransaction(start) {
            outgoing = old
            progress = 0
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.03)) {
            progress = 1
        } completion: {
            outgoing = nil
        }
    }
}

/// What a map layer shows, captured so that the outgoing layer stays still while it leaves.
struct MapSnapshot: Equatable {
    let id: String
    let name: String
    let tint: UInt32?
    let entries: [AnalyzeResult.Entry]
    let isLoading: Bool
}

/// The opened tile itself, growing to fill the map or shrinking back into place. It's solid,
/// so the two maps never show through each other.
@Animatable
private struct ZoomPlate: View {
    var progress: CGFloat
    @AnimatableIgnored var rect: CGRect
    @AnimatableIgnored var tint: UInt32
    @AnimatableIgnored var size: CGSize
    @AnimatableIgnored var isZoomingIn: Bool

    var body: some View {
        let amount = min(max(progress, 0), 1)
        let growth = isZoomingIn ? amount : 1 - amount
        let tile = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        let frame = CGRect(
            x: tile.minX * (1 - growth),
            y: tile.minY * (1 - growth),
            width: tile.width + (size.width - tile.width) * growth,
            height: tile.height + (size.height - tile.height) * growth
        )
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(Color(hex: tint))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .fill(LinearGradient(colors: [.white.opacity(0.1), .clear, .black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            // Once the new tiles cover it, the plate gets out of the way of the gaps between them.
            .opacity(isZoomingIn ? 1 - Double(min(max((amount - 0.82) / 0.18, 0), 1)) : 1)
    }
}

@Animatable
private struct ZoomEffect: ViewModifier {
    enum Role { case incoming, outgoing }

    var progress: CGFloat
    @AnimatableIgnored var rect: CGRect?
    @AnimatableIgnored var size: CGSize
    @AnimatableIgnored var isZoomingIn: Bool
    @AnimatableIgnored var role: Role

    func body(content: Content) -> some View {
        let transform = currentTransform
        return content
            .scaleEffect(transform.scale)
            .offset(transform.offset)
            .opacity(transform.opacity)
    }

    /// Where a map sits when the opened tile fills the view, using one scale so nothing distorts.
    private var zoomed: (scale: CGFloat, offset: CGSize) {
        guard let rect, rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else {
            return (1.08, .zero)
        }
        let scale = max(1 / rect.width, 1 / rect.height)
        let centerX = (rect.midX - 0.5) * size.width
        let centerY = (rect.midY - 0.5) * size.height
        return (scale, CGSize(width: -centerX * scale, height: -centerY * scale))
    }

    private var currentTransform: (scale: CGFloat, offset: CGSize, opacity: Double) {
        let amount = min(max(progress, 0), 1)
        switch (role, isZoomingIn) {
        case (.outgoing, true):
            // The old map zooms past behind the growing plate.
            return mix(from: (1, .zero), to: zoomed, amount: amount, opacity: 1 - ramp(amount, start: 0.1, end: 0.55))
        case (.incoming, true):
            // The contents appear inside the plate once it's large enough to hold them.
            return mix(from: (0.965, .zero), to: (1, .zero), amount: amount, opacity: ramp(amount, start: 0.42, end: 0.85))
        case (.outgoing, false):
            // The contents leave first, uncovering the plate.
            return mix(from: (1, .zero), to: (0.965, .zero), amount: amount, opacity: 1 - ramp(amount, start: 0, end: 0.35))
        case (.incoming, false):
            // The parent map settles back from the zoomed position.
            return mix(from: zoomed, to: (1, .zero), amount: amount, opacity: ramp(amount, start: 0.1, end: 0.6))
        }
    }

    private func ramp(_ amount: CGFloat, start: CGFloat, end: CGFloat) -> Double {
        Double(min(max((amount - start) / (end - start), 0), 1))
    }

    private func mix(
        from start: (scale: CGFloat, offset: CGSize),
        to end: (scale: CGFloat, offset: CGSize),
        amount: CGFloat,
        opacity: Double
    ) -> (scale: CGFloat, offset: CGSize, opacity: Double) {
        // Mixing scale in log space keeps the zoom's speed even across a large change.
        let scale = exp(log(start.scale) + (log(end.scale) - log(start.scale)) * amount)
        let width = start.offset.width + (end.offset.width - start.offset.width) * amount
        let height = start.offset.height + (end.offset.height - start.offset.height) * amount
        return (scale, CGSize(width: width, height: height), opacity)
    }
}

/// One map: either its tiles, or the folder's own color while it's being measured.
private struct MapLayer: View {
    let snapshot: MapSnapshot
    let model: AnalyzeModel
    let cli: CLIInfo
    let isInteractive: Bool

    var body: some View {
        GeometryReader { proxy in
            if snapshot.isLoading, snapshot.entries.isEmpty {
                MeasuringPlate(name: snapshot.name, tint: snapshot.tint)
                    .transition(.opacity)
            } else if snapshot.entries.isEmpty {
                ContentUnavailableView(model.emptyStateTitle, systemImage: "folder")
            } else {
                tiles(in: proxy.size)
            }
        }
        .animation(Motion.isReduced ? nil : Motion.lift, value: snapshot.entries.map(\.id))
    }

    private func tiles(in size: CGSize) -> some View {
        let map = EntryMap(entries: snapshot.entries, in: CGRect(origin: .zero, size: size))
        let lookup = Dictionary(map.shown.enumerated().map { ($0.element.path, $0) }, uniquingKeysWith: { first, _ in first })

        return ZStack(alignment: .topLeading) {
            ForEach(map.tiles, id: \.id) { tile in
                if let found = lookup[tile.id] {
                    TileView(
                        entry: found.element,
                        rank: found.offset,
                        color: Theme.tile(rank: found.offset, parent: snapshot.tint),
                        rect: tile.rect,
                        container: size,
                        isSelected: model.selection.contains(found.element.path),
                        isInteractive: isInteractive,
                        model: model,
                        cli: cli
                    )
                    .transition(Motion.content(scale: 0.7))
                } else {
                    SmallItemsTile(count: map.restCount, size: map.restSize, rect: tile.rect)
                }
            }
        }
    }
}

/// The folder's color filling the map while its contents are measured, with a slow sheen.
private struct MeasuringPlate: View {
    let name: String
    let tint: UInt32?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .fill(tint.map { Color(hex: $0) } ?? Color.secondary.opacity(0.18))
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .fill(.black.opacity(0.08))
                .phaseAnimator([false, true]) { view, isBright in
                    view.opacity(Motion.isReduced ? 0.5 : (isBright ? 1 : 0.1))
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            VStack(spacing: Theme.Space.row) {
                ProgressView()
                    .controlSize(.small)
                Text("Measuring \(name)")
                    .font(.callout)
            }
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TileView: View {
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

/// Keep text on its contrast-tested solid color. Hover only changes the edge.
struct TileFace: View {
    let title: String
    let size: String
    let symbol: String
    let rect: CGRect
    let color: UInt32
    let isHovered: Bool
    var isSelected = false

    @Environment(\.colorSchemeContrast) private var contrast

    /// Small tiles get smaller corners, so a sliver stays a rectangle instead of becoming a
    /// pill or a dot.
    private var radius: CGFloat {
        min(Theme.Radius.tile, max(min(rect.width, rect.height) * 0.22, 2))
    }

    private var edgeOpacity: Double {
        if isHovered { return 0.8 }
        return contrast == .increased ? 0.7 : 0.22
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(hex: color))
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.white.opacity(edgeOpacity), lineWidth: isHovered ? 2 : 1)
            TileLabel(title: title, size: size, symbol: symbol, rect: rect)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color(hex: color))
                    .padding(5)
                    .transition(Motion.content(scale: 0.3))
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2.5)
        }
        .clipShape(.rect(cornerRadius: radius))
        .animation(Motion.snap, value: isHovered)
    }
}

private struct SmallItemsTile: View {
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
        .offset(x: rect.minX + 1.5, y: rect.minY + 1.5)
    }
}

private struct TileLabel: View {
    let title: String
    let size: String
    let symbol: String
    let rect: CGRect

    var body: some View {
        if rect.width > 70, rect.height > 38 {
            VStack(spacing: Theme.Space.micro) {
                HStack(spacing: Theme.Space.tight) {
                    if rect.width > 120 {
                        Image(systemName: symbol)
                            .font(.caption)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.callout)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(size)
                    .font(.callout)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.snug)
        }
    }
}
