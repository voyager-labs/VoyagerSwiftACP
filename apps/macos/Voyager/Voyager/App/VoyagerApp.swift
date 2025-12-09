import AppKit
import SwiftUI

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            AppMenuCommands()
            EditMenuCommands()
            ViewMenuCommands()
        }
    }
}
