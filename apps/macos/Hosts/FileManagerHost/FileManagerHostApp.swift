import AppKit
import SwiftUI
import VoyagerPagesFileManager

@MainActor
private enum FileManagerHostSmokeMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["FILE_MANAGER_HOST_SMOKE"] == "1"
    }

    static func runIfNeeded() {
        guard isEnabled else { return }

        _ = NSApplication.shared
        let windowController = FileManagerHostFixture.makeWindowController()
        windowController.showWindow(nil)
        _ = windowController.window?.contentViewController?.view
        exit(0)
    }
}

@main
struct FileManagerHostApp: App {
    @NSApplicationDelegateAdaptor(FileManagerHostAppDelegate.self)
    private var appDelegate

    init() {
        FileManagerHostSmokeMode.runIfNeeded()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class FileManagerHostAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        let controller = FileManagerHostFixture.makeWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
