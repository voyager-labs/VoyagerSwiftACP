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

    nonisolated public init(
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
    nonisolated public static var liveValue: UpdaterClient {
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

    nonisolated public static var testValue: UpdaterClient {
        UpdaterClient(
            configure: {},
            startAtLaunch: {},
            checkForUpdates: {},
            setAutomaticUpdate: { _ in },
        )
    }

    nonisolated public static var previewValue: UpdaterClient {
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

public enum SparkleUpdateEligibilityGate {
    public static func shouldSkipUpdateChecks(
        appEnv: EnvironmentLoader.AppEnv,
        feedURL: String?,
    ) -> Bool {
        appEnv == .dev || feedURL?.isEmpty != false
    }

    /// The candidate must already have a verified manifest identity. Sparkle does not
    /// determine release trust from a version string.
    public static func requireCandidate(
        candidate _: ReleaseIdentity,
    ) throws {}
}

@MainActor
private final class UpdaterCoordinator: NSObject, @preconcurrency SPUUpdaterDelegate {
    static let shared = UpdaterCoordinator()
    private var controller: SPUStandardUpdaterController?
    private var pendingRelaunchAttemptId: UUID?
    private var didInvokeInstallHandler = false
    var prepareForRelaunchAction: @Sendable () async -> Void = {}
    var stopHelperAppAction: @Sendable () async -> Void = {}

    private let logger = Logger(label: "Voyager")

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
        let appEnv = EnvironmentLoader.detectAppEnv()
        let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String
        guard !SparkleUpdateEligibilityGate.shouldSkipUpdateChecks(appEnv: appEnv, feedURL: feedURL) else {
            logger.info("sparkle_skip_check_dev")
            return
        }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticUpdate(_ enabled: Bool) {
        configureIfNeeded()
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    func startAtLaunch() async {
        configureIfNeeded()
        let appEnv = EnvironmentLoader.detectAppEnv()
        let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String
        guard !SparkleUpdateEligibilityGate.shouldSkipUpdateChecks(appEnv: appEnv, feedURL: feedURL) else {
            logger.info("sparkle_skip_start_dev")
            return
        }
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

    func prepareForRelaunch() async {
        await prepareForRelaunchAction()
    }

    func stopHelperApp() async {
        await stopHelperAppAction()
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

    func updater(
        _: SPUUpdater,
        shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck _: SPUUpdateCheck,
    ) throws {
        guard let artifactURL = updateItem.fileURL else {
            throw CandidateVerificationError.missingArtifactURL
        }
        let manifestData = try loadManifestData(for: artifactURL)
        let identity = try VerifiedReleaseCandidate.verifiedIdentity(
            manifestData: manifestData,
            artifactURL: artifactURL,
            now: .now,
        )
        try SparkleUpdateEligibilityGate.requireCandidate(
            candidate: identity,
        )
    }

    private func loadManifestData(for artifactURL: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ManifestLoadResult()
        URLSession.shared
            .dataTask(with: VerifiedReleaseCandidate.manifestURL(for: artifactURL)) { data, response, error in
                defer { semaphore.signal() }
                guard error == nil,
                      let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      let data
                else {
                    return
                }
                result.set(.success(data))
            }.resume()
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            throw CandidateVerificationError.manifestUnavailable
        }
        return try result.value().get()
    }

    private func invokeInstallHandlerOnce(attemptId: UUID, _ installHandler: @escaping () -> Void) {
        guard pendingRelaunchAttemptId == attemptId, !didInvokeInstallHandler else { return }
        didInvokeInstallHandler = true
        pendingRelaunchAttemptId = nil
        installHandler()
    }
}

private enum CandidateVerificationError: Error {
    case missingArtifactURL
    case manifestUnavailable
}

private final class ManifestLoadResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Data, Error> = .failure(CandidateVerificationError.manifestUnavailable)

    func set(_ result: Result<Data, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }

    func value() -> Result<Data, Error> {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

public extension UpdaterClient {
    /// Register App-layer relaunch handlers that the package cannot reference directly.
    /// Call this once during app startup before any update check runs.
    @MainActor
    static func registerRelaunchHandlers(
        prepareForRelaunch: @escaping @Sendable () async -> Void,
        stopHelperApp: @escaping @Sendable () async -> Void,
    ) {
        UpdaterCoordinator.shared.prepareForRelaunchAction = prepareForRelaunch
        UpdaterCoordinator.shared.stopHelperAppAction = stopHelperApp
    }
}
