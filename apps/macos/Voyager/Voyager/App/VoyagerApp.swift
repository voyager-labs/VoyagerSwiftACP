import AppKit
import SwiftUI

@main
struct VoyagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
        .commands {
            MenuCommands()
        }
    }
}
