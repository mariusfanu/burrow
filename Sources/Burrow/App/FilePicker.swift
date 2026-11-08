import AppKit

@MainActor
enum FilePicker {
    static func chooseFile(prompt: String) -> String? {
        choose(prompt: prompt, directories: false)
    }

    static func chooseFolder(prompt: String) -> String? {
        choose(prompt: prompt, directories: true)
    }

    private static func choose(prompt: String, directories: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.prompt = prompt
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
