import Foundation

/// A located copy of the Mole CLI.
public struct CLIInfo: Sendable, Equatable {
    public let executable: String
    public let root: String
    public let version: String
    public let installMethod: String

    public init(executable: String, root: String, version: String, installMethod: String) {
        self.executable = executable
        self.root = root
        self.version = version
        self.installMethod = installMethod
    }

    /// The Go status and analyze binaries ship with releases, not with a source checkout.
    public var hasBundledTools: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: root + "/bin/status-go")
            && fileManager.fileExists(atPath: root + "/bin/analyze-go")
    }
}
