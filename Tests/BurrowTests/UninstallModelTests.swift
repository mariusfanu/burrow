import Foundation
import Testing
import BurrowCore
@testable import Burrow

private actor ControlledSizes {
    struct Request {
        let path: String
        let continuation: CheckedContinuation<Int64, any Error>
    }
    private(set) var requests: [Request] = []
    nonisolated var client: AppSizeClient {
        AppSizeClient(measure: { path in try await self.measure(path) })
    }
    func measure(_ path: String) async throws -> Int64 {
        try await withCheckedThrowingContinuation { requests.append(Request(path: path, continuation: $0)) }
    }
    func complete(path: String, occurrence: Int = 0, bytes: Int64) {
        let index = requests.enumerated().filter { $0.element.path == path }[occurrence].offset
        requests[index].continuation.resume(returning: bytes)
    }
    func fail(path: String, occurrence: Int = 0) {
        let index = requests.enumerated().filter { $0.element.path == path }[occurrence].offset
        requests[index].continuation.resume(throwing: CommandError.failed(status: 1, message: "Access denied"))
    }
    func complete(_ index: Int, bytes: Int64) { requests[index].continuation.resume(returning: bytes) }
}

@MainActor
struct UninstallModelTests {
    private let list = """
    [{"name":"Alpha","path":"/apps/alpha.app","uninstall_name":"Alpha"},
     {"name":"Beta","path":"/apps/beta.app","uninstall_name":"Beta"},
     {"name":"No location","uninstall_name":"No location"}]
    """

    private func fixture() -> (UninstallModel, ScriptedCommands, ControlledSizes) {
        let commands = ScriptedCommands()
        let sizes = ControlledSizes()
        let model = UninstallModel(policy: .live, commands: commands.client, sizeClient: sizes.client)
        return (model, commands, sizes)
    }

