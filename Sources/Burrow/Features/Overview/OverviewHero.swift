import BurrowCore
import SwiftUI

struct OverviewHero: View {
    let cli: CLIInfo
    @Environment(AppModel.self) private var app

    private var disk: StatusSnapshot.Disk? { app.status.snapshot?.rootDisk }
    private var used: Int64 { max(disk?.used ?? 0, 0) }
    private var total: Int64 { max(disk?.total ?? 0, 0) }
    private var free: Int64 { max(total - used, 0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            StrataScene(usedFraction: total > 0 ? Double(used) / Double(total) : 0)
                .mask {
                    // The scene melts into the page instead of ending at a hard edge.
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .backgroundExtensionEffect()
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                Spacer(minLength: 56)
                // Until the disk is measured, a soft placeholder holds the number's place, so
                // nothing jumps when it lands.
                HeroNumber(text: total > 0 ? free.fileSize : "000.00 GB", size: 52, value: Double(free))
                    .redacted(reason: total > 0 ? [] : .placeholder)
                    .accessibilityHidden(total == 0)
                Text(diskCaption)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                HStack {
                    Button("Scan for Space", action: scan)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    Button("Explore Disk", action: explore)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(.top, Theme.Space.item)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.page + 4)
            .accessibilityElement(children: .contain)
        }
        .frame(height: 350)
        .animation(Motion.settle, value: total > 0)
    }

    private var diskCaption: String {
        if total > 0 { return "available · \(used.fileSize) of \(total.fileSize) used" }
        // Only Mole's status tool reports this, so without it there's nothing to wait for.
        if !cli.hasBundledTools || app.status.errorMessage != nil { return "Disk usage isn’t available" }
        return "Measuring your disk"
    }

    private func scan() {
        app.selection = .clean
        if app.clean.state == .idle { app.clean.scan(cli: cli) }
    }

    private func explore() {
        app.selection = .analyze
    }
}
