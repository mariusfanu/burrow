import BurrowCore
import SwiftUI

/// Stable inputs let unchanged sections skip updates while the scan progresses.
struct CleanSectionCard: View {
    let section: CleanReport.Section
    let largestBytes: Int64
    @Bindable var model: CleanModel
    let cli: CLIInfo
    let isEditable: Bool

    var body: some View {
        Surface(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CleanSectionHeader(section: section, largestBytes: largestBytes,
                                   isExpanded: $model[isExpanded: section.id])
                if model[isExpanded: section.id] {
                    Divider()
                    CleanSectionDetails(section: section, isEditable: isEditable,
                                        protected: model.protectedThisSession, protect: protect)
                        .transition(Motion.content(y: -6))
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
    }

    private func protect(_ path: String) {
        withAnimation(Motion.snap) { model.protect(path: path, cli: cli) }
    }
}
