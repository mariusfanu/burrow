#if DEBUG
import AppKit
import BurrowCore
import Foundation

/// Runs a scripted session against the real view models, for debug builds only.
///
/// `BURROW_STEPS` holds steps separated by `;`. It exists so that whole flows can be
/// checked against a sandboxed `HOME` without a person clicking. Release builds don't
/// contain it.
@MainActor
enum DebugDriver {
    static func runIfRequested(model: AppModel, cli: CLIInfo) {
        guard let script = ProcessInfo.processInfo.environment["BURROW_STEPS"] else { return }
        Task {
            NSApp.activate()
            mainWindow?.makeKeyAndOrderFront(nil)
            mainWindow?.orderFrontRegardless()
            for step in script.split(separator: ";").map(String.init) {
                await perform(step, model: model, cli: cli)
            }
        }
    }

    nonisolated private static func log(_ text: String) {
        FileHandle.standardError.write(Data("[burrow] \(text)\n".utf8))
    }

    private static func flow(_ name: String, _ model: AppModel) -> MenuFlowModel {
        switch name {
        case "purge": model.purge
        case "slim": model.slim
        default: model.installers
        }
    }

    private static func run(_ name: String, _ model: AppModel) -> RunController {
        switch name {
        case "clean": model.clean.run
        case "uninstall": model.uninstall.run
        case "optimize": model.optimize.run
        case "manage": model.manage.run
        default: flow(name, model).run
        }
    }

    private static func waitUntil(_ timeout: TimeInterval = 240, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !condition() { log("timed out") }
    }