    /// The standard list, with both of its measurements waiting to be completed.
    private func loadedFixture() async throws -> (UninstallModel, ScriptedCommands, ControlledSizes) {
        let (model, commands, sizes) = fixture()
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: list)
        try await eventually { await sizes.requests.count == 2 }
        return (model, commands, sizes)
    }

    /// Children must finish before the group ends. In a release build, a `do`/`catch` written
    /// inside `addTask` made `group.next()` return nil early and crashed the app when a child
    /// finished, so this needs to pass under `swift test -c release` as well.
    @Test func everyAppIsMeasuredBeforeMeasuringEnds() async throws {
        let rows = (0..<12).map { "{\"name\":\"App\($0)\",\"path\":\"/apps/\($0).app\",\"uninstall_name\":\"App\($0)\"}" }
        let json = "[" + rows.joined(separator: ",") + "]"
        let model = UninstallModel(
            policy: .live,
            commands: CommandClient(run: { _, _, _ in CommandResult(status: 0, stdout: json, stderr: "") }),
            sizeClient: AppSizeClient(measure: { path in
                try await Task.sleep(for: .milliseconds(5))
                if path.hasSuffix("/3.app") { throw CommandError.timedOut }
                return 7
            })
        )
        model.load(cli: fixtureCLI)
        try await eventually { model.state == .list && !model.isMeasuring }
        #expect(model.sizes.count == 11)
        #expect(model.sizeState(for: try #require(model.apps.first { $0.name == "App3" })) == .failed(CommandError.timedOut.localizedDescription))
        #expect(!model.sizeStates.values.contains(.pending))
    }

    @Test func measurementsHaveTerminalStatesAndRetryWithoutAnEndlessSpinner() async throws {
        let (model, _, sizes) = try await loadedFixture()
        let alpha = try #require(model.apps.first { $0.name == "Alpha" })
        let missing = try #require(model.apps.first { $0.path == nil })
        #expect(model.sizeState(for: missing) == .unavailable)
        #expect(model.sizeState(for: alpha) == .pending)
        await sizes.fail(path: "/apps/alpha.app")
        await sizes.complete(path: "/apps/beta.app", bytes: 20)
        try await eventually { !model.isMeasuring }
        #expect(model.sizeState(for: alpha) == .failed("Access denied"))
        model.retrySize(for: alpha)
        try await eventually { await sizes.requests.count == 3 }
        await sizes.complete(path: "/apps/alpha.app", occurrence: 1, bytes: 30)
        try await eventually { !model.isMeasuring }
        #expect(model.sizeState(for: alpha) == .measured(30))
        #expect(model.sizes[alpha.id] == 30)
    }

    @Test func rowsStayStillDuringMeasurementsAndAnInteractionDefersTheFinalSort() async throws {
        let (model, _, sizes) = try await loadedFixture()
        let firstOrder = model.visibleApps.map(\.id)
        model.toggleSelection("/apps/alpha.app")
        #expect(model.selection == ["/apps/alpha.app"])
        await sizes.complete(path: "/apps/beta.app", bytes: 100)
        try await eventually { model.sizes["/apps/beta.app"] == 100 }
        #expect(model.visibleApps.map(\.id) == firstOrder)
        await sizes.complete(path: "/apps/alpha.app", bytes: 10)
        try await eventually { !model.isMeasuring }
        #expect(model.visibleApps.map(\.id) == firstOrder)
        #expect(model.hasPendingSizeSort)
        model.applySort()
        #expect(model.visibleApps.first?.name == "Beta")
        #expect(!model.hasPendingSizeSort)
        model.toggleSelection("/apps/alpha.app")
        #expect(model.selection.isEmpty)
    }

    @Test func untouchedBatchSortsOnceOnCompletion() async throws {
        let (model, _, sizes) = try await loadedFixture()
        await sizes.complete(path: "/apps/beta.app", bytes: 100)
        try await eventually { model.sizes["/apps/beta.app"] == 100 }
        #expect(model.visibleApps.first?.name == "Alpha")
        await sizes.complete(path: "/apps/alpha.app", bytes: 10)
        try await eventually { !model.isMeasuring }
        #expect(model.visibleApps.first?.name == "Beta")
    }

    @Test func equalNamesUseTheirIDsToKeepTheOrderDeterministic() async throws {
        let (model, commands, _) = fixture()
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: """
        [{"name":"Twin","uninstall_name":"Twin-Z"},
         {"name":"Alpha","uninstall_name":"Alpha"},
         {"name":"Twin","uninstall_name":"Twin-A"}]
        """)
        try await eventually { model.state == .list }
        #expect(model.visibleApps.map(\.id) == ["Alpha", "Twin-A", "Twin-Z"])
        model.sortOrder = .name
        #expect(model.visibleApps.map(\.id) == ["Alpha", "Twin-A", "Twin-Z"])
    }

    @Test func reloadKeepsKnownPositionsAndSortsOnlyNewRowsByNameUntilMeasurementsFinish() async throws {
        let (model, commands, sizes) = try await loadedFixture()
        await sizes.complete(path: "/apps/alpha.app", bytes: 10)
        await sizes.complete(path: "/apps/beta.app", bytes: 100)
        try await eventually { !model.isMeasuring }
        #expect(model.visibleApps.map(\.id) == ["/apps/beta.app", "/apps/alpha.app", "No location"])

        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: """
        [{"name":"Twin","uninstall_name":"Twin-Z"},
         {"name":"Alpha","path":"/apps/alpha.app","uninstall_name":"Alpha"},
         {"name":"Aardvark","uninstall_name":"Aardvark"},
         {"name":"No location","uninstall_name":"No location"},
         {"name":"Twin","uninstall_name":"Twin-A"},
         {"name":"Beta","path":"/apps/beta.app","uninstall_name":"Beta"}]
        """)
        try await eventually { await sizes.requests.count == 4 }
        #expect(model.visibleApps.map(\.id) == [
            "/apps/beta.app", "/apps/alpha.app", "No location", "Aardvark", "Twin-A", "Twin-Z",
        ])

        await sizes.complete(path: "/apps/alpha.app", occurrence: 1, bytes: 200)
        await sizes.complete(path: "/apps/beta.app", occurrence: 1, bytes: 100)
        try await eventually { !model.isMeasuring }
        #expect(model.visibleApps.map(\.id) == [
            "/apps/alpha.app", "/apps/beta.app", "Aardvark", "No location", "Twin-A", "Twin-Z",
        ])
    }

    @Test func reloadMeasuresTheSamePathsAgainAndRejectsOldResults() async throws {
        let (model, commands, sizes) = try await loadedFixture()
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 2 }
        await commands.completeRun(1, stdout: list)
        try await eventually { await sizes.requests.count == 4 }
        await sizes.complete(path: "/apps/alpha.app", occurrence: 1, bytes: 40)
        await sizes.complete(path: "/apps/beta.app", occurrence: 1, bytes: 50)
        try await eventually { !model.isMeasuring }
        await sizes.complete(path: "/apps/alpha.app", bytes: 999)
        await sizes.complete(path: "/apps/beta.app", bytes: 888)
        for _ in 0..<20 { await Task.yield() }
        #expect(model.sizes["/apps/alpha.app"] == 40)
        #expect(model.sizes["/apps/beta.app"] == 50)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 3 }
        await commands.completeRun(2, stdout: list)
        try await eventually { await sizes.requests.count == 6 }
        #expect(model.sizes.isEmpty)
        await sizes.complete(path: "/apps/alpha.app", occurrence: 2, bytes: 60)
        await sizes.complete(path: "/apps/beta.app", occurrence: 2, bytes: 70)
        try await eventually { !model.isMeasuring }
        #expect(model.sizes["/apps/alpha.app"] == 60)
    }
    @Test func measurementConcurrencyStaysBoundedToFour() async throws {
        let (model, commands, sizes) = fixture()
        let rows = (0..<10).map { ["name": "App \($0)", "path": "/apps/\($0).app", "uninstall_name": "App \($0)"] }
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        model.load(cli: fixtureCLI)
        try await eventually { await commands.runs.count == 1 }
        await commands.completeRun(0, stdout: json)
        try await eventually { await sizes.requests.count == 4 }
        for _ in 0..<20 { await Task.yield() }
        #expect(await sizes.requests.count == 4)
        for index in 0..<10 {
            try await eventually { await sizes.requests.count >= index + 1 }
            await sizes.complete(index, bytes: Int64(index + 1))
            try await eventually { await sizes.requests.count == min(index + 5, 10) }
        }
        try await eventually { !model.isMeasuring }
        #expect(model.sizes.count == 10)
    }
}
