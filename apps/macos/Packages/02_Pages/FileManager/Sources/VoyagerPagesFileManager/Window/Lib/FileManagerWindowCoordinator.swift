import AppKit
import Combine
import ComposableArchitecture
import QuickLookUI
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@MainActor
public final class FileManagerWindowCoordinator: NSWindowController, NSWindowDelegate,
    EntryQuickLookPanelEventHandling
{
    public let windowID: UUID
    public let store: StoreOf<FileManagerFeature>
    private let fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry
    private let onBecameKey: (@MainActor (UUID) -> Void)?
    private let onResignedKey: (@MainActor (UUID) -> Void)?
    private let onWillClose: (@MainActor (UUID) -> Void)?
    private let initialWindowSizeProvider: (() -> NSSize?)?
    @Dependency(\.entryQuickLookClient)
    private var entryQuickLookClient
    private weak var windowSplitCoordinator: FileManagerWindowSplitCoordinator?
    private var cancellables: Set<AnyCancellable> = []

    private struct FileManagerWindowSplitInputs {
        let workspaceClient: WorkspaceClient
        let materialOverride: FileManagerWindowMaterialOverride?
    }

    public init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        self.windowID = windowID
        self.store = store
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            splitInputs: FileManagerWindowSplitInputs(
                workspaceClient: workspaceClient,
                materialOverride: nil,
            ),
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
        window.delegate = self
        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    init(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        materialOverride: FileManagerWindowMaterialOverride? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        self.windowID = windowID
        self.store = store
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            splitInputs: FileManagerWindowSplitInputs(
                workspaceClient: workspaceClient,
                materialOverride: materialOverride,
            ),
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
        window.delegate = self
        store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    init(
        registryClient: RegistryClient,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        path: String? = nil,
        workspaceClient: WorkspaceClient = .liveValue,
        duplicateState: FileManagerFeature.State? = nil,
        onBecameKey: (@MainActor (UUID) -> Void)? = nil,
        onResignedKey: (@MainActor (UUID) -> Void)? = nil,
        onWillClose: (@MainActor (UUID) -> Void)? = nil,
        initialWindowSizeProvider: (() -> NSSize?)? = nil,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)? = nil,
    ) {
        let windowID = UUID()
        let state = Self.createInitialState(
            windowID: windowID,
            path: path,
            duplicateState: duplicateState,
        )
        let store = Self.createStore(
            state: state,
            fileOperationUndoManagerRegistry: fileOperationUndoManagerRegistry,
            registryClient: registryClient,
        )

        if duplicateState == nil {
            store.send(.content(.entryViewLayout(.entryOperations(.lifecycle(.windowIDChanged(windowID))))))
            store.send(.internal(.sidebarEntryDrop(.lifecycle(.windowIDChanged(windowID)))))
        }

        self.windowID = windowID
        self.store = store
        self.fileOperationUndoManagerRegistry = fileOperationUndoManagerRegistry
        Self.activateInitialScopes(
            windowID: windowID,
            store: store,
            registry: fileOperationUndoManagerRegistry,
        )
        self.onBecameKey = onBecameKey
        self.onResignedKey = onResignedKey
        self.onWillClose = onWillClose
        self.initialWindowSizeProvider = initialWindowSizeProvider

        let window = Self.makeWindow(
            store: store,
            path: path,
            splitInputs: FileManagerWindowSplitInputs(
                workspaceClient: workspaceClient,
                materialOverride: nil,
            ),
            makeContentViewController: makeContentViewController,
            initialWindowSizeProvider: initialWindowSizeProvider,
        )

        super.init(window: window)
        windowSplitCoordinator = window.contentViewController as? FileManagerWindowSplitCoordinator
        window.delegate = self
        FileManagerWindowChrome.bindTitle(to: window, store: store, cancellables: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func createInitialState(
        windowID: UUID,
        path: String?,
        duplicateState: FileManagerFeature.State?,
    ) -> FileManagerFeature.State {
        var state: FileManagerFeature.State = if let duplicateState {
            duplicateState
        } else {
            FileManagerFeature.State()
        }

        if duplicateState != nil {
            for tabID in state.contentTabs.tabs.ids {
                guard var tabContent = state.tabContentStates[tabID]
                    ?? (tabID == state.contentTabs.activeTabID ? state.content : nil)
                else { continue }
                let loadingCancellationOwnerID = UUID()
                tabContent.entryViewLayout.entryOperations.resetForDuplicate(
                    windowID: windowID,
                    loadingCancellationOwnerID: loadingCancellationOwnerID,
                    undoOwnerID: UUID(),
                )
                tabContent.composer.cancellationOwnerID = windowID
                tabContent.entryViewLayout.collectionWindowID = windowID
                tabContent.entryViewLayout.collectionLoadingCancellationOwnerID = loadingCancellationOwnerID
                tabContent.entryViewLayout.selectedIds = []
                tabContent.entryViewLayout.lastSelectedId = nil
                tabContent.entryViewLayout.rangeAnchorId = nil
                tabContent.entryViewLayout.shouldScrollToSelection = false
                state.tabContentStates[tabID] = tabContent
            }
            if let activeTabID = state.contentTabs.activeTabID,
               let activeContent = state.tabContentStates[activeTabID]
            {
                state.content = activeContent
            }
        }

        if let path {
            state.content.navigation.seedInitialFolderPath(path)
            state.syncActiveTabContentState()
        }

        return state
    }

    private static func createStore(
        state: FileManagerFeature.State,
        fileOperationUndoManagerRegistry: FileOperationUndoManagerRegistry,
        registryClient: RegistryClient,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileOperationUndoManagerClient = .live(registry: fileOperationUndoManagerRegistry)
            $0.registryClient = registryClient
        }
    }

    private static func activateInitialScopes(
        windowID: UUID,
        store: StoreOf<FileManagerFeature>,
        registry: FileOperationUndoManagerRegistry,
    ) {
        let tabIDs = store.withState { $0.contentTabs.tabs.ids }
        for tabID in tabIDs {
            registry.activate(UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue))
        }
    }

    private static func makeWindow(
        store: StoreOf<FileManagerFeature>,
        path: String?,
        splitInputs: FileManagerWindowSplitInputs,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)?,
        initialWindowSizeProvider: (() -> NSSize?)?,
    ) -> NSWindow {
        let contentViewController: NSViewController = if let makeContentViewController {
            makeContentViewController(store, path)
        } else {
            FileManagerWindowSplitCoordinator(
                store: store,
                isDark: FileManagerWindowChrome.currentIsDark,
                workspaceClient: splitInputs.workspaceClient,
                materialOverride: splitInputs.materialOverride,
            )
        }

        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowChrome.configureWindowStyle(window)
        FileManagerWindowChrome.applyInitialFrame(window, initialWindowSizeProvider: initialWindowSizeProvider)
        return window
    }

    static func configureWindowStyle(_ window: NSWindow) {
        FileManagerWindowChrome.configureWindowStyle(window)
    }

    static func applyTrafficLightVisibility(to window: NSWindow, isSidebarVisible: Bool) {
        FileManagerWindowChrome.applyTrafficLightVisibility(to: window, isSidebarVisible: isSidebarVisible)
    }

    func updateMaterialOverride(_ override: FileManagerWindowMaterialOverride?) {
        windowSplitCoordinator?.updateMaterialOverride(override)
    }

    private func tearDownBindings() {
        cancellables.removeAll()
    }
}

