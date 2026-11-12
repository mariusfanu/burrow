import BurrowCore
import SwiftUI

/// The diagnosis and plan, with each task group arriving in turn.
struct OptimizePlan: View {
    let lines: [LogLine]

    private var groups: [PlanGroup] {
        var result: [PlanGroup] = []
        var current = PlanGroup(title: nil, lines: [])
        for line in lines {
            if line.kind == .section {
                if !current.lines.isEmpty { result.append(current) }
                current = PlanGroup(title: line.title, lines: [])
            } else {
                current.lines.append(line)
            }
        }
        if !current.lines.isEmpty { result.append(current) }
        return result
    }

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: Theme.Space.cluster, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.cluster) {
                ForEach(groups.enumerated(), id: \.element.id) { index, group in
                    Surface {
                        VStack(alignment: .leading, spacing: Theme.Space.snug) {
                            if let title = group.title {
                                Text(title)
                                    .font(.headline)
                            }
                            ForEach(group.lines) { LogRow(line: $0) }
                        }
                    }
                    .arrives(index: index)
                }
            }
            .padding(Theme.Space.page)
        }
    }

    private struct PlanGroup: Identifiable {
        let title: String?
        var lines: [LogLine]
        var id: String { title ?? "summary" }
    }
}
