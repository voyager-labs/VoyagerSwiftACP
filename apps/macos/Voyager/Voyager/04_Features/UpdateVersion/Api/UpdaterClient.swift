import AppKit
import ComposableArchitecture
import Foundation
import Logging
@preconcurrency import Sparkle

public struct UpdaterClient: Sendable {
    public var configure: @Sendable () async -> Void
    public var startAtLaunch: @Sendable () async -> Void
    public var checkForUpdates: @Sendable () async -> Void
    public var setAutomaticUpdate: @Sendable (Bool) async -> Void

    public nonisolated init(
        configure: @escaping @Sendable () async -> Void,
        startAtLaunch: @escaping @Sendable () async -> Void,
        checkForUpdates: @escaping @Sendable () async -> Void,
        setAutomaticUpdate: @escaping @Sendable (Bool) async -> Void,
    ) {
        self.configure = configure
        self.startAtLaunch = startAtLaunch
        self.checkForUpdates = checkForUpdates
        self.setAutomaticUpdate = setAutomaticUpdate
    }
}

extension UpdaterClient: DependencyKey {
    public nonisolated static var liveValue: UpdaterClient {
        UpdaterClient(
            configure: {
                await UpdaterCoordinator.shared.configureIfNeeded()
            },
            startAtLaunch: {
                await UpdaterCoordinator.shared.startAtLaunch()
            },
            checkForUpdates: {
                await UpdaterCoordinator.shared.checkForUpdates()
            },
            setAutomaticUpdate: { enabled in
                await UpdaterCoordinator.shared.setAutomaticUpdate(enabled)
            },
        )
    }

    public nonisolated static var testValue: UpdaterClient {
        UpdaterClient(
            configure: {},
            startAtLaunch: {},
            checkForUpdates: {},
            setAutomaticUpdate: { _ in },
        )
    }

    public nonisolated static var previewValue: UpdaterClient {
        UpdaterClient(
            configure: {},
            startAtLaunch: {},
            checkForUpdates: {},
            setAutomaticUpdate: { _ in },
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

    override private init() {
        super.init()
    }

    func configureIfNeeded() {
        guard controller == nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil,
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
            nil,
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

    func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate _: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void,
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
            await VoyagerTerminationCoordinator.shared.begin(.sparkleRelaunch)
            await HelperAppClient.liveValue.stop()
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
