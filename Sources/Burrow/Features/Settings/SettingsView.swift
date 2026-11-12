import SwiftUI

/// App-level setup, in the standard Settings window.
struct SettingsView: View {
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                GeneralSettings()
            }
            Tab("Protected", systemImage: "lock.shield", value: SettingsPane.protected) {
                ProtectedSettings()
            }
            Tab("Maintenance", systemImage: "wrench.and.screwdriver", value: SettingsPane.maintenance) {
                MaintenanceSettings()
            }
            Tab("Mole CLI", systemImage: "terminal", value: SettingsPane.mole) {
                MoleSettings()
            }
            Tab("About", systemImage: "info.circle", value: SettingsPane.about) {
                ScrollView {
                    AboutView()
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 560, height: 500)
    }
}
