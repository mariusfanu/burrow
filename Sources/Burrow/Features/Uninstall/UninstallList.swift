import AppKit
import BurrowCore
import SwiftUI

struct UninstallList: View {
    @Bindable var model: UninstallModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var isSearchFocused: Bool
    /// The row under keyboard focus, which arrow keys move and Space toggles.
    @State private var focusedRow: InstalledApp.ID?

    var body: some View {
        let largestSize = model.largestSize
        let visibleApps = model.visibleApps
        List(selection: $focusedRow) {
            ForEach(visibleApps.enumerated(), id: \.element.id) { index, item in
                UninstallAppRow(
                    app: item,
                    sizeState: model.sizeState(for: item),
                    largestSize: largestSize,
                    isSelected: model.selection.contains(item.id),
                    model: model,
                    focusedRow: $focusedRow
                )
                .tag(item.id)
                .arrives(index: index)
                .transition(Motion.content(scale: 0.96, reduced: reduceMotion))
            }
        }
        .onKeyPress(.space, action: toggleFocused)
        .onCommand(#selector(NSResponder.selectAll(_:)), perform: selectAll)
        .onHover { inside in if inside { model.noteInteraction() } }
        .onChange(of: focusedRow) { model.noteInteraction() }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .animation(Motion.isReduced(reduceMotion) ? nil : Motion.lift(reduced: reduceMotion), value: model.sortOrder)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search Apps")
        .searchFocused($isSearchFocused)
        .onChange(of: app.isSearchFocused) {
            if app.isSearchFocused {
                isSearchFocused = true
                app.isSearchFocused = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                UninstallOptionsMenu(model: model, isPreview: app.effectivePreview)
            }
        }
        .overlay {
            if model.apps.isEmpty {
                ContentUnavailableView("No Apps Found", systemImage: "app.dashed", description: Text("Mole didn’t list any apps it can remove."))
            } else if visibleApps.isEmpty {
                ContentUnavailableView.search
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let error = model.errorMessage {
                    NoticeBar(text: error) { model.errorMessage = nil }
                        .transition(Motion.rise(reduced: reduceMotion))
                }
                if let notice = model.activeOptionsNotice {
                    NoticeBar(text: notice, dismiss: model.clearRemovalOptions)
                        .transition(Motion.rise(reduced: reduceMotion))
                }
            }
        }
        .alert("Delete Without Using the Trash?", isPresented: $model.isConfirmingPermanent) {
            Button("Cancel", role: .cancel) {}
            Button("Skip the Trash", role: .destructive, action: skipTrash)
        } message: {
            Text("Removed files can’t be restored. Using the Trash is the safer choice.")
        }
    }

    private func toggleFocused() -> KeyPress.Result {
        guard let item = model.visibleApps.first(where: { $0.id == focusedRow }) else { return .ignored }
        focusedRow = item.id
        withAnimation(Motion.snap(reduced: reduceMotion)) { model.toggleSelection(item.id) }
        return .handled
    }

    private func selectAll() {
        withAnimation(Motion.snap(reduced: reduceMotion)) { model.selection = Set(model.visibleApps.map(\.id)) }
    }

    private func skipTrash() {
        model.deletePermanently = true
    }
}
