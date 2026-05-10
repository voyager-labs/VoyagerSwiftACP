import AppKit
import ComposableArchitecture
import Foundation
import Logging
@preconcurrency import Sparkle
import VoyagerShared

public struct UpdaterClient: Sendable {
    public var configure: @Sendable () async -> Void
    public var startAtLaunch: @Sendable () async -> Void
    public var checkForUpdates: @Sendable () async -> Void
    public var setAutomaticUpdate: @Sendable (Bool) async -> Void
    public var prepareForRelaunch: @Sendable () async -> Void
    public var stopHelperApp: @Sendable () async -> Void

    public nonisolated init(
        configure: @escaping @Sendable () async -> Void,
        startAtLaunch: @escaping @Sendable () async -> Void,
        checkForUpdates: @escaping @Sendable () async -> Void,
        setAutomaticUpdate: @escaping @Sendable (Bool) async -> Void,
        prepareForRelaunch: @escaping @Sendable () async -> Void = {},
        stopHelperApp: @escaping @Sendable () async -> Void = {}
    ) {
        self.configure = configure
        self.startAtLaunch = startAtLaunch
        self.checkForUpdates = checkForUpdates
        self.setAutomaticUpdate = setAutomaticUpdate
        self.prepareForRelaunch = prepareForRelaunch
        self.stopHelperApp = stopHelperApp
    }
}

extension UpdaterClient: DependencyKey {
    public nonisolated static var liveValue: UpdaterClient {
        let coordinator = UpdaterCoordinator.shared
        return UpdaterClient(
            configure: {
                await coordinator.configureIfNeeded()
            },
            startAtLaunch: {
                await coordinator.startAtLaunch()
            },
            checkForUpdates: {
                await coordinator.checkForUpdates()
            },
            setAutomaticUpdate: { enabled in
                await coordinator.setAutomaticUpdate(enabled)
            },
            prepareForRelaunch: {
                await coordinator.prepareForRelaunch()
            },
            stopHelperApp: {
                await coordinator.stopHelperApp()
            }
        )
    }

    public nonisolated static var testValue: UpdaterClient {
        UpdaterClient(
            configure: {},
            startAtLaunch: {},
            checkForUpdates: {},
            setAutomaticUpdate: { _ in },
            prepareForRelaunch: {},
            stopHelperApp: {}
        )
    }

    public nonisolated static var previewValue: UpdaterClient {
        UpdaterClient(
            configure: {},
            startAtLaunch: {},
            checkForUpdates: {},
            setAutomaticUpdate: { _ in },
            prepareForRelaunch: {},
            stopHelperApp: {}
        )
    }
}

public extension DependencyValues {
    nonisolated var updaterClient: UpdaterClient {
        get { self[UpdaterClient.self] }
        set { self[UpdaterClient.self] = newValue }
    }
}

@MainActor
private final class UpdaterCoordinator: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterCoordinator()
    private var controller: SPUStandardUpdaterController?
    private var pendingRelaunchAttemptId: UUID?
    private var didInvokeInstallHandler = false
    var prepareForRelaunchAction: @Sendable () async -> Void = {}
    var stopHelperAppAction: @Sendable () async -> Void = {}

    override private init() {
        super.init()
    }

    func configureIfNeeded() {
        guard controller == nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        configureIfNeeded()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticUpdate(_ enabled: Bool) {
        configureIfNeeded()
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func startAtLaunch() async {
        configureIfNeeded()
        guard let updater = controller?.updater else { return }

        let notificationCenterClient = NotificationCenterClient.liveValue
        let notifications = notificationCenterClient.notifications(
            NSWindow.didBecomeMainNotification,
            nil
        )

        if NSApp.keyWindow != nil {
            updater.checkForUpdatesInBackground()
            return
        }

        for await _ in notifications {
            updater.checkForUpdatesInBackground()
            break
        }
    }

    func prepareForRelaunch() async {
        await prepareForRelaunchAction()
    }

    func stopHelperApp() async {
        await stopHelperAppAction()
    }

    func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate _: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let logger = Logger(label: "Voyager")
        logger.info("sparkle_postpone_relaunch_begin")

        let attemptId: UUID
        if let pendingRelaunchAttemptId {
            attemptId = pendingRelaunchAttemptId
        } else {
            attemptId = UUID()
            pendingRelaunchAttemptId = attemptId
            didInvokeInstallHandler = false
        }

        Task { @MainActor in
            await prepareForRelaunch()
            await stopHelperApp()
            logger.info("sparkle_postpone_relaunch_end")
            invokeInstallHandlerOnce(attemptId: attemptId, installHandler)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            invokeInstallHandlerOnce(attemptId: attemptId, installHandler)
        }

        return true
    }

    private func invokeInstallHandlerOnce(attemptId: UUID, _ installHandler: @escaping () -> Void) {
        guard pendingRelaunchAttemptId == attemptId, !didInvokeInstallHandler else { return }
        didInvokeInstallHandler = true
        pendingRelaunchAttemptId = nil
        installHandler()
    }
}
