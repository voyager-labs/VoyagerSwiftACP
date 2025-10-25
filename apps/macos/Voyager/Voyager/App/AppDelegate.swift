import AppKit
import ComposableArchitecture
import SwiftUI

extension Notification.Name {
    static let closedTabsChanged = Notification.Name("closedTabsChanged")
    static let focusHistoryChanged = Notification.Name("focusHistoryChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var windowControllers: [FileManagerWindowController] = []
    var closedTabHistory: [FileManagerFeature.State] = []
    var focusHistory: [NSWindow] = []
    private var isNavigatingFocusHistory: Bool = false

    var hasValidFocusHistory: Bool {
        let validWindows = focusHistory.filter { window in
            window != NSApp.keyWindow && windowControllers.contains(where: { $0.window == window })
        }
        return !validWindows.isEmpty
    }

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

    func createNewTab(path: String? = nil, duplicateState: FileManagerFeature.State? = nil) {
        guard let keyWindow = NSApp.keyWindow else {
            createNewWindow(path: path)
            return
        }

        let controller = FileManagerWindowController(path: path, duplicateState: duplicateState, asTab: true)
        windowControllers.append(controller)

        if let newWindow = controller.window {
            keyWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    func duplicateCurrentTab() {
        guard let keyWindow = NSApp.keyWindow,
              let controller = windowControllers.first(where: { $0.window == keyWindow })
        else { return }

        createNewTab(duplicateState: controller.store.state)
    }

    func selectTab(at index: Int) {
        guard let window = NSApp.keyWindow,
              let tabGroup = window.tabGroup,
              index < tabGroup.windows.count
        else { return }

        tabGroup.windows[index].makeKeyAndOrderFront(nil)
    }

    func reopenLastClosedTab() {
        guard let state = closedTabHistory.popLast() else { return }
        NotificationCenter.default.post(name: .closedTabsChanged, object: nil)
        createNewTab(path: nil, duplicateState: state)
    }

    func updateFocusHistory(window: NSWindow?) {
        guard let window = window else { return }

        if isNavigatingFocusHistory {
            isNavigatingFocusHistory = false
            return
        }

        focusHistory.removeAll { $0 == window }

        if focusHistory.count >= 10 {
            focusHistory.removeLast()
        }

        focusHistory.insert(window, at: 0)
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)
    }

    func switchToLastFocusedTab() {
        if let currentWindow = NSApp.keyWindow {
            focusHistory.removeAll { $0 == currentWindow }
        }

        let validWindows = focusHistory.filter { window in
            windowControllers.contains(where: { $0.window == window })
        }

        guard let targetWindow = validWindows.first else { return }

        focusHistory.removeAll { $0 == targetWindow }
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)

        isNavigatingFocusHistory = true
        targetWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(controller: FileManagerWindowController) {
        guard let window = controller.window else {
            windowControllers.removeAll { $0 === controller }
            return
        }

        let isTab = window.tabbingMode == .preferred && window.tabbingIdentifier == "file-manager"

        if isTab {
            closedTabHistory.append(controller.store.state)

            if closedTabHistory.count > 10 {
                closedTabHistory.removeFirst()
            }

            NotificationCenter.default.post(name: .closedTabsChanged, object: nil)
        }

        focusHistory.removeAll { $0 == window }
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)
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
