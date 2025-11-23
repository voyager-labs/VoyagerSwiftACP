import AppKit
import Foundation

/// VoyagerHelper 앱의 생명주기를 관리하는 클래스
@MainActor
final class HelperLifecycleManager {
    private let helperBundleId: String
    private let helperURL: URL
    private var terminationObserver: NSObjectProtocol?

    init() {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL

        let embedded = bundleURL.appendingPathComponent("Contents/Helpers/VoyagerHelper.app")
        if fm.fileExists(atPath: embedded.path) {
            helperURL = embedded
        } else {
            let sibling = bundleURL.deletingLastPathComponent().appendingPathComponent("VoyagerHelper.app")
            guard fm.fileExists(atPath: sibling.path) else {
                fatalError("VoyagerHelper.app not found")
            }
            helperURL = sibling
        }

        guard let bundle = Bundle(url: helperURL),
              let bundleId = bundle.bundleIdentifier
        else {
            fatalError("VoyagerHelper bundle information not found")
        }
        helperBundleId = bundleId
    }

    func start() {
        observeHelperTermination()
        launchHelperOnce()
    }

    func stop() {
        if let observer = terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            terminationObserver = nil
        }

        let runningApps = NSWorkspace.shared.runningApplications
        if let helper = runningApps.first(where: { $0.bundleIdentifier == helperBundleId }) {
            helper.terminate()
        }
    }

    private func launchHelperOnce() {
        let runningApps = NSWorkspace.shared.runningApplications
        let isHelperRunning = runningApps.contains { app in
            app.bundleIdentifier == helperBundleId
        }

        if !isHelperRunning {
            let config = NSWorkspace.OpenConfiguration()
            config.environment = ProcessInfo.processInfo.environment
            NSWorkspace.shared.openApplication(at: helperURL, configuration: config) { _, _ in }
        }
    }

    private func observeHelperTermination() {
        let center = NSWorkspace.shared.notificationCenter
        terminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self = self,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == self.helperBundleId
            else { return }

            Task { @MainActor in
                self.launchHelperOnce()
            }
        }
    }
}
