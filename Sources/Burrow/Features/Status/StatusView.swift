import SwiftUI

struct StatusView: View {
    let store: StatusStore
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let snapshot = store.snapshot {
                StatusDashboard(store: store, snapshot: snapshot)
                    .transition(Motion.materialize(reduced: reduceMotion))
            } else if let message = store.errorMessage {
                ContentUnavailableView {
                    Label("Live Status Isn’t Available", systemImage: "waveform.path.ecg")
                } description: {
                    Text(message)
                } actions: {
                    if let cli = app.cli {
                        Button("Retry", systemImage: "arrow.clockwise") { store.retry(cli: cli) }
                    }
                }
            } else {
                WorkingView(title: "Reading This Mac’s Vital Signs")
            }
        }
        .animation(Motion.glide(reduced: reduceMotion), value: store.snapshot == nil)
        .animation(Motion.glide(reduced: reduceMotion), value: store.errorMessage == nil)
        .toolbar {
            if store.errorMessage != nil, let cli = app.cli {
                ToolbarItem(placement: .automatic) {
                    Button("Retry", systemImage: "arrow.clockwise") { store.retry(cli: cli) }
                }
            }
        }
    }
}
