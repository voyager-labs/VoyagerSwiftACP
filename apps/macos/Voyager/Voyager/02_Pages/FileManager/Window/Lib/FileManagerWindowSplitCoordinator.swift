import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

@MainActor
final class FileManagerWindowSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let contentVerticalMargin: CGFloat = 4

        static let sidebarMinWidth: CGFloat = 150
        static let sidebarMaxWidth: CGFloat = 280
        static let sidebarCollapseThreshold: CGFloat = 2
    }

    private struct Constraints {
        var mainContainerLeading: NSLayoutConstraint?
    }

    let store: StoreOf<FileManagerFeature>
    let keyCommandFocusCoordinator = FileManagerKeyCommandFocusCoordinator()

    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasTornDown = false

    private var hasSetInitialLayout = false
    private var currentSidebarVisible: Bool?
    private var currentSidebarWidth: CGFloat
    private var currentIsDark: Bool

    private var sidebarHosting: NSHostingController<AnyView>?
    private var mainContainerHosting: NSHostingController<FileManagerWindowMainContainerView>?

    private weak var windowSplitView: NSSplitView?
    private weak var mainContainerView: NSView?

    private var constraints = Constraints()

    init(store: StoreOf<FileManagerFeature>, isDark: Bool) {
        self.store = store
        currentSidebarWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, store.sidebar.sidebarWidth),
        )
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
        constraints.mainContainerLeading = components.mainContainerLeading

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
        applyInitialLayoutIfNeeded(
            sidebarVisible: store.sidebar.sidebarVisible,
            sidebarWidth: store.sidebar.sidebarWidth,
        )
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
                self?.applySidebarState(
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

    private func applySidebarState(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        let clampedSidebarWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, sidebarWidth),
        )
        let sidebarWidthChanged = abs(currentSidebarWidth - clampedSidebarWidth) > 0.5
        currentSidebarWidth = clampedSidebarWidth

        applyInitialLayoutIfNeeded(sidebarVisible: sidebarVisible, sidebarWidth: clampedSidebarWidth)

        if currentSidebarVisible != sidebarVisible {
            updateSidebarVisibility(isVisible: sidebarVisible, sidebarWidth: clampedSidebarWidth)
        } else if sidebarVisible, sidebarWidthChanged {
            windowSplitView?.setPosition(clampedSidebarWidth, ofDividerAt: 0)
            windowSplitView?.adjustSubviews()
        }

        currentSidebarVisible = sidebarVisible
    }

    private func applyInitialLayoutIfNeeded(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        guard !hasSetInitialLayout,
              let splitView = windowSplitView,
              splitView.bounds.width > 0
        else { return }

        if sidebarVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: Constants.contentVerticalMargin,
            )
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: Constants.contentVerticalMargin,
            )
        }

        splitView.adjustSubviews()
        hasSetInitialLayout = true
    }

    private func updateSidebarVisibility(isVisible: Bool, sidebarWidth: CGFloat) {
        guard let splitView = windowSplitView,
              let sidebarView = sidebarHosting?.view,
              splitView.bounds.width > 0
        else { return }

        if isVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: Constants.contentVerticalMargin,
            )
        } else {
            let currentWidth = sidebarView.frame.width
            if currentWidth > Constants.sidebarCollapseThreshold {
                syncSidebarWidthToStore(currentWidth)
            }
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: Constants.contentVerticalMargin,
            )
        }

        mainContainerView?.layoutSubtreeIfNeeded()
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0: return Constants.sidebarMinWidth
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
        case 0: return Constants.sidebarMaxWidth
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
        guard let splitView = notification.object as? NSSplitView,
              splitView === windowSplitView
        else { return }
        syncSidebarVisibilityWithWidth()
    }

    private func syncSidebarVisibilityWithWidth() {
        guard hasSetInitialLayout,
              let sidebarView = sidebarHosting?.view,
              let splitView = windowSplitView
        else { return }

        let sidebarWidth = sidebarView.frame.width
        let isCollapsed = splitView.isSubviewCollapsed(sidebarView)

        if !isCollapsed, sidebarWidth > Constants.sidebarCollapseThreshold {
            syncSidebarWidthToStore(sidebarWidth)
        }

        let shouldBeVisible = !isCollapsed
        if store.sidebar.sidebarVisible != shouldBeVisible {
            store.send(.sidebar(.view(.setSidebarVisible(shouldBeVisible))))
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: shouldBeVisible,
                contentVerticalMargin: Constants.contentVerticalMargin,
            )
            mainContainerView?.layoutSubtreeIfNeeded()
        }
    }

    private func syncSidebarWidthToStore(_ width: CGFloat) {
        let clampedWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, width),
        )
        guard abs(store.sidebar.sidebarWidth - clampedWidth) > 0.5 else { return }
        store.send(.sidebar(.view(.setSidebarWidth(clampedWidth))))
    }
}
