public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }

    /// Throws the command's stderr, without its escape codes, if it failed.
    public func requireSuccess() throws {
        guard succeeded else {
            throw CommandError.failed(status: status, message: ANSI.strip(stderr))
        }
    }
}
