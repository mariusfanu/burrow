import Foundation

/// One folder for this test process's temporary files, removed when the process exits, so
/// that a test that doesn't clean up after itself leaves nothing behind.
enum TestScratch {
    static let root: String = {
        let path = NSTemporaryDirectory() + "burrow-tests-\(ProcessInfo.processInfo.processIdentifier)/"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(atPath: TestScratch.root) }
        return path
    }()
}
