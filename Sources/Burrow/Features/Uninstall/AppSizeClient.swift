import BurrowCore
import Foundation

struct AppSizeClient: Sendable {
    var measure: @Sendable (String) async throws -> Int64 = { path in
        let result = try await CommandRunner.run(executable: "/usr/bin/du", arguments: ["-sk", path], timeout: 60)
        try result.requireSuccess()
        guard let field = result.stdout.split(whereSeparator: \.isWhitespace).first,
              let kilobytes = Int64(field), kilobytes >= 0 else {
            throw CommandError.failed(status: 1, message: "The app’s size couldn’t be measured.")
        }
        let (bytes, overflow) = kilobytes.multipliedReportingOverflow(by: 1_024)
        guard !overflow else {
            throw CommandError.failed(status: 1, message: "The app’s reported size is too large.")
        }
        return bytes
    }
}
