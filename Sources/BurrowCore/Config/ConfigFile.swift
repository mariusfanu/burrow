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
        try write(text, to: url, replacing: read(url))
    }

    static func write(_ text: String, to url: URL, replacing previous: String?) throws {
        let target = url.resolvingSymlinksInPath()
        let identity = TrashMover.FileIdentity(path: target.path)
        if previous != nil {
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            guard identity != nil, attributes[.type] as? FileAttributeType == .typeRegular else {
                throw ConfigError.unreadable(url.lastPathComponent)
            }
        }
        if previous == nil {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard try read(url) == previous, url.resolvingSymlinksInPath() == target,
              TrashMover.FileIdentity(path: target.path) == identity else {
            throw ConfigError.changed(url.lastPathComponent)
        }
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    static func parseList(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
