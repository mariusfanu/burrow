import AppKit
import BurrowCore
import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Burrow", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                #if DEBUG
                .preferredColorScheme(appearanceOverride)
                #endif
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands { BurrowCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    #if DEBUG
    private var appearanceOverride: ColorScheme? {
        switch ProcessInfo.processInfo.environment["BURROW_SCHEME"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    #endif
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BURROW_SCHEME"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if ProcessInfo.processInfo.environment["BURROW_SCHEME"] == "light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        #endif
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        if model?.hasActiveWork == true {
            let alert = NSAlert()
            alert.messageText = "A command is still running"
            alert.informativeText = "Quitting stops it partway. Anything it already finished stays finished."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        isTerminating = true
        let model = model
        Task {
            // A child stuck on a stalled volume ignores even SIGKILL, and mustn't hold the app
            // open until someone reaches for Force Quit.
            _ = await finishes(within: .seconds(6)) {
                if let model { await model.shutdown() }
                else { await ProcessLifecycle.shared.shutdownAll() }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The Dock menu's most useful commands, available even with no window in front.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for screen in [Screen.clean, .analyze, .status] {
            let item = NSMenuItem(title: screen.title, action: #selector(openFromDock(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen.rawValue
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openFromDock(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let screen = Screen(rawValue: raw) {
            model?.selection = screen
        }
        NSApp.activate()
    }
}

/// Runs work to its end, and returns early with false if it's still going at the deadline.
@MainActor
func finishes(within deadline: Duration, _ work: @escaping @MainActor () async -> Void) async -> Bool {
    await withCheckedContinuation { continuation in
        var pending: CheckedContinuation<Bool, Never>? = continuation
        @MainActor func finish(_ finished: Bool) {
            pending?.resume(returning: finished)
            pending = nil
        }
        Task {
            await work()
            finish(true)
        }
        Task {
            try? await Task.sleep(for: deadline)
            finish(false)
        }
    }
}
