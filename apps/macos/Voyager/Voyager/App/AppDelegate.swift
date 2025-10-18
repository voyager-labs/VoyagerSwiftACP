import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var windowControllers: [FileManagerWindowController] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        launchHelperOnce()
        createNewWindow()
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            createNewWindow()
        }
        return true
    }

    @objc
    func createNewWindow(path: String? = nil) {
        let controller = FileManagerWindowController(path: path, asTab: false)
        windowControllers.append(controller)
        controller.showWindow(nil)
    }

    @objc
    func createNewTab(path: String? = nil) {
        guard let keyWindow = NSApp.keyWindow else {
            createNewWindow(path: path)
            return
        }

        let controller = FileManagerWindowController(path: path, asTab: true)
        windowControllers.append(controller)

        if let newWindow = controller.window {
            keyWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(controller: FileManagerWindowController) {
        windowControllers.removeAll { $0 === controller }
    }

    private func launchHelperOnce() {
        let mainURL = Bundle.main.bundleURL
        let buildDir = mainURL.deletingLastPathComponent()
        let helperURL = buildDir.appendingPathComponent("VoyagerHelper.app")

        guard FileManager.default.fileExists(atPath: helperURL.path) else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        let isHelperRunning = runningApps.contains { app in
            app.bundleIdentifier == "fm.voyager.VoyagerHelper"
        }

        if !isHelperRunning {
            let config = NSWorkspace.OpenConfiguration()
            config.environment = ProcessInfo.processInfo.environment
            NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { _, _ in }
        }
    }
}