// MARK: - NSWindowDelegate

public extension FileManagerWindowCoordinator {
    func windowDidBecomeKey(_: Notification) {
        if let onBecameKey {
            onBecameKey(windowID)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        let documentWindow = notification.object as? NSWindow ?? window
        guard !Self.shouldRetainLogicalFocus(
            documentIsMain: documentWindow?.isMainWindow == true,
            keyWindow: NSApp.keyWindow,
        ) else { return }
        if let onResignedKey {
            onResignedKey(windowID)
        }
    }

    static func shouldRetainLogicalFocus(
        documentIsMain: Bool,
        keyWindow: NSWindow?,
    ) -> Bool {
        documentIsMain && keyWindow is QLPreviewPanel
    }

    /// Quick Look 제어 중 보류한 resign을 이 시점에 정산해야 하는지 판정한다.
    /// document가 key로 돌아왔으면 정산이 불필요하고, QL이 여전히 key이고 document가
    /// main인 동안에는 logical focus 유지 조건을 존중한다.
    static func shouldSettleRetainedResignKey(
        documentIsKey: Bool,
        documentIsMain: Bool,
        keyWindow: NSWindow?,
    ) -> Bool {
        guard !documentIsKey else { return false }
        return !shouldRetainLogicalFocus(documentIsMain: documentIsMain, keyWindow: keyWindow)
    }

    /// QuickLookUI의 NSObject hooks는 nonisolated로 import되지만 AppKit responder dispatch는 main thread에서 실행된다.
    override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated {
            canControlQuickLookPanel()
        }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel, canControlQuickLookPanel() else { return }
            entryQuickLookClient.beginPreviewPanelControl(panel, self)
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            guard let panel else { return }
            entryQuickLookClient.endPreviewPanelControl(panel, self)
            settleRetainedResignKeyIfNeeded()
        }
    }

    /// Quick Look panel은 앱 전체에 하나뿐이므로 background window가 responder-chain owner가 되지 않게 한다.
    /// `isFocused`는 WindowManager가 key transition과 Quick Look logical focus를 반영한 단일 ownership source다.
    private func canControlQuickLookPanel() -> Bool {
        guard store.withState({ $0.isFocused && !$0.content.entryViewLayout.selectedIds.isEmpty }) else {
            return false
        }
        return entryQuickLookClient.acceptsPreviewPanelControl()
    }

    /// Quick Look이 key를 비-FileManager window에 넘기거나 앱이 비활성화되면 document는
    /// 두 번째 resignKey를 받지 못한다. 제어 종료 시점에 보류한 resign을 정산해
    /// `focusedWindowID`/`isFocused`가 이전 document에 머무르지 않게 한다.
    private func settleRetainedResignKeyIfNeeded() {
        guard let window,
              Self.shouldSettleRetainedResignKey(
                  documentIsKey: window.isKeyWindow,
                  documentIsMain: window.isMainWindow,
                  keyWindow: NSApp.keyWindow,
              )
        else { return }
        onResignedKey?(windowID)
    }

    func handleQuickLookPanelEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.isDisjoint(with: [.command, .option, .control]),
              (123 ... 126).contains(event.keyCode)
        else { return false }

        store.send(.view(.quickLookKeyCommand(KeyCommand(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        ))))
        return true
    }

    func window(
        _: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions,
    ) -> NSApplication.PresentationOptions {
        var options = proposedOptions
        options.insert(.autoHideMenuBar)
        options.insert(.autoHideDock)
        options.insert(.fullScreen)

        if #available(macOS 11.0, *) {
            options.insert(.autoHideToolbar)
        }
        return options
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        FileManagerWindowChrome.saveFrame(window)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            FileManagerWindowChrome.saveFrame(window)
        }
        fileOperationUndoManagerRegistry.deactivateAll(windowID: windowID)
        tearDownBindings()
        if let onWillClose {
            onWillClose(windowID)
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        true
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        guard let activeTabID = store.withState(\.contentTabs.activeTabID) else {
            return nil
        }
        return fileOperationUndoManagerRegistry.undoManager(for: UndoManagerScope(
            windowID: windowID,
            contentTabID: activeTabID.rawValue,
        ))
    }
}
