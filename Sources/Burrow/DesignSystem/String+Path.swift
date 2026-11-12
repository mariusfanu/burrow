import Foundation

extension String {
    /// The last component of a path, such as a file or volume name.
    var lastPathComponent: String { (self as NSString).lastPathComponent }

    /// Shortens the home directory to `~` for display.
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
