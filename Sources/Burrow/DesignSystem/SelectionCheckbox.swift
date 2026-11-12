import SwiftUI

/// The checkbox at the front of a selectable row. The whole row is clickable too, so the
/// checkbox reports the row's state and hands every change to the row's own toggle, which
/// also moves keyboard focus. This preserves the row’s action when the checkbox is clicked.
struct SelectionCheckbox: View {
    let title: String
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle("Select \(title)", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
            .labelsHidden()
            .toggleStyle(.checkbox)
    }
}
