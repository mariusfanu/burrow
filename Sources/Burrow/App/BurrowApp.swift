import AppKit
import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Burrow", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                #if DEBUG
                .preferredColorScheme(appearanceOverride)
                #endif
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unified)
        .commands { BurrowCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    #if DEBUG
    private var appearanceOverride: ColorScheme? {
        switch ProcessInfo.processInfo.environment["BURROW_SCHEME"] {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
    #endif
}