    private static func perform(_ step: String, model: AppModel, cli: CLIInfo) async {
        let parts = step.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let operation = parts[0]
        let argument = parts.count > 1 ? parts[1] : ""
        let extra = parts.count > 2 ? parts[2] : ""
        let isTerminalInput = operation == "prompt.password" || operation == "terminal.send"
        log("step \(isTerminalInput ? operation : step)")

        switch operation {
        case "sleep":
            try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
        case "snap":
            snapshot(to: argument)
        case "shot":
            await windowShot(to: argument)
        case "burst":
            for frame in 0..<max(Int(extra) ?? 6, 0) {
                await windowShot(to: "\(argument)-\(frame).png")
            }
        case "hover":
            model.analyze.hovered = model.analyze.entries.first?.path
        case "search":
            model.uninstall.searchText = argument
        case "screen":
            if let screen = Screen(rawValue: argument) { model.selection = screen }
        case "clean.scan":
            model.clean.scan(cli: cli)
            await waitUntil { model.clean.state != .scanning }
            log("clean state \(model.clean.state), \(model.clean.report.sections.count) sections, potential \(model.clean.report.potentialText ?? "none")")
        case "clean.run":
            model.clean.clean(cli: cli, preview: model.effectivePreview)
        case "menu.scan":
            let flow = flow(argument, model)
            flow.scan(cli: cli, preview: model.effectivePreview)
            await waitUntil { flow.state != .scanning }
            log("\(argument) state \(flow.state), error \(flow.errorMessage ?? "none")")
            for item in flow.items {
                log("  [\(item.index)] sel=\(item.preselected) name=\(item.name) tag=\(item.tag ?? "-") path=\(item.path ?? "-") size=\(item.sizeText ?? "-")")
            }
        case "menu.select":
            let flow = flow(argument, model)
            flow.selection = Set(flow.items.filter { $0.rowText.contains(extra) }.map(\.index))
            log("selected \(flow.selection.sorted())")
        case "menu.apply":
            flow(argument, model).applySelection(preview: model.effectivePreview)
            await waitUntil(60) { flow(argument, model).state == .running || flow(argument, model).state == .idle }
            log("\(argument) state \(flow(argument, model).state), error \(flow(argument, model).errorMessage ?? "none")")
        case "menu.quit":
            flow(argument, model).abandonSelection()
        case "settings":
            if !argument.isEmpty { UserDefaults.standard.set(argument, forKey: "settingsPane") }
            model.openSettingsForDebug?()
            NSApp.activate()
        case "closewindow":
            NSApp.keyWindow?.close()
        case "history.tab":
            model.history.showsFiles = argument == "files"
        case "clean.volume":
            model.clean.isChoosingVolume = argument == "on"
        case "menu.paths":
            flow(argument, model).isEditingPaths = extra == "on"
        case "terminal":
            run(argument, model).isTerminalVisible = extra == "on"
        case "prompt.wait":
            let run = run(argument, model)
            await waitUntil(120) { run.promptRequest != nil || !run.isRunning }
            log("prompt \(String(describing: run.promptRequest?.prompt)) phase \(run.phase)")
        case "prompt.confirm":
            run(argument, model).answerConfirm()
        case "prompt.decline":
            run(argument, model).answerDecline()
        case "prompt.system":
            run(argument, model).answerSystemClean(useAdmin: extra == "admin")
        case "prompt.password":
            run(argument, model).answerPassword(extra)
        case "primary":
            model.primaryAction?.perform()
        case "clean.expand":
            model.clean.expandedSections = Set(model.clean.report.sections.map(\.id))
        case "terminal.send":
            run(argument, model).send(extra.replacingOccurrences(of: "\\r", with: "\r"))
        case "run.wait":
            let run = run(argument, model)
            await waitUntil { !run.isRunning }
            log("\(argument) phase \(run.phase) cancelled \(run.wasCancelled)")
            for line in run.lines.suffix(Int(extra) ?? 12) { log("  \(line.kind): \(line.text)") }
        case "run.finish":
            switch argument {
            case "uninstall": model.uninstall.finishRun(cli: cli)
            case "clean": model.clean.finishRun()
            case "optimize": model.optimize.finishRun(cli: cli)
            case "manage": model.manage.closeRun(cli: cli)
            default: flow(argument, model).finishRun()
            }
        case "uninstall.options":
            model.uninstall.deletePermanently = true
            model.uninstall.includePersonalData = true
        case "uninstall.load":
            model.uninstall.load(cli: cli)
            await waitUntil { model.uninstall.state != .loading }
            log("uninstall \(model.uninstall.state) apps \(model.uninstall.apps.count) error \(model.uninstall.errorMessage ?? "none")")
        case "uninstall.select":
            model.uninstall.selection = Set(model.uninstall.apps.filter { $0.name == argument }.map(\.id))
            log("selected \(model.uninstall.selection)")
        case "uninstall.review":
            model.uninstall.beginRemoval(cli: cli, preview: model.effectivePreview)
        case "optimize.preview":
            model.optimize.preview(cli: cli)
            await waitUntil { model.optimize.state != .previewing }
            log("optimize \(model.optimize.state) lines \(model.optimize.lines.count)")
        case "optimize.run":
            model.optimize.runMaintenance(cli: cli, preview: model.effectivePreview)
        case "analyze.open":
            if argument.isEmpty {
                model.analyze.openRoot(cli: cli)
            } else if let entry = model.analyze.entries.first(where: { $0.path == argument || $0.name == argument }) {
                let rank = model.analyze.entries.firstIndex(of: entry) ?? 0
                model.analyze.open(entry, tint: Theme.tile(rank: rank, parent: model.analyze.current?.tint), rect: model.analyze.tileRect(for: entry), cli: cli)
            } else {
                model.analyze.openPath(argument, cli: cli)
            }
            await waitUntil { !model.analyze.isLoading }
            log("analyze entries \(model.analyze.entries.count) error \(model.analyze.errorMessage ?? "none")")
        case "analyze.undo":
            model.analyze.undoTrash(cli: cli)
            await waitUntil(30) { !model.analyze.isLoading }
            log("notice \(model.analyze.noticeMessage ?? "none") entries \(model.analyze.entries.map(\.name))")
        case "analyze.back":
            model.analyze.goBack(cli: cli)
        case "analyze.select":
            model.analyze.selection = Set(model.analyze.entries.filter { $0.name == argument }.map(\.path))
            log("selected \(model.analyze.selection)")
        case "analyze.trash":
            model.analyze.trashSelection(cli: cli)
            await waitUntil(30) { !model.analyze.isTrashing && !model.analyze.isLoading }
            log("notice \(model.analyze.noticeMessage ?? "none") error \(model.analyze.errorMessage ?? "none") entries \(model.analyze.entries.map(\.name))")
            log("question \(model.analyze.pendingTrash?.title ?? "none") \(model.analyze.pendingTrash?.message ?? "")")
        case "analyze.confirm":
            model.analyze.confirmPendingTrash(cli: cli)
            await waitUntil(30) { !model.analyze.isTrashing }
            log("notice \(model.analyze.noticeMessage ?? "none") entries \(model.analyze.entries.map(\.name))")
        case "analyze.decline":
            model.analyze.pendingTrash = nil
        case "manage.run":
            model.manage.perform(title: "Debug", arguments: argument.split(separator: " ").map(String.init), cli: cli)
        case "manage.terminal":
            model.manage.perform(title: "Debug", arguments: argument.split(separator: " ").map(String.init), cli: cli, showsTerminal: true)
        case "history.load":
            model.history.load(cli: cli)
            await waitUntil(30) { !model.history.isLoading }
            let sessions = model.history.report?.sessions ?? []
            log("history sessions \(sessions.count): \(sessions.prefix(5).map { "\($0.command ?? "?") \($0.size ?? "")" })")
        case "uninstall.permanent":
            model.uninstall.deletePermanently = true
        case "appearance":
            let app = NSAppearance(named: argument == "light" ? .aqua : .darkAqua)
            NSApp.appearance = app
            mainWindow?.appearance = app
        case "quit":
            // AppKit waits for the termination delegate's reply in a nested run loop.
            // Leave this MainActor task first so the delegate's shutdown task can run.
            RunLoop.main.perform {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        default:
            log("unknown step \(step)")
        }
    }

    /// The window a sheet belongs to, or else the frontmost window.
    private static var mainWindow: NSWindow? {
        NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }

    /// Captures the live window from outside the app, so that a frame caught during an
    /// animation shows what's really on screen.
    private static func windowShot(to path: String) async {
        guard let number = mainWindow?.windowNumber else { return }
        NSApp.activate()
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(number), path]
            do {
                try process.run()
            } catch {
                log("window capture couldn’t start: \(error.localizedDescription)")
                return
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                log("window capture exited with status \(process.terminationStatus)")
            }
        }.value
    }

    /// Draws the window into a PNG, which works even when the display is asleep.
    private static func snapshot(to path: String) {
        guard let main = mainWindow,
              let view = (main.attachedSheet ?? main).contentView?.superview else {
            log("no window to snapshot")
            return
        }
        NSApp.activate()
        main.makeKeyAndOrderFront(nil)
        let firstResponder = main.firstResponder
        defer { main.makeFirstResponder(firstResponder) }
        main.makeFirstResponder(main.contentView)
        main.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            log("no bitmap")
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)

        if let sidebar = sourceList(in: view) {
            compositeSidebar(sidebar, in: view, onto: bitmap)
        }

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            log("couldn’t encode snapshot")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            log("snapshot \(path)")
        } catch {
            log("couldn’t save snapshot: \(error.localizedDescription)")
        }
    }

    private static func sourceList(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.effectiveStyle == .sourceList { return table }
        for subview in view.subviews {
            if let table = sourceList(in: subview) { return table }
        }
        return nil
    }

    /// In a cached display, the sidebar’s glass can come back transparent. Draw an opaque
    /// backdrop for the source list only, leaving detail tables and sheet contents untouched.
    private static func compositeSidebar(_ table: NSTableView, in view: NSView, onto bitmap: NSBitmapImageRep) {
        guard let scrollView = table.enclosingScrollView,
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        let isDark = table.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let sidebarBg = isDark
            ? NSColor(srgbRed: 0.106, green: 0.129, blue: 0.165, alpha: 1.0)
            : NSColor(srgbRed: 0.945, green: 0.953, blue: 0.965, alpha: 1.0)
        let borderColor = isDark
            ? NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 1.0)
            : NSColor(srgbRed: 0.86, green: 0.88, blue: 0.90, alpha: 1.0)

        let scrollRect = view.convert(scrollView.bounds, from: scrollView)
        let sidebarRect = NSRect(x: view.bounds.minX, y: view.bounds.minY, width: scrollRect.maxX - view.bounds.minX, height: view.bounds.height)
        let tableRect = view.convert(table.bounds, from: table)
        let oldBackground = table.backgroundColor
        table.backgroundColor = sidebarBg

        var hiddenEffects: [NSVisualEffectView] = []
        defer {
            table.backgroundColor = oldBackground
            for effect in hiddenEffects { effect.isHidden = false }
        }
        for row in table.selectedRowIndexes {
            guard let rowView = table.rowView(atRow: row, makeIfNecessary: false) else { continue }
            for case let effect as NSVisualEffectView in rowView.subviews where !effect.isHidden {
                effect.isHidden = true
                hiddenEffects.append(effect)
            }
        }

        guard let tableRep = table.bitmapImageRepForCachingDisplay(in: table.bounds) else { return }
        table.cacheDisplay(in: table.bounds, to: tableRep)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        sidebarBg.setFill()
        NSBezierPath(rect: sidebarRect).fill()
        borderColor.setFill()
        NSBezierPath(rect: NSRect(x: sidebarRect.maxX - 1, y: sidebarRect.minY, width: 1, height: sidebarRect.height)).fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: scrollRect).addClip()
        for row in table.selectedRowIndexes {
            let pillRect = view.convert(table.rect(ofRow: row), from: table).insetBy(dx: 8, dy: 1)
            let selectionColor = isDark
                ? NSColor(srgbRed: 0.18, green: 0.38, blue: 0.72, alpha: 1.0)
                : NSColor(srgbRed: 0.21, green: 0.42, blue: 0.76, alpha: 1.0)
            selectionColor.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        }
        tableRep.draw(in: tableRect)
        NSGraphicsContext.restoreGraphicsState()

        let widgets = view.subviews.filter {
            let name = String(describing: type(of: $0))
            return name.contains("Widget") || name.contains("ToolbarItemHostingView")
        }
        for widget in widgets {
            guard let widgetRep = widget.bitmapImageRepForCachingDisplay(in: widget.bounds) else { continue }
            widget.cacheDisplay(in: widget.bounds, to: widgetRep)
            widgetRep.draw(in: view.convert(widget.bounds, from: widget))
        }
    }
}
#endif
