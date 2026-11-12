import BurrowCore
import Foundation
import Observation

@MainActor
@Observable
final class ManageModel {
    private(set) var touchIDStatus = ""
    private(set) var touchIDEnabled: Bool?
    var isRunPresented = false
    var isConfirmingRemove = false

    let run: RunController

    private let commands: CommandClient
    private var refreshID = UUID()

    init(policy: ExecutionPolicy, commands: CommandClient = CommandClient()) {
        self.commands = commands
        run = RunController(policy: policy)
    }

    func refresh(cli: CLIInfo) {
        let id = UUID()
        refreshID = id
        Task {
            let result = try? await commands.run(cli.executable, ["touchid", "status"], 20)
            guard refreshID == id else { return }
            let status = TouchIDStatus(output: result?.stdout ?? "")
            touchIDStatus = status?.description ?? "Couldn’t check"
            touchIDEnabled = status?.isEnabled
        }
    }

    /// Runs a command in the sheet, with its prompts relayed by the run panel.
    func perform(title: String, arguments: [String], cli: CLIInfo, showsTerminal: Bool = false) {
        run.start(title: title, cli: cli, arguments: arguments, showsTerminal: showsTerminal)
        isRunPresented = true
    }

    func closeRun(cli: CLIInfo) {
        run.reset()
        isRunPresented = false
        refresh(cli: cli)
    }
}
