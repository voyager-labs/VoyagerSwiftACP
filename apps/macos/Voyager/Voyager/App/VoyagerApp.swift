import AppKit
import Logging
import SwiftUI

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    init() {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardError(label: label)
        }
    }

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
