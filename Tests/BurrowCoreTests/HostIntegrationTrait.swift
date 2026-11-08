import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    static var hostIntegration: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["BURROW_RUN_HOST_TESTS"] == "1",
            "Set BURROW_RUN_HOST_TESTS=1 to run tests that use the installed Mole CLI or macOS Trash."
        )
    }
}
