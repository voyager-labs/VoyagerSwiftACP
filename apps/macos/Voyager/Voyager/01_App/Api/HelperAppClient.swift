@preconcurrency import AppKit
import ComposableArchitecture
import Darwin
import Foundation
import Logging

public struct HelperAppClient: Sendable {
    public var start: @Sendable () async -> Void
    public var stop: @Sendable () async -> Void
    public var isRunning: @Sendable () async -> Bool
    public var terminationEvents: @Sendable () -> AsyncStream<Void>
    public var ensureRunning: @Sendable () async -> Void

    public nonisolated init(
        start: @escaping @Sendable () async -> Void,
        stop: @escaping @Sendable () async -> Void,
        isRunning: @escaping @Sendable () async -> Bool,
        terminationEvents: @escaping @Sendable () -> AsyncStream<Void>,
        ensureRunning: @escaping @Sendable () async -> Void,
    ) {
        self.start = start
        self.stop = stop
        self.isRunning = isRunning
        self.terminationEvents = terminationEvents
        self.ensureRunning = ensureRunning
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
                let logger = Logger(label: "Voyager")
                logger.info("[VOY-122] termination_stream_started -- using kqueue")

                return AsyncStream { continuation in
                    Task {
                        var lastPID: pid_t = 0

                        while !Task.isCancelled {
                            let helperPID = await MainActor.run {
                                findHelperPID()
                            }

                            if let pid = helperPID, pid != lastPID {
                                lastPID = pid
                                logger.info("[VOY-122] kqueue_monitoring_start -- pid=\(pid)")

                                await withCheckedContinuation { (checkedContinuation: CheckedContinuation<
                                    Void,
                                    Never,
                                >) in
                                    Task.detached {
                                        monitorProcessTermination(pid: pid, logger: logger)
                                        checkedContinuation.resume()
                                    }
                                }

                                logger.info("[VOY-122] kqueue_process_terminated -- pid=\(pid)")
                                continuation.yield(())
                            } else if helperPID == nil, lastPID != 0 {
                                lastPID = 0
                            }

                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }

                        logger.info("[VOY-122] termination_stream_terminated")
                        continuation.finish()
                    }
                }
            },
            ensureRunning: {
                let logger = Logger(label: "Voyager")
                logger.info("[VOY-122] helper_ensure_begin")

                let running = await MainActor.run {
                    let helperInfo = resolveHelperInfo()
                    return NSWorkspace.shared.runningApplications.contains { app in
                        app.bundleIdentifier == helperInfo.bundleId
                    }
                }

                if running {
                    logger.info("[VOY-122] helper_ensure_skip -- reason=already_running")
                    return
                }

                logger.info("[VOY-122] helper_ensure_start")
                await MainActor.run {
                    launchHelper(resolveHelperInfo())
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
            ensureRunning: {},
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
            ensureRunning: {},
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
    ) async -> HelperState? {
        let state = await requestStateWithFallback(stateClient: stateClient)
        return await ensureAligned(
            state,
            stateClient: stateClient,
            mainBundleVersion: mainBundleVersion,
        )
    }
}

private extension HelperAppClient {
    private static let log = Logger(label: "Voyager")

    func requestStateWithFallback(
        stateClient: HelperStateClient,
    ) async -> HelperState? {
        await start()

        if let state = await stateClient.resolve() {
            return state
        }

        Self.log.info("[VOY-122] helper_state_missing_restart")
        await stop()
        await start()
        return await stateClient.resolve()
    }

    func ensureAligned(
        _ state: HelperState?,
        stateClient: HelperStateClient,
        mainBundleVersion: String?,
    ) async -> HelperState? {
        guard let state else {
            return state
        }

        guard let mainVersion = mainBundleVersion else {
            return state
        }

        guard let helperVersion = state.helperBundleVersion else {
            Self.log.info("[VOY-122] helper_launch_force_restart_begin -- helper=unknown main=\(mainVersion)")
            await stop()
            await start()
            return await stateClient.resolve()
        }

        guard mainVersion != helperVersion else {
            return state
        }

        Self.log.info("[VOY-122] helper_launch_force_restart_begin -- helper=\(helperVersion) main=\(mainVersion)")
        await stop()
        await start()
        return await stateClient.resolve()
    }
}

private struct HelperLifecycleInfo {
    let bundleId: String
    let url: URL
}

private let voyagerHelperLog = Logger(label: "Voyager")

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
    voyagerHelperLog.info("[VOY-122] helper_launch_begin -- url=\(info.url.path)")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    if let helperEnvironment = resolveHelperEnvironment() {
        configuration.environment = helperEnvironment
    }
    NSWorkspace.shared.openApplication(at: info.url, configuration: configuration) { runningApp, error in
        Task { @MainActor in
            if let app = runningApp {
                voyagerHelperLog.info("[VOY-122] helper_launch_success -- pid=\(app.processIdentifier)")
            } else if let error {
                voyagerHelperLog.info("[VOY-122] helper_launch_failed -- error=\(error.localizedDescription)")
            } else {
                voyagerHelperLog.info("[VOY-122] helper_launch_failed -- reason=unknown")
            }
        }
    }
}

