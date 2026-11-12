import SwiftUI

/// Reveals a bundled document such as the license in the Finder.
struct AboutDocumentButton: View {
    let title: LocalizedStringKey
    let file: String

    var body: some View {
        Button(title, action: reveal)
            .buttonStyle(.link)
            .font(.caption)
            .disabled(url == nil)
    }

    private var url: URL? {
        if let bundled = Bundle.main.url(forResource: file, withExtension: nil) {
            return bundled
        }
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appending(path: file)
        return FileManager.default.isReadableFile(atPath: local.path) ? local : nil
    }

    private func reveal() {
        if let url { FilePicker.reveal(url.path) }
    }
}
