import AppKit
import Combine
import ComposableArchitecture

extension Notification.Name {
    static let closedTabsChanged = Notification.Name("closedTabsChanged")
    static let focusHistoryChanged = Notification.Name("focusHistoryChanged")
}

@MainActor
final class FileManagerWindowCoordinator: ObservableObject {
    static let shared = FileManagerWindowCoordinator()

    @Published var hasSelectedItems: Bool = false
    @Published var hasClipboardItems: Bool = false
    @Published var hasStore: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var currentFileManagerStore: StoreOf<FileManagerFeature>?

    private let onboardingWindowClient: OnboardingWindowClient
    private let registryClient: RegistryClient

    private(set) var windowControllers: [FileManagerWindowController] = []
    private var closedTabHistory: [FileManagerFeature.State] = []
    private var focusHistory: [NSWindow] = []
    private var isNavigatingFocusHistory: Bool = false

    init(
        onboardingWindowClient: OnboardingWindowClient = .liveValue,
        registryClient: RegistryClient = RegistryClient.live(snapshot: RegistrySnapshot.load()),
    ) {
        self.onboardingWindowClient = onboardingWindowClient
        self.registryClient = registryClient
    }

    func handleAppDidFinishLaunching() {
        if onboardingWindowClient.showIfNeeded() {
            return
        }
        if windowControllers.isEmpty {
            createNewWindow()
        }
    }

    func handleAppReopen(hasVisibleWindows flag: Bool) -> Bool {
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

    @discardableResult
    func createNewWindow(path: String? = nil) -> FileManagerWindowController? {
        if onboardingWindowClient.showIfNeeded() {
            return nil
        }
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

    func focusWindow(path: String) {
        let targetController = windowControllers.first { controller in
            controller.store.currentPath == path
        }
        targetController?.window?.makeKeyAndOrderFront(nil)
    }

    private func activeWindowController() -> FileManagerWindowController? {
        if let keyWindow = NSApp.keyWindow {
            return windowControllers.first { $0.window == keyWindow }
        }
        return windowControllers.first
    }
}
