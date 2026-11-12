import AppKit
import SwiftUI

/// Information about Burrow, its creator Marius Fanu, websites and license.
struct AboutView: View {
    init() {}

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    static let personalWebsiteURL = URL(string: "https://mariusfanu.com")!
    static let burrowWebsiteURL = URL(string: "https://burrow.mariusfanu.com")!
    static let moleRepoURL = URL(string: "https://github.com/tw93/Mole")!

    private var appIcon: NSImage {
        NSApp?.applicationIconImage ?? NSImage(size: NSSize(width: 80, height: 80))
    }

    var body: some View {
        VStack(spacing: Theme.Space.group) {
            VStack(spacing: Theme.Space.item) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.tight) {
                    Text("Burrow")
                        .font(.title2).bold()
                        .accessibilityAddTraits(.isHeader)

                    Text(appVersion)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("A native macOS front end for the Mole CLI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Space.snug)

            Surface(padding: Theme.Space.card) {
                VStack(alignment: .leading, spacing: Theme.Space.cluster) {
                    AboutLinkRow(
                        title: "Created by",
                        name: "Marius Fanu",
                        detail: "mariusfanu.com",
                        systemImage: "person.crop.circle.fill",
                        url: Self.personalWebsiteURL
                    )

                    Divider()

                    AboutLinkRow(
                        title: "Burrow Website",
                        name: "burrow.mariusfanu.com",
                        detail: "Official website & updates",
                        systemImage: "globe",
                        url: Self.burrowWebsiteURL
                    )

                    Divider()

                    AboutLinkRow(
                        title: "Mole CLI",
                        name: "tw93/Mole",
                        detail: "Core command-line tool",
                        systemImage: "terminal.fill",
                        url: Self.moleRepoURL
                    )
                }
            }

            VStack(spacing: Theme.Space.tight) {
                Text("Burrow is an independent, unofficial front end distributed under the GNU General Public License v3.0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.cluster) {
                    AboutDocumentButton(title: "Show Notice in Finder", file: "NOTICE")

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    AboutDocumentButton(title: "Show License in Finder", file: "LICENSE")
                }

                Text("Copyright © 2026 Marius Fanu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.micro)
            }
        }
        .padding(Theme.Space.page)
    }
}
