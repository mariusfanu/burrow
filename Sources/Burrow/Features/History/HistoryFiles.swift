import BurrowCore
import SwiftUI

struct HistoryFiles: View {
    let rows: [HistoryReport.Deletion]
    var isLoading = false

    var body: some View {
        if isLoading {
            WorkingView(title: "Reading the Logs")
        } else if rows.isEmpty {
            ContentUnavailableView(
                "No Files Recorded",
                systemImage: "doc",
                description: Text("Individual removals appear here once Mole’s deletion log has entries.")
            )
        } else {
            List(rows) { HistoryDeletionRow(row: $0) }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
