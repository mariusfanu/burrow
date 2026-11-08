import BurrowCore
import SwiftUI

struct OptimizeView: View {
    @Bindable var model: OptimizeModel
    let cli: CLIInfo

    var body: some View {
        ZStack {
            switch model.state {
            case .idle:
                ToolIntro(
                    symbol: "wrench.and.screwdriver",
                    title: "Refresh Caches and Services",
                    message: "Bounded maintenance such as rebuilding icon caches, refreshing DNS and repairing preferences. See the plan before anything runs.",
                    errorMessage: model.errorMessage
                ) {
                    Button("Check This Mac", action: check)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(Motion.materialize)
            case .previewing:
                WorkingView(title: "Checking This Mac", detail: model.activity)
            case .review:
                VStack(spacing: 0) {
                    if let message = model.errorMessage {
                        InlineNotice(text: message)
                            .padding(.horizontal, Theme.Space.page)
                            .padding(.top, Theme.Space.page)
                    }
                    OptimizePlan(lines: model.lines)
                }
                .transition(Motion.materialize)
            case .running:
                RunPanel(run: model.run)
                    .transition(Motion.materialize)
            }
        }
        .animation(Motion.glide, value: model.state)
        .alert("Run Maintenance Now?", isPresented: $model.isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Run", action: run)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Some tasks ask for your password. Tasks you’ve turned off in Settings are skipped.")
        }
    }

    private func check() {
        model.preview(cli: cli)
    }

    private func run() {
        model.runMaintenance(cli: cli, preview: false)
    }
}

/// The diagnosis and plan, with each task group arriving in turn.
private struct OptimizePlan: View {
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
