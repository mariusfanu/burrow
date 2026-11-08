import Foundation
import Observation

/// Shared by the app and mutation models, so alternate UI paths cannot bypass Preview Mode.
@MainActor
@Observable
final class ExecutionPolicy {
    var previewMode: Bool {
        didSet { defaults?.set(previewMode, forKey: "previewMode") }
    }
    let isPreviewForced: Bool
    private let defaults: UserDefaults?

    var effectivePreview: Bool { previewMode || isPreviewForced }

    init(defaults: UserDefaults?, forced: Bool) {
        self.defaults = defaults
        isPreviewForced = forced
        previewMode = forced || defaults?.bool(forKey: "previewMode") == true
    }
}
