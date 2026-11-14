import BurrowCore
import SwiftUI

struct HistorySessions: View {
    let model: HistoryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleSessions: [HistoryReport.Session] {
        (model.report?.sessions ?? []).filter { session in
            guard session.recordedWork else { return false }
            return model.includesPreviews || !session.isPreview
        }
    }

    var body: some View {
        let sessions = visibleSessions
        let realSessions = sessions.filter { !$0.isPreview }
        let totalFreed = realSessions.map(\.bytes).saturatingSum
        if sessions.isEmpty {
            if model.isLoading, model.report == nil {
                WorkingView(title: "Reading the Logs")
            } else {
                ContentUnavailableView(
                    "Nothing Here Yet",
                    systemImage: "clock",
                    description: Text("Sessions appear here after Mole changes something.")
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.group) {
                    VStack(alignment: .leading, spacing: Theme.Space.micro) {
                        HeroNumber(text: totalFreed.fileSize, value: Double(totalFreed))
                        Text("freed across ^[\(realSessions.count) session](inflect: true)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .arrives()
                    LazyVStack(spacing: Theme.Space.row) {
                        ForEach(sessions.enumerated(), id: \.element.id) { index, session in
                            HistorySessionRow(session: session)
                                .arrives(index: index + 1)
                        }
                    }
                    .animation(Motion.settle(reduced: reduceMotion), value: sessions.map(\.id))
                }
                .padding(Theme.Space.page)
            }
        }
    }
}
