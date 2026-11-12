import SwiftUI

/// Every page in the sidebar. App-level setup lives in the Settings window instead.
enum Screen: String, CaseIterable, Identifiable, Hashable {
    case overview, clean, uninstall, purge, installers, slim, optimize, analyze, status, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .purge: "Project Purge"
        case .installers: "Installers"
        case .slim: "Slim Apps"
        case .optimize: "Optimize"
        case .analyze: "Disk Explorer"
        case .status: "System Status"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .clean: "sparkles"
        case .uninstall: "trash"
        case .purge: "hammer"
        case .installers: "shippingbox"
        case .slim: "scissors"
        case .optimize: "wrench.and.screwdriver"
        case .analyze: "chart.pie"
        case .status: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        }
    }

    var summary: String {
        switch self {
        case .overview: "Your Mac at a glance"
        case .clean: "Caches, logs and leftovers"
        case .uninstall: "Apps and their leftovers"
        case .purge: "Old build artifacts"
        case .installers: "Disk images and packages"
        case .slim: "Intel code in universal apps"
        case .optimize: "Caches, DNS and services"
        case .analyze: "See what fills the disk"
        case .status: "Live health and processes"
        case .history: "Everything that changed"
        }
    }

    /// Position in the sidebar, which sets the direction of page transitions.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Every page except the Overview, which is where they are listed.
    static let tools = allCases.filter { $0 != .overview }

    /// Command-1 through Command-9 for the first nine pages.
    var goShortcut: KeyboardShortcut? {
        order < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(order + 1)")), modifiers: .command) : nil
    }

    struct Group: Identifiable {
        let title: String?
        let screens: [Screen]
        var id: String { title ?? "top" }
    }

    static let groups = [
        Group(title: nil, screens: [.overview]),
        Group(title: "Reclaim", screens: [.clean, .uninstall, .purge, .installers, .slim]),
        Group(title: "Maintain", screens: [.optimize]),
        Group(title: "Inspect", screens: [.analyze, .status, .history]),
    ]
}

extension Screen {
    /// The page a CLI command belongs to. Every command is named like its page except
    /// `mo installer`.
    init?(commandName: String) {
        switch commandName {
        case "installer": self = .installers
        default:
            guard let screen = Screen(rawValue: commandName) else { return nil }
            self = screen
        }
    }
}
