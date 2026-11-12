import BurrowCore
import SwiftUI

struct CleanSectionDetails: View {
    let section: CleanReport.Section
    let isEditable: Bool
    let protected: Set<String>
    let protect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            ForEach(section.rows) { LogRow(line: $0) }
            if !section.paths.isEmpty {
                Text("Files")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.row)
                ForEach(section.paths.prefix(200)) { entry in
                    CleanPathRow(
                        entry: entry,
                        isProtected: protected.contains(entry.path),
                        isEditable: isEditable,
                        protect: protect
                    )
                }
                if section.paths.count > 200 {
                    Text("And \(section.paths.count - 200) more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.card)
    }
}
