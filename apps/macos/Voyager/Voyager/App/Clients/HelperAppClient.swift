@preconcurrency import AppKit
import ComposableArchitecture
import Foundation

public struct HelperAppClient: Sendable {
    public var start: @Sendable () async -> Void
    public var stop: @Sendable () async -> Void
    // Helper 실행 여부 확인
    public var isRunning: @Sendable () async -> Bool
    public var terminationEvents: @Sendable () -> AsyncStream<Void>

    public nonisolated init(
        start: @escaping @Sendable () async -> Void,
        stop: @escaping @Sendable () async -> Void,
        isRunning: @escaping @Sendable () async -> Bool,
        terminationEvents: @escaping @Sendable () -> AsyncStream<Void>,
    ) {
        self.start = start
        self.stop = stop
        self.isRunning = isRunning
        self.terminationEvents = terminationEvents
    }
}

extension HelperAppClient: DependencyKey {
    public nonisolated static var liveValue: HelperAppClient {
        HelperAppClient(
            start: {
                await MainActor.run {
                    launchHelperOnce(resolveHelperInfo())
                }
            },
            stop: {
                await MainActor.run {
                    terminateHelper(resolveHelperInfo())
                }
            },
            isRunning: {
                await MainActor.run {
                    let info = resolveHelperInfo()
                    return NSWorkspace.shared.runningApplications.contains { app in
                        app.bundleIdentifier == info.bundleId
                    }
                }
            },
            terminationEvents: {
                AsyncStream { continuation in
                    Task { @MainActor in
                        let info = resolveHelperInfo()
                        let observer = NSWorkspace.shared.notificationCenter.addObserver(
                            forName: NSWorkspace.didTerminateApplicationNotification,
                            object: nil,
                            queue: .main,
                        ) { notification in
                            guard
                                let app = notification
                                .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                                app.bundleIdentifier == info.bundleId
                            else { return }

                            continuation.yield(())
                        }

                        continuation.onTermination = { _ in
                            Task { @MainActor in
                                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                            }
                        }
                    }
                }
            },
        )
    }

    public nonisolated static var testValue: HelperAppClient {
        HelperAppClient(
            start: {},
            stop: {},
            isRunning: { false },
            terminationEvents: { AsyncStream { $0.finish() } },
        )
    }

    public nonisolated static var previewValue: HelperAppClient {
        HelperAppClient(
            start: {},
            stop: {},
            isRunning: { false },
            terminationEvents: { AsyncStream { $0.finish() } },
        )
    }
}

public extension DependencyValues {
    nonisolated var helperAppClient: HelperAppClient {
        get { self[HelperAppClient.self] }
        set { self[HelperAppClient.self] = newValue }
    }
}

private struct HelperLifecycleInfo {
    let bundleId: String
    let url: URL
}

@MainActor
private func resolveHelperInfo() -> HelperLifecycleInfo {
    let fm = FileManager.default
    let bundleURL = Bundle.main.bundleURL

    let embedded = bundleURL.appendingPathComponent("Contents/Helpers/VoyagerHelper.app")
    let helperURL: URL

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

    return HelperLifecycleInfo(bundleId: bundleId, url: helperURL)
}

@MainActor
private func launchHelperOnce(_ info: HelperLifecycleInfo) {
    let runningApps = NSWorkspace.shared.runningApplications
    let isHelperRunning = runningApps.contains { app in
        app.bundleIdentifier == info.bundleId
    }

    if !isHelperRunning {
        let config = NSWorkspace.OpenConfiguration()
        if let helperEnvironment = resolveHelperEnvironment() {
            config.environment = helperEnvironment
        }
        NSWorkspace.shared.openApplication(at: info.url, configuration: config) { _, _ in }
    }
}

@MainActor
private func resolveHelperEnvironment() -> [String: String]? {
    let environment = ProcessInfo.processInfo.environment
    if let projectRoot = environment["VOYAGER_PROJECT_ROOT"], !projectRoot.isEmpty {
        return environment
    }
    return nil
}

@MainActor
private func terminateHelper(_ info: HelperLifecycleInfo) {
    let runningApps = NSWorkspace.shared.runningApplications
    if let helper = runningApps.first(where: { $0.bundleIdentifier == info.bundleId }) {
        helper.terminate()
    }
}
