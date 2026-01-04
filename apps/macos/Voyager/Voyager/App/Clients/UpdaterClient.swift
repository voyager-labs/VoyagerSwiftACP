import AppKit
import ComposableArchitecture
import Foundation
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
private final class UpdaterCoordinator {
    static let shared = UpdaterCoordinator()
    private var controller: SPUStandardUpdaterController?

    func configureIfNeeded() {
        guard controller == nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )

        controller?.updater.automaticallyChecksForUpdates = true

        let automaticUpdates = UserDefaults.standard
            .object(forKey: SettingsKeys.automaticUpdate) as? Bool ?? false
        controller?.updater.automaticallyDownloadsUpdates = automaticUpdates
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

        let notifications = NotificationCenter.default.notifications(
            named: NSWindow.didBecomeMainNotification,
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
}
