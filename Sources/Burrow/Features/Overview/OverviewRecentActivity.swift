import BurrowCore
import SwiftUI

struct OverviewRecentActivity: View {
    let sessions: [HistoryReport.Session]
    @Environment(AppModel.self) private var app

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.row) {
                HStack {
                    Text("Recent Activity")
                        .font(.headline)
                    Spacer()
                    Button("All History", action: showHistory)
                        .buttonStyle(.link)
                }
                Surface(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(sessions.enumerated(), id: \.element.id) { index, session in
                            if index > 0 {
                                Divider().padding(.leading, 48)
                            }
                            OverviewSessionRow(session: session)
                        }
                    }
                }
            }
            .arrives(index: 9)
        }
    }

    private func showHistory() {
        app.selection = .history
    }
}
