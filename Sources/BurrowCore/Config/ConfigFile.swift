import Foundation

enum ConfigFile {
    /// Returns the file's text, or nil only when it doesn't exist. Any other failure
    /// throws, so that callers never mistake an unreadable file for an empty one.
    static func read(_ url: URL) throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // A broken link is unreadable configuration, not permission to use defaults.
            // Check parents too, while allowing a missing file inside a valid linked folder.
            var candidate = url
            while candidate.path != "/" {
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil,
                   !FileManager.default.fileExists(atPath: candidate.path) {
                    throw ConfigError.unreadable(url.lastPathComponent)
                }
                candidate.deleteLastPathComponent()
            }
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.unreadable(url.lastPathComponent)
        }
        return text
    }

    static func write(_ text: String, to url: URL) throws {
        // Recheck before writing: the file may have become unreadable since the UI loaded it.
        _ = try read(url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
