import AppKit
import BurrowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    var openMainWindow: (@MainActor () -> Void)?
    private var isTerminating = false
    private var isConfirmingTermination = false

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
        guard !isConfirmingTermination else { return .terminateCancel }
        if model?.hasActiveWork == true {
            let alert = NSAlert()
            alert.messageText = "A command is still running"
            alert.informativeText = "Quitting stops it partway. Anything it already finished stays finished."
            alert.addButton(withTitle: "Keep Running")
            alert.addButton(withTitle: "Quit")
            isConfirmingTermination = true
            let response = alert.runModal()
            isConfirmingTermination = false
            guard response == .alertSecondButtonReturn else { return .terminateCancel }
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
        openMainWindow?()
        NSApp.activate()
    }
}
