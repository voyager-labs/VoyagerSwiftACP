import AppKit
import ComposableArchitecture
import Logging

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private lazy var appLifecycleStore = Store(initialState: AppLifecycleFeature.State()) {
        AppLifecycleFeature()
    }

    private lazy var updaterStore = Store(initialState: UpdaterFeature.State()) {
        UpdaterFeature()
    }

    @Dependency(\.helperAppClient)
    private var helperAppClient

    private var terminationAttemptId: UUID?

    private let fileManagerWindowCoordinator = FileManagerWindowCoordinator.shared

    override init() {
        super.init()
        AppDelegate.shared = self

        let appearanceSettingsClient = AppearanceSettingsClient.liveValue
        let theme = appearanceSettingsClient.loadTheme()
        DispatchQueue.main.async {
            appearanceSettingsClient.applyThemeSync(theme)
        }
    }

    func applicationWillFinishLaunching(_: Notification) {
        _ = fileManagerWindowCoordinator
        appLifecycleStore.send(.willFinishLaunching)
        updaterStore.send(.configureAtLaunch)
    }

    func applicationDidFinishLaunching(_: Notification) {
        appLifecycleStore.send(.didFinishLaunching)
        NSWindow.allowsAutomaticWindowTabbing = true
        fileManagerWindowCoordinator.handleAppDidFinishLaunching()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        fileManagerWindowCoordinator.handleAppReopen(hasVisibleWindows: flag)
    }

    func checkForUpdates() {
        updaterStore.send(.checkForUpdates)
    }

    func setAutomaticUpdate(enabled: Bool) {
        updaterStore.send(.setAutomaticUpdate(enabled))
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    private func checkIndexingStatus() -> Bool {
        false
    }

    private func showQuitAlert(isIndexing: Bool, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            if isIndexing {
                alert.messageText = "Indexing in Progress"
                alert.informativeText = "Indexing is still running. Quitting now may pause background work."
            } else {
                alert.messageText = "Quit Voyager?"
                alert.informativeText = "Are you sure you want to quit?"
            }
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn)
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if terminationAttemptId != nil {
            return .terminateLater
        }

        let attemptId = UUID()
        terminationAttemptId = attemptId

        let shouldAlert = UserDefaults.standard.bool(forKey: SettingsKeys.alertBeforeQuit)
        if shouldAlert {
            let isIndexing = checkIndexingStatus()

            showQuitAlert(isIndexing: isIndexing) { [weak self] shouldQuit in
                guard let self else { return }

                if shouldQuit {
                    startTerminationCleanup(attemptId: attemptId)
                } else {
                    Task { @MainActor in
                        await VoyagerTerminationCoordinator.shared.end()
                        self.replyToTerminate(attemptId: attemptId, shouldTerminate: false)
                    }
                }
            }
            return .terminateLater
        }

        startTerminationCleanup(attemptId: attemptId)
        return .terminateLater
    }

    private func startTerminationCleanup(attemptId: UUID) {
        let lifecycleStore = appLifecycleStore
        let helperClient = helperAppClient
        let logger = Logger(label: "Voyager")

        Task { @MainActor in
            await VoyagerTerminationCoordinator.shared.begin(.userQuit)
            lifecycleStore.send(.willTerminate)

            logger.info("app_terminate_cleanup_begin")

            // Helper stop은 내부적으로 5초 예산으로 SIGTERM→forceTerminate→SIGKILL을 시도한다.
            await helperClient.stop()

            logger.info("app_terminate_cleanup_done")
            self.replyToTerminate(attemptId: attemptId, shouldTerminate: true)
        }

        // fail-safe: cleanup이 어떤 이유로든 지연되어도 앱 종료를 영원히 막지 않는다.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.replyToTerminate(attemptId: attemptId, shouldTerminate: true)
        }
    }

    @MainActor
    private func replyToTerminate(attemptId: UUID, shouldTerminate: Bool) {
        guard terminationAttemptId == attemptId else {
            return
        }

        terminationAttemptId = nil
        NSApplication.shared.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
