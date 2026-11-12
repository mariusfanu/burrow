import Darwin

/// Owns the NULL-terminated argument and environment arrays until the spawn call returns.
func withSpawnArguments<Result>(
    executable: String,
    arguments: [String],
    environment: [String: String],
    _ body: ([UnsafeMutablePointer<CChar>?], [UnsafeMutablePointer<CChar>?]) throws -> Result
) rethrows -> Result {
    var argv = ([executable] + arguments).map { strdup($0) }
    argv.append(nil)
    var envp = environment.map { strdup("\($0.key)=\($0.value)") }
    envp.append(nil)
    defer {
        argv.forEach { free($0) }
        envp.forEach { free($0) }
    }
    return try body(argv, envp)
}
