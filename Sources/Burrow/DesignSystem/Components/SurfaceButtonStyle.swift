import SwiftUI

/// The press and hover behavior for content surfaces that act as buttons.
struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SurfaceButtonBody(configuration: configuration)
    }
}
