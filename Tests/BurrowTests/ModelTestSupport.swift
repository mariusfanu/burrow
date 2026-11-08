import Foundation
import SwiftUI
import Testing
import BurrowCore
@testable import Burrow

let fixtureCLI = CLIInfo(executable: "/fixture/mo", root: "/fixture", version: "1", installMethod: "test")
let shellCLI = CLIInfo(executable: "/bin/sh", root: "/bin", version: "fixture", installMethod: "test")
let sleeperCLI = CLIInfo(executable: "/bin/sleep", root: "/bin", version: "fixture", installMethod: "test")

extension ExecutionPolicy {
    /// A new policy each time, because tests change it. Not forced, and it saves nothing.
    static var live: ExecutionPolicy { ExecutionPolicy(defaults: nil, forced: false) }
}

/// A stand-in CLI that keeps what it writes beside itself, at `"$(dirname "$0")/name"`.
func makeScript(_ body: String) throws -> (CLIInfo, String) {
    let directory = TestScratch.root + "burrow-script-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let script = directory + "/mo"
    try body.write(toFile: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    return (CLIInfo(executable: script, root: directory, version: "1", installMethod: "test"), directory)
}

/// A view's RGBA bytes at one pixel per point, top row first.
@MainActor
func pixels<V: View>(_ view: V) throws -> [UInt8] {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { bytes in
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
}

@MainActor
func eventually(_ predicate: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    try #require(await predicate(), "Timed out waiting for model state")
}

/// Intentionally ignores cancellation so tests can deliver obsolete results and callbacks.
actor ScriptedCommands {
    struct Run {
        let continuation: CheckedContinuation<CommandResult, any Error>
    }
    struct Stream {
        let executable: String
        let output: @Sendable (Data) -> Void
        let continuation: CheckedContinuation<Int32, any Error>
    }
    private(set) var runs: [Run] = []
    private(set) var streams: [Stream] = []

    nonisolated var client: CommandClient {
        CommandClient(
            run: { _, _, _ in try await self.run() },
            stream: { executable, _, output in try await self.stream(executable, output: output) }
        )
    }
    func run() async throws -> CommandResult {
        try await withCheckedThrowingContinuation { runs.append(Run(continuation: $0)) }
    }
    func stream(_ executable: String, output: @escaping @Sendable (Data) -> Void) async throws -> Int32 {
        try await withCheckedThrowingContinuation { streams.append(Stream(executable: executable, output: output, continuation: $0)) }
    }
    func completeRun(_ index: Int, stdout: String = "{}", status: Int32 = 0, stderr: String = "") {
        runs[index].continuation.resume(returning: CommandResult(status: status, stdout: stdout, stderr: stderr))
    }
    func failRun(_ index: Int) { runs[index].continuation.resume(throwing: CommandError.timedOut) }
    func emit(_ index: Int, _ text: String) { streams[index].output(Data(text.utf8)) }
    func finishStream(_ index: Int, status: Int32 = 0) { streams[index].continuation.resume(returning: status) }
}
