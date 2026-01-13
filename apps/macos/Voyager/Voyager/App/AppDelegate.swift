import AppKit
import Combine
import ComposableArchitecture
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

    @Dependency(\.onboardingWindowClient)
    private var onboardingWindowClient
    // TODO: 온보딩 게이트 판단/표시 호출을 전용 경로로 모아 중복 체크를 제거한다.

    @Published var hasSelectedItems: Bool = false
    @Published var hasClipboardItems: Bool = false
    @Published var hasStore: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var currentFileManagerStore: StoreOf<FileManagerFeature>?

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
        canUndo = store.fsItems.canUndoEntryAction
        canRedo = store.fsItems.canRedoEntryAction
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

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let shouldAlert = UserDefaults.standard.bool(forKey: SettingsKeys.alertBeforeQuit)

        guard shouldAlert else {
            return .terminateNow
        }

        let isIndexing = checkIndexingStatus()

        showQuitAlert(isIndexing: isIndexing) { shouldQuit in
            if shouldQuit {
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            } else {
                NSApplication.shared.reply(toApplicationShouldTerminate: false)
            }
        }

        return .terminateLater
    }

    @discardableResult
    @objc
    func createNewWindow(path: String? = nil) -> FileManagerWindowController? {
        if onboardingWindowClient.showIfNeeded() {
            return nil
        }
        // TODO: 모든 윈도우 생성 경로를 여기로 통합해 게이트 적용 지점을 단일화한다.
        let controller = FileManagerWindowController(path: path, asTab: false)
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

        let controller = FileManagerWindowController(path: path, duplicateState: duplicateState, asTab: true)
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

    func applicationWillTerminate(_: Notification) {
        appLifecycleStore.send(.willTerminate)
    }

    func application(_: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard isVoyagerCollectionURL(url) else { return false }
        Task { @MainActor in
            openCollectionFiles(urls: [url])
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }.filter(isVoyagerCollectionURL)

        Task { @MainActor in
            openCollectionFiles(urls: urls)
            sender.reply(toOpenOrPrint: .success)
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        let voyagerURLs = urls.filter(isVoyagerCollectionURL)
        guard !voyagerURLs.isEmpty else { return }

        Task { @MainActor in
            openCollectionFiles(urls: voyagerURLs)
        }
    }

    private func checkIndexingStatus() -> Bool {
        // TODO: 추후 인덱싱 기능 구현 시 실제 상태 확인
        false
    }

    private func showQuitAlert(isIndexing: Bool, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = isIndexing
            ? "Indexing is in progress. Quitting will stop the indexing process."
            : "Are you sure you want to quit Voyager?"
        alert.informativeText = isIndexing
            ? "To stop indexing and quit, click 'Quit'."
            : "You may have unsaved work."

        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.showsSuppressionButton = true
        if let suppressionButton = alert.suppressionButton {
            suppressionButton.title = "Alert before app quit"
            suppressionButton.state = UserDefaults.standard.bool(forKey: SettingsKeys.alertBeforeQuit) ? .on : .off
        }

        let response = alert.runModal()
        if let suppressionButton = alert.suppressionButton {
            let shouldAlert = suppressionButton.state == .on
            UserDefaults.standard.set(shouldAlert, forKey: SettingsKeys.alertBeforeQuit)
        }
        completion(response == .alertFirstButtonReturn)
    }

    private func isVoyagerCollectionURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "voycoll"
    }

    @MainActor
    private func openCollectionFile(url: URL) {
        if onboardingWindowClient.showIfNeeded() {
            return
        }
        guard let controller = activeWindowController() ?? createNewWindow() else { return }
        controller.window?.makeKeyAndOrderFront(nil)
        controller.store.send(.openCollectionFile(url))
    }

    @MainActor
    private func openCollectionFiles(urls: [URL]) {
        for url in urls {
            openCollectionFile(url: url)
        }
    }

    @MainActor
    private func activeWindowController() -> FileManagerWindowController? {
        guard let keyWindow = NSApp.keyWindow else {
            return windowControllers.first
        }
        return windowControllers.first { $0.window == keyWindow } ?? windowControllers.first
    }
}