@MainActor
private func resolveHelperEnvironment() -> [String: String]? {
    let environment = ProcessInfo.processInfo.environment
    var filtered: [String: String] = [:]
    for key in kHelperEnvironmentKeys {
        if let value = environment[key], !value.isEmpty {
            filtered[key] = value
        }
    }
    return filtered.isEmpty ? nil : filtered
}

@MainActor
private func terminateHelperGracefully(_ info: HelperLifecycleInfo) async {
    guard let helper = findRunningHelper(bundleId: info.bundleId) else {
        return
    }

    voyagerHelperLog.info("[VOY-122] helper_stop_begin")

    if helper.bundleURL == nil {
        voyagerHelperLog.info("[VOY-122] helper_stop_bundleurl_nil")
    } else if helper.bundleURL?.lastPathComponent != "VoyagerHelper.app" {
        voyagerHelperLog.info("[VOY-122] helper_stop_bundleurl_unexpected -- \(helper.bundleURL?.path ?? "nil")")
        return
    }

    let pid = helper.processIdentifier
    if kill(pid, SIGTERM) != 0 {
        voyagerHelperLog.info("[VOY-122] helper_stop_sigterm_failed -- errno=\(errno)")
    }

    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 3) {
        voyagerHelperLog.info("[VOY-122] helper_stop_done")
        return
    }

    helper.forceTerminate()
    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 2) {
        voyagerHelperLog.info("[VOY-122] helper_stop_done")
        return
    }

    _ = kill(pid, SIGKILL)
    if await waitForHelperTermination(bundleId: info.bundleId, timeoutSeconds: 2) {
        voyagerHelperLog.info("[VOY-122] helper_stop_forced")
    } else {
        voyagerHelperLog.info("[VOY-122] helper_stop_failed")
    }
}

private let kHelperEnvironmentKeys: [String] = [
    "APP_ENV",
    "PATH",
    "PUBLIC_APP_NAME",
    "PUBLIC_GATEWAY_URL",
    "PUBLIC_HELPER_NAME",
    "PUBLIC_LOG_LEVEL",
    "PUBLIC_SENTRY_DSN",
    "PUBLIC_SENTRY_TRACES_SAMPLE_RATE",
    "PUBLIC_WEB_BASE_URL",
    "VOYAGER_PROJECT_ROOT",
]

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

@MainActor
private func findHelperPID() -> pid_t? {
    let info = resolveHelperInfo()
    return NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == info.bundleId })?
        .processIdentifier
}

private nonisolated func monitorProcessTermination(pid: pid_t, logger: Logger) {
    let kq = kqueue()
    guard kq != -1 else {
        logger.error("[VOY-122] kqueue_create_failed -- errno=\(errno)")
        return
    }
    defer { close(kq) }

    var ke = kevent(
        ident: UInt(pid),
        filter: Int16(EVFILT_PROC),
        flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT),
        fflags: UInt32(NOTE_EXIT),
        data: 0,
        udata: nil,
    )

    let result = kevent(kq, &ke, 1, nil, 0, nil)
    guard result != -1 else {
        logger.error("[VOY-122] kevent_register_failed -- errno=\(errno)")
        return
    }

    logger.info("[VOY-122] kqueue_waiting_for_exit -- pid=\(pid)")

    var event = kevent()
    let eventResult = kevent(kq, nil, 0, &event, 1, nil)

    if eventResult > 0 {
        logger.info("[VOY-122] kqueue_exit_detected -- pid=\(pid)")
    }
}
