import Foundation

/// One folder on the way down, remembering where it sat in its parent so that going back
/// can zoom out to the same spot.
struct AnalyzeLevel: Equatable, Identifiable {
    /// nil is the disk overview.
    let path: String?
    let tint: UInt32?
    /// The tile this level grew from, as fractions of the map.
    let originRect: CGRect?

    var id: String { path.map { "folder:\($0)" } ?? "disk-overview" }
    var name: String { path.map { $0.lastPathComponent } ?? "This Mac" }
}
