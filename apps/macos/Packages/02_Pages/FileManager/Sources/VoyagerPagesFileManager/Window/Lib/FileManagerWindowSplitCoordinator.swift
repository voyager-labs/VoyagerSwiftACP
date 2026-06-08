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
    private var isTrackingUserSidebarDividerResize = false

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
                layout: (
                    mainContainerLeading: mainContainerLeading,
                    contentVerticalMargin: Constants.contentVerticalMargin,
                ),
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
        defer {
            reconcileSidebarChromeWithActualLayout()
            isApplyingSidebarLayout = false
        }
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
        isTrackingUserSidebarDividerResize = false

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
        case 0: return 0
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

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedPosition }
        switch dividerIndex {
        case 0:
            return FileManagerSidebarSync.constrainedSidebarDividerPosition(proposedPosition: proposedPosition)
        default:
            return proposedPosition
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

    func splitViewWillResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === windowSplitView,
              let sidebarView = sidebarHosting?.view
        else { return }

        if isCurrentEventOnSidebarDivider(splitView: splitView, sidebarView: sidebarView) {
            isTrackingUserSidebarDividerResize = true
        }
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingSidebarLayout else { return }
        guard let splitView = notification.object as? NSSplitView,
              splitView === windowSplitView,
              let sidebarView = sidebarHosting?.view
        else { return }

        let isUserInitiatedCollapse = isCurrentEventOnSidebarDivider(
            splitView: splitView,
            sidebarView: sidebarView,
        ) || (
            isTrackingUserSidebarDividerResize
                && isCurrentSidebarMouseEvent(in: splitView)
        )
        defer {
            resetSidebarDividerTrackingIfNeeded()
        }

        let resizeDecision = sidebarSync.handleSplitViewResize(
            splitView: splitView,
            sidebarView: sidebarView,
            storeSidebarVisible: store.sidebar.sidebarVisible,
            isUserInitiatedCollapse: isUserInitiatedCollapse,
            syncWidthToStore: { [weak self] width in
                self?.syncSidebarWidthToStore(width)
            },
        )

        switch resizeDecision {
        case .none:
            break

        case .hideSidebar:
            syncSidebarVisibilityToStore(false)

        case let .showSidebar(width):
            syncSidebarVisibilityToStore(true)
            syncSidebarWidthToStore(width)

        case .restoreSidebar:
            applySidebarState(
                sidebarVisible: true,
                sidebarWidth: store.sidebar.sidebarWidth,
            )
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

    private func syncSidebarVisibilityToStore(_ isVisible: Bool) {
        guard store.sidebar.sidebarVisible != isVisible else { return }
        store.send(.sidebar(.view(.setSidebarVisible(isVisible))))
    }

    private func resetSidebarDividerTrackingIfNeeded() {
        guard isTrackingUserSidebarDividerResize else { return }

        guard let splitView = windowSplitView,
              isCurrentSidebarTrackingContinuation(in: splitView)
        else {
            isTrackingUserSidebarDividerResize = false
            return
        }
    }

    private func reconcileSidebarChromeWithActualLayout() {
        guard let splitView = windowSplitView,
              let sidebarView = sidebarHosting?.view,
              splitView.bounds.width > 0
        else { return }

        if store.sidebar.sidebarVisible,
           !FileManagerSidebarSync.isSidebarEffectivelyVisible(
               splitView: splitView,
               sidebarView: sidebarView,
           )
        {
            splitView.setPosition(store.sidebar.sidebarWidth, ofDividerAt: 0)
            splitView.adjustSubviews()
        }

        let isSidebarActuallyVisible = store.sidebar.sidebarVisible
            && FileManagerSidebarSync.isSidebarEffectivelyVisible(
                splitView: splitView,
                sidebarView: sidebarView,
            )
        updateTrafficLightVisibility(isSidebarVisible: isSidebarActuallyVisible)
    }

    private func updateTrafficLightVisibility(isSidebarVisible: Bool) {
        guard let window = view.window else { return }
        FileManagerWindowCoordinator.applyTrafficLightVisibility(
            to: window,
            isSidebarVisible: isSidebarVisible,
        )
    }
}

private func isCurrentEventOnSidebarDivider(
    splitView: NSSplitView,
    sidebarView: NSView,
) -> Bool {
    guard let event = NSApp.currentEvent,
          event.window === splitView.window
    else { return false }

    switch event.type {
    case .leftMouseDown,
         .leftMouseDragged,
         .leftMouseUp:
        break
    default:
        return false
    }

    let location = splitView.convert(event.locationInWindow, from: nil)
    let dividerX = sidebarView.frame.maxX
    let hitSlop = max(splitView.dividerThickness + 6, 12)
    return abs(location.x - dividerX) <= hitSlop
}

private func isCurrentSidebarMouseEvent(in splitView: NSSplitView) -> Bool {
    guard let event = NSApp.currentEvent,
          event.window === splitView.window
    else { return false }

    switch event.type {
    case .leftMouseDown,
         .leftMouseDragged,
         .leftMouseUp:
        return true
    default:
        return false
    }
}

private func isCurrentSidebarTrackingContinuation(in splitView: NSSplitView) -> Bool {
    guard let event = NSApp.currentEvent,
          event.window === splitView.window
    else { return false }

    switch event.type {
    case .leftMouseDown,
         .leftMouseDragged:
        return true
    default:
        return false
    }
}
