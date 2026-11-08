import Foundation

/// What differs between the three flows that use a CLI selection menu.
struct MenuFlowConfiguration {
    let screen: Screen
    let subtitle: String
    let command: String
    let idleTitle: String
    let idleMessage: String
    let emptyTitle: String
    let actionVerb: String
    let workingTitle: String
    let doneTitle: String
    let scanTitle: String
    /// Whether `--dry-run` still shows the menu. `mo slim --dry-run` only prints a list.
    let previewShowsMenu: Bool
    let managesScanPaths: Bool
    /// What confirming does to the selected rows, shown beside the CLI's question.
    let consequence: String
    let isIrreversible: Bool
    /// Whether confirming changes what the Uninstall page lists.
    let changesApps: Bool

    static let purge = MenuFlowConfiguration(
        screen: .purge,
        subtitle: "Build artifacts you can always regenerate. Recent projects start unselected.",
        command: "purge",
        idleTitle: "Clear Old Build Artifacts",
        idleMessage: "Finds node_modules, target, .build, DerivedData and similar folders in your projects, so you can choose what goes.",
        emptyTitle: "No Artifacts to Purge",
        actionVerb: "Purge",
        workingTitle: "Purging Artifacts",
        doneTitle: "Purged",
        scanTitle: "Measuring Project Artifacts",
        previewShowsMenu: true,
        managesScanPaths: true,
        consequence: "Selected folders are deleted permanently, without using the Trash. Build tools can create them again.",
        isIrreversible: true,
        changesApps: false
    )

    static let installers = MenuFlowConfiguration(
        screen: .installers,
        subtitle: "Disk images, packages and archives you probably don't need anymore.",
        command: "installer",
        idleTitle: "Find Leftover Installers",
        idleMessage: "Looks for .dmg, .pkg, .iso, .xip and installer .zip files, so you can choose what goes.",
        emptyTitle: "No Installers Found",
        actionVerb: "Remove",
        workingTitle: "Removing Installers",
        doneTitle: "Removed",
        scanTitle: "Scanning for Installers",
        previewShowsMenu: true,
        managesScanPaths: false,
        consequence: "Selected files are deleted permanently, without using the Trash.",
        isIrreversible: true,
        changesApps: false
    )

    static let slim = MenuFlowConfiguration(
        screen: .slim,
        subtitle: "Removes Intel code from universal apps. Each app is verified on a copy first, and the original goes to the Trash.",
        command: "slim",
        idleTitle: "Remove Unused Intel Code",
        idleMessage: "On Apple silicon, universal apps carry code your Mac never runs. App updates bring it back.",
        emptyTitle: "No Apps to Slim",
        actionVerb: "Slim",
        workingTitle: "Slimming Apps",
        doneTitle: "Slimmed",
        scanTitle: "Scanning Apps",
        previewShowsMenu: false,
        managesScanPaths: false,
        consequence: "Each app is verified on a copy first, and the original goes to the Trash.",
        isIrreversible: false,
        changesApps: true
    )
}
