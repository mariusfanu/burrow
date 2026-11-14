import Darwin
import Foundation

/// Owns the NULL-terminated argument and environment arrays until the spawn call returns.
func withSpawnArguments<Result>(
    executable: String,
    arguments: [String],
    environment: [String: String],
    _ body: ([UnsafeMutablePointer<CChar>?], [UnsafeMutablePointer<CChar>?]) throws -> Result
) throws -> Result {
    guard !executable.utf8.contains(0),
          arguments.allSatisfy({ !$0.utf8.contains(0) }),
          environment.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.utf8.contains(0) && !$0.value.utf8.contains(0) }) else {
        throw POSIXError(.EINVAL)
    }

    var argv: [UnsafeMutablePointer<CChar>?] = []
    var envp: [UnsafeMutablePointer<CChar>?] = []
    defer {
        argv.forEach { free($0) }
        envp.forEach { free($0) }
    }

    for item in [executable] + arguments {
        guard let copy = strdup(item) else { throw POSIXError(.ENOMEM) }
        argv.append(copy)
    }
    argv.append(nil)

    for (key, value) in environment {
        guard let copy = strdup("\(key)=\(value)") else { throw POSIXError(.ENOMEM) }
        envp.append(copy)
    }
    envp.append(nil)

    return try body(argv, envp)
}
