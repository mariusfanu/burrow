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
            TreemapLayer(snapshot: outgoing, model: model, cli: cli, isInteractive: false)
                .modifier(ZoomEffect(progress: progress, rect: model.zoomRect, size: size, isZoomingIn: model.isZoomingIn, role: .outgoing))
        }
    }

    private func incomingLayer(in size: CGSize) -> some View {
        TreemapLayer(snapshot: snapshot, model: model, cli: cli, isInteractive: true)
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
