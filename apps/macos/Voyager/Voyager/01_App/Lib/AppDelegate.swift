import AppKit
import Combine
import ComposableArchitecture
import Logging
import SwiftUI

extension Notification.Name {
    static let closedTabsChanged = Notification.Name("closedTabsChanged")
    static let focusHistoryChanged = Notification.Name("focusHistoryChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static var shared: AppDelegate?
    private lazy var appLifecycleStore = Store(initialState: AppLifecycleFeature.State()) {
        AppLifecycleFeature()
    }

    private lazy var updaterStore = Store(initialState: UpdaterFeature.State()) {
        UpdaterFeature()
    }

    @Dependency(\.helperAppClient)
    private var helperAppClient

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient
    // TODO: 온보딩 게이트 판단/표시 호출을 전용 경로로 모아 중복 체크를 제거한다.

    private lazy var registrySnapshot = RegistrySnapshot.load()
    lazy var registryClient = RegistryClient.live(snapshot: registrySnapshot)

    @Published var hasSelectedItems: Bool = false
    @Published var hasClipboardItems: Bool = false
    @Published var hasStore: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var currentFileManagerStore: StoreOf<FileManagerFeature>?

    private var terminationAttemptId: UUID?

    var windowControllers: [FileManagerWindowController] = []
    var closedTabHistory: [FileManagerFeature.State] = []
    var focusHistory: [NSWindow] = []
    var isNavigatingFocusHistory: Bool = false

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
        _ = registrySnapshot
        appLifecycleStore.send(.willFinishLaunching)
        updaterStore.send(.configureAtLaunch)
    }

    func applicationDidFinishLaunching(_: Notification) {
        appLifecycleStore.send(.didFinishLaunching)
        NSWindow.allowsAutomaticWindowTabbing = true
        if onboardingWindowClient.showIfNeeded() {
            return
        }
        if windowControllers.isEmpty {
            createNewWindow()
        }
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
