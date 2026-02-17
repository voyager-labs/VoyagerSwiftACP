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
    private var onboardingWindowClient
    // TODO: 온보딩 게이트 판단/표시 호출을 전용 경로로 모아 중복 체크를 제거한다.

    private lazy var registrySnapshot = RegistrySnapshot.load()
    private lazy var registryClient = RegistryClient.live(snapshot: registrySnapshot)

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
    private var isNavigatingFocusHistory: Bool = false

    var hasValidFocusHistory: Bool {
        let validWindows = focusHistory.filter { window in
            window != NSApp.keyWindow && windowControllers.contains(where: { $0.window == window })
        }
        return !validWindows.isEmpty
    }

    func updateMenuState(store: StoreOf<FileManagerFeature>?) {
        guard let store else {
            hasStore = false
            hasSelectedItems = false
            hasClipboardItems = false
            canUndo = false
            canRedo = false
            currentFileManagerStore = nil
            return
        }

        hasStore = true
        hasSelectedItems = store.hasSelectedItems
        hasClipboardItems = store.hasClipboardItems
        canUndo = store.entries.canUndoEntryAction
        canRedo = store.entries.canRedoEntryAction
        currentFileManagerStore = store
    }

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

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindowClient.showIfNeeded() {
            return true
        }
        if !flag {
            if windowControllers.isEmpty {
                createNewWindow()
            } else {
                activeWindowController()?.window?.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    private func activeWindowController() -> FileManagerWindowController? {
        if let keyWindow = NSApp.keyWindow {
            return windowControllers.first { $0.window == keyWindow }
        }
        return windowControllers.first
    }

    private func showQuitAlert(completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Quit Voyager?"
            alert.informativeText = "Are you sure you want to quit?"
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
            showQuitAlert { [weak self] shouldQuit in
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

    @discardableResult
    @objc
    func createNewWindow(path: String? = nil) -> FileManagerWindowController? {
        if onboardingWindowClient.showIfNeeded() {
            return nil
        }
        // TODO: 모든 윈도우 생성 경로를 여기로 통합해 게이트 적용 지점을 단일화한다.
        let controller = FileManagerWindowController(
            registryClient: registryClient,
            path: path,
            asTab: false,
        )
        windowControllers.append(controller)
        controller.showWindow(nil)
        return controller
    }

    func createNewTab(path: String? = nil, duplicateState: FileManagerFeature.State? = nil) {
        if onboardingWindowClient.showIfNeeded() {
            return
        }
        guard let keyWindow = NSApp.keyWindow else {
            createNewWindow(path: path)
            return
        }

        let controller = FileManagerWindowController(
            registryClient: registryClient,
            path: path,
            duplicateState: duplicateState,
            asTab: true,
        )
        windowControllers.append(controller)

        if let newWindow = controller.window {
            keyWindow.addTabbedWindow(newWindow, ordered: .above)
            newWindow.makeKeyAndOrderFront(nil)
        }
    }

    func duplicateCurrentTab() {
        guard let keyWindow = NSApp.keyWindow,
              let controller = windowControllers.first(where: { $0.window == keyWindow })
        else { return }

        createNewTab(duplicateState: controller.store.state)
    }

    func selectTab(at index: Int) {
        guard let window = NSApp.keyWindow,
              let tabGroup = window.tabGroup,
              index < tabGroup.windows.count
        else { return }

        tabGroup.windows[index].makeKeyAndOrderFront(nil)
    }

    func reopenLastClosedTab() {
        guard let state = closedTabHistory.popLast() else { return }
        NotificationCenter.default.post(name: .closedTabsChanged, object: nil)
        createNewTab(path: nil, duplicateState: state)
    }

    func updateFocusHistory(window: NSWindow?) {
        guard let window else { return }

        if isNavigatingFocusHistory {
            isNavigatingFocusHistory = false
            return
        }

        focusHistory.removeAll { $0 == window }

        if focusHistory.count >= 10 {
            focusHistory.removeLast()
        }

        focusHistory.insert(window, at: 0)
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)
    }

    func switchToLastFocusedTab() {
        if let currentWindow = NSApp.keyWindow {
            focusHistory.removeAll { $0 == currentWindow }
        }

        let validWindows = focusHistory.filter { window in
            windowControllers.contains(where: { $0.window == window })
        }

        guard let targetWindow = validWindows.first else { return }

        focusHistory.removeAll { $0 == targetWindow }
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)

        isNavigatingFocusHistory = true
        targetWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(controller: FileManagerWindowController) {
        guard let window = controller.window else {
            windowControllers.removeAll { $0 === controller }
            if windowControllers.isEmpty {
                currentFileManagerStore = nil
            }
            return
        }

        let isTab = window.tabbingMode == .preferred && window.tabbingIdentifier == "file-manager"

        if isTab {
            closedTabHistory.append(controller.store.state)

            if closedTabHistory.count > 10 {
                closedTabHistory.removeFirst()
            }

            NotificationCenter.default.post(name: .closedTabsChanged, object: nil)
        }

        focusHistory.removeAll { $0 == window }
        NotificationCenter.default.post(name: .focusHistoryChanged, object: nil)
        windowControllers.removeAll { $0 === controller }

        if window.isKeyWindow {
            if let newKeyWindow = NSApp.keyWindow,
               let newController = windowControllers.first(where: { $0.window == newKeyWindow })
            {
                updateMenuState(store: newController.store)
            } else {
                updateMenuState(store: nil)
            }
        }
    }
}
