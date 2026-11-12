import BurrowCore
import Foundation

/// The process boundary used by feature models. Tests can deliver late output and
/// completions deterministically without running maintenance on the host Mac.
struct CommandClient: Sendable {
    var run: @Sendable (String, [String], TimeInterval?) async throws -> CommandResult = {
        try CLILocator.checkLaunchPath($0)
        return try await CommandRunner.run(executable: $0, arguments: $1, timeout: $2)
    }
    var stream: @Sendable (String, [String], @escaping @Sendable (Data) -> Void) async throws -> Int32 = {
        try CLILocator.checkLaunchPath($0)
        return try await CommandRunner.stream(executable: $0, arguments: $1, onStdout: $2)
    }
}
