@preconcurrency import AppKit
import ComposableArchitecture
import Darwin
import Foundation
import Logging

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
                    launchHelper(resolveHelperInfo())
                }
            },
            stop: {
                await terminateHelperGracefully(resolveHelperInfo())
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
            start: {
                fatalError("helperAppClient.start test dependency is not configured")
            },
            stop: {
                fatalError("helperAppClient.stop test dependency is not configured")
            },
            isRunning: { false },
            terminationEvents: { AsyncStream { $0.finish() } },
        )
    }

    public nonisolated static var previewValue: HelperAppClient {
        HelperAppClient(
            start: {
                fatalError("helperAppClient.start preview dependency is not configured")
            },
            stop: {
                fatalError("helperAppClient.stop preview dependency is not configured")
            },
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

public extension HelperAppClient {
    func resolveAlignedState(
        stateClient: HelperStateClient,
        mainBundleVersion: String?,
        logger: Logger,
    ) async -> HelperState? {
        let state = await requestStateWithFallback(stateClient: stateClient, logger: logger)
        return await ensureAligned(
            state,
            stateClient: stateClient,
            mainBundleVersion: mainBundleVersion,
            logger: logger,
        )
    }
}

private extension HelperAppClient {
    func requestStateWithFallback(
        stateClient: HelperStateClient,
        logger: Logger,
    ) async -> HelperState? {
        // Helper가 떠있다는 전제를 하지 않고, start는 idempotent하다는 가정 하에 항상 호출한다.
        await start()

        // 1) State를 요청한다.
        if let state = await stateClient.resolve() {
            return state
        }

        // 2) state가 안 오면, unresponsive로 판단하고 회수/재기동 후 1회 더 요청한다.
        logger.warning("helper_state_missing_restart")
        await stop()
        await start()
        return await stateClient.resolve()
    }

    func ensureAligned(
        _ state: HelperState?,
        stateClient: HelperStateClient,
        mainBundleVersion: String?,
        logger: Logger,
    ) async -> HelperState? {
        guard let state else {
            return state
        }

        guard let mainVersion = mainBundleVersion else {
            return state
        }

        guard let helperVersion = state.helperBundleVersion else {
            logger.info("helper_launch_force_restart_begin -- helper=unknown main=\(mainVersion)")
            await stop()
            await start()
            return await stateClient.resolve()
        }

        guard mainVersion != helperVersion else {
            return state
        }

        logger.info("helper_launch_force_restart_begin -- helper=\(helperVersion) main=\(mainVersion)")
        await stop()
        await start()
        return await stateClient.resolve()
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
private func launchHelper(_ info: HelperLifecycleInfo) {
    let logger = Logger(label: "Voyager")

    let runningApps = NSWorkspace.shared.runningApplications
    let isHelperRunning = runningApps.contains { app in
        app.bundleIdentifier == info.bundleId
    }
    if isHelperRunning {
        return
    }

    logger.info("helper_launch_begin")
    let config = NSWorkspace.OpenConfiguration()
    if let helperEnvironment = resolveHelperEnvironment() {
        config.environment = helperEnvironment
    }
    NSWorkspace.shared.openApplication(at: info.url, configuration: config) { _, error in
        if let error {
            logger.error("helper_launch_failed -- \(String(describing: error))")
        }
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
private func terminateHelperGracefully(_ info: HelperLifecycleInfo) async {
    let logger = Logger(label: "Voyager")

    guard let helper = findRunningHelper(bundleId: info.bundleId) else {
        return
    }

    logger.info("helper_stop_begin")

    if helper.bundleURL == nil {
        logger.warning("helper_stop_bundleurl_nil")
    } else if helper.bundleURL?.lastPathComponent != "VoyagerHelper.app" {
        logger.warning("helper_stop_bundleurl_unexpected -- \(helper.bundleURL?.path ?? "nil")")
        return
    }

    let pid = helper.processIdentifier
    if kill(pid, SIGTERM) != 0 {
        logger.warning("helper_stop_sigterm_failed -- errno=\(errno)")
    }

    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 3) {
        logger.info("helper_stop_done")
        return
    }

    helper.forceTerminate()
    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 2) {
        logger.info("helper_stop_done")
        return
    }

    _ = kill(pid, SIGKILL)
    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 2) {
        logger.warning("helper_stop_forced")
    } else {
        logger.error("helper_stop_failed")
    }
}

@MainActor
private func findRunningHelper(bundleId: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId })
}

@MainActor
private func waitForHelperTermination(bundleId: String, timeoutSeconds: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        let isRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleId
        }
        if !isRunning {
            return true
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    return !NSWorkspace.shared.runningApplications.contains { app in
        app.bundleIdentifier == bundleId
    }
}
