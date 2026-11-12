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
                    documentButton("Show Notice in Finder", file: "NOTICE")

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    documentButton("Show License in Finder", file: "LICENSE")
                }

                Text("Copyright © 2026 Marius Fanu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.micro)
            }
        }
        .padding(Theme.Space.page)
    }

    private func documentButton(_ title: LocalizedStringKey, file: String) -> some View {
        let url = Bundle.main.url(forResource: file, withExtension: nil) ?? localDocument(file)
        return Button(title) {
            if let url { FilePicker.reveal(url.path) }
        }
        .buttonStyle(.link)
        .font(.caption)
        .disabled(url == nil)
    }

    private func localDocument(_ file: String) -> URL? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appending(path: file)
        return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }
}

/// A clickable row opening a related project or developer URL.
private struct AboutLinkRow: View {
    let title: String
    let name: String
    let detail: String
    let systemImage: String
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Theme.Space.cluster) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Space.item)

                Image(systemName: "arrow.up.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .scaleEffect(isHovered && !Motion.isReduced ? 1.08 : 1)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Motion.snap) {
                isHovered = hovering
            }
        }
        .help("Open \(url.absoluteString)")
    }
}

/// Controls presenting the dedicated About panel.
@MainActor
final class AboutPanelController {
    static let shared = AboutPanelController()
    private var window: NSPanel?

    private init() {}

    func show() {
        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Burrow"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()

        let hosting = NSHostingView(rootView: AboutWindowContent())
        panel.contentView = hosting
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct AboutWindowContent: View {
    var body: some View {
        ScrollView {
            AboutView()
                .padding(.top, Theme.Space.item)
        }
        .frame(width: 440, height: 520)
    }
}
