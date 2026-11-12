import BurrowCore
import Foundation
import Observation

@MainActor
@Observable
final class HistoryModel {
    private(set) var report: HistoryReport?
    private(set) var isLoading = false
    var errorMessage: String?
    var showsFiles = false
    var includesPreviews = false
    private var task: Task<Void, Never>?
    private var loadID = UUID()
    private let commands: CommandClient

    init(commands: CommandClient = CommandClient()) {
        self.commands = commands
    }

    func cancelLoading() {
        loadID = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    func invalidateCLIResults() {
        cancelLoading()
        report = nil
        errorMessage = nil
    }

    func load(cli: CLIInfo) {
        let id = UUID()
        loadID = id
        task?.cancel()
        isLoading = true
        errorMessage = nil
        task = Task {
            defer {
                if loadID == id {
                    isLoading = false
                    task = nil
                }
            }
            do {
                let result = try await commands.run(cli.executable, ["history", "--json", "--limit", "200"], 60)
                try Task.checkCancellation()
                guard loadID == id else { return }
                try result.requireSuccess()
                report = try HistoryReport.decode(Data(result.stdout.utf8))
            } catch is CancellationError {
                return
            } catch {
                guard loadID == id else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
