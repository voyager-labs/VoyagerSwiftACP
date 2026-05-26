import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

@MainActor
final class FileManagerWindowSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let contentVerticalMargin: CGFloat = 4
    }

    let store: StoreOf<FileManagerFeature>
    let keyCommandFocusCoordinator = FileManagerKeyCommandFocusCoordinator()

    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasTornDown = false
    private var isApplyingSidebarLayout = false

    private var sidebarSync: FileManagerSidebarSync
    private var currentIsDark: Bool

    private var sidebarHosting: NSHostingController<AnyView>?
    private var mainContainerHosting: NSHostingController<FileManagerWindowMainContainerView>?

    private weak var windowSplitView: NSSplitView?
    private weak var mainContainerView: NSView?

    private var mainContainerLeading: NSLayoutConstraint?

    init(store: StoreOf<FileManagerFeature>, isDark: Bool) {
        self.store = store
        sidebarSync = FileManagerSidebarSync(storeSidebarWidth: store.sidebar.sidebarWidth)
        currentIsDark = isDark
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let components = FileManagerWindowSplitLayout.build(
            store: store,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
            mainContainerRootView: makeMainContainerRootView(),
            contentVerticalMargin: Constants.contentVerticalMargin,
            isSidebarVisible: store.sidebar.sidebarVisible,
        )

        windowSplitView = components.splitView
        windowSplitView?.delegate = self

        sidebarHosting = components.sidebarHosting
        mainContainerHosting = components.mainContainerHosting
        mainContainerView = components.mainContainerView
        mainContainerLeading = components.mainContainerLeading

        addChild(components.sidebarHosting)
        addChild(components.mainContainerHosting)

        view = components.rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applySidebarLayout {
            sidebarSync.applyInitialLayoutIfNeeded(
                sidebarVisible: store.sidebar.sidebarVisible,
                sidebarWidth: store.sidebar.sidebarWidth,
                splitView: windowSplitView,
                mainContainerLeading: mainContainerLeading,
                contentVerticalMargin: Constants.contentVerticalMargin,
            ) { [weak self] isSidebarVisible in
                self?.updateTrafficLightVisibility(isSidebarVisible: isSidebarVisible)
            }
        }
    }

    private func applySidebarState(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        applySidebarLayout {
            sidebarSync.applySidebarState(
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                layout: makeSidebarSyncLayout(),
                callbacks: makeSidebarSyncCallbacks(),
            )
        }
    }

    private func applySidebarLayout(_ operation: () -> Void) {
        guard !isApplyingSidebarLayout else { return }
        isApplyingSidebarLayout = true
        defer { isApplyingSidebarLayout = false }
        operation()
    }

    func updateAppearance(isDark: Bool) {
        currentIsDark = isDark
        FileManagerWindowSplitLayout.applySplitBackground(windowSplitView)
        mainContainerHosting?.rootView = makeMainContainerRootView()
    }

    func tearDown() {
        guard !hasTornDown else { return }
        hasTornDown = true
        cancellables.removeAll()

        windowSplitView?.delegate = nil

        sidebarHosting?.removeFromParent()
        mainContainerHosting?.removeFromParent()

        sidebarHosting = nil
        mainContainerHosting = nil
        store.send(.onDisappear)
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        observeSidebarState()
        applySidebarState(
            sidebarVisible: store.sidebar.sidebarVisible,
            sidebarWidth: store.sidebar.sidebarWidth,
        )
        store.send(.onAppear)
    }

    private func observeSidebarState() {
        store.publisher.sidebar
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sidebarState in
                guard let self else { return }
                applySidebarState(
                    sidebarVisible: sidebarState.sidebarVisible,
                    sidebarWidth: sidebarState.sidebarWidth,
                )
            }
            .store(in: &cancellables)
    }

    private func makeMainContainerRootView() -> FileManagerWindowMainContainerView {
        FileManagerWindowMainContainerView(
            store: store,
            isDark: currentIsDark,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0: return FileManagerSidebarSync.sidebarMinWidth
        default: return proposedMinimumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedMaximumPosition }
        switch dividerIndex {
        case 0: return FileManagerSidebarSync.sidebarMaxWidth
        default: return proposedMaximumPosition
        }
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard splitView === windowSplitView,
              let index = splitView.arrangedSubviews.firstIndex(of: view)
        else { return false }
        return index == 1
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard splitView === windowSplitView,
              let index = splitView.arrangedSubviews.firstIndex(of: subview)
        else { return false }
        return index == 0
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingSidebarLayout else { return }
        guard let splitView = notification.object as? NSSplitView,
              splitView === windowSplitView,
              let sidebarView = sidebarHosting?.view
        else { return }

        let restoreWidth = sidebarSync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: store.sidebar.sidebarVisible,
            syncWidthToStore: { [weak self] width in
                self?.syncSidebarWidthToStore(width)
            },
        )
        if let restoreWidth {
            applySidebarState(sidebarVisible: true, sidebarWidth: restoreWidth)
        }
    }

    private func makeSidebarSyncLayout() -> FileManagerSidebarSync.Layout {
        FileManagerSidebarSync.Layout(
            splitView: windowSplitView,
            sidebarView: sidebarHosting?.view,
            mainContainerLeading: mainContainerLeading,
            contentVerticalMargin: Constants.contentVerticalMargin,
        )
    }

    private func makeSidebarSyncCallbacks() -> FileManagerSidebarSync.Callbacks {
        FileManagerSidebarSync.Callbacks(
            onSidebarVisibilityChanged: { [weak self] _, width in
                self?.syncSidebarWidthToStore(width)
            },
            onTrafficLightUpdate: { [weak self] isSidebarVisible in
                self?.updateTrafficLightVisibility(isSidebarVisible: isSidebarVisible)
            },
        )
    }

    private func syncSidebarWidthToStore(_ width: CGFloat) {
        let clampedWidth = max(
            FileManagerSidebarSync.sidebarMinWidth,
            min(FileManagerSidebarSync.sidebarMaxWidth, width),
        )
        guard abs(store.sidebar.sidebarWidth - clampedWidth) > 0.5 else { return }
        store.send(.sidebar(.view(.setSidebarWidth(clampedWidth))))
    }

    private func updateTrafficLightVisibility(isSidebarVisible: Bool) {
        guard let window = view.window else { return }
        FileManagerWindowCoordinator.applyTrafficLightVisibility(
            to: window,
            isSidebarVisible: isSidebarVisible,
        )
    }
}
