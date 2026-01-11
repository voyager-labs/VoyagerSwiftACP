import AppKit
import Logging
import SwiftUI

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    init() {
        LoggingSystem.bootstrap { label in
            let oslogHandler = VoyagerOSLogHandler(label: label)
            #if DEBUG
            let stderrHandler = StreamLogHandler.standardError(label: label)
            return MultiplexLogHandler([oslogHandler, stderrHandler])
            #else
            return oslogHandler
            #endif
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
