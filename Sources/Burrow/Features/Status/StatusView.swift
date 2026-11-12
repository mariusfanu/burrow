import SwiftUI

struct StatusView: View {
    let store: StatusStore
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            if let snapshot = store.snapshot {
                StatusDashboard(store: store, snapshot: snapshot)
                    .transition(Motion.materialize)
            } else if let message = store.errorMessage {
                ContentUnavailableView("Live Status Isn’t Available", systemImage: "waveform.path.ecg", description: Text(message))
            } else {
                WorkingView(title: "Reading This Mac’s Vital Signs")
            }
        }
        .animation(Motion.glide, value: store.snapshot == nil)
        .toolbar {
            if store.errorMessage != nil, let cli = app.cli {
                ToolbarItem(placement: .automatic) {
                    Button("Retry", systemImage: "arrow.clockwise") { store.retry(cli: cli) }
                }
            }
        }
    }
}
