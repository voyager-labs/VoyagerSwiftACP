import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

@MainActor
public final class FileManagerWindowSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let contentVerticalMargin: CGFloat = 4
    }

    private struct Constraints {
        var mainContainerLeading: NSLayoutConstraint?
    }

    public let store: StoreOf<FileManagerFeature>
    public let keyCommandFocusCoordinator = FileManagerKeyCommandFocusCoordinator()

    private var sidebarSync: FileManagerSidebarSync!
    private var hasTornDown = false

    private var currentIsDark: Bool

    private var sidebarHosting: NSHostingController<AnyView>?
    private var mainContainerHosting: NSHostingController<FileManagerWindowMainContainerView>?

    private weak var windowSplitView: NSSplitView?
    private weak var mainContainerView: NSView?

    private var constraints = Constraints()

    init(store: StoreOf<FileManagerFeature>, isDark: Bool) {
        self.store = store
        currentIsDark = isDark
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
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

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSidebarSync()
        sidebarSync.start(store: store)
        store.send(.onAppear)
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        applyInitialLayoutViaSync(
            sidebarVisible: store.sidebar.sidebarVisible,
            sidebarWidth: store.sidebar.sidebarWidth,
        )
    }

    public func updateAppearance(isDark: Bool) {
        currentIsDark = isDark
        FileManagerWindowSplitLayout.applySplitBackground(windowSplitView)
        mainContainerHosting?.rootView = makeMainContainerRootView()
    }

    public func tearDown() {
        guard !hasTornDown else { return }
        hasTornDown = true
        sidebarSync.tearDown()

        windowSplitView?.delegate = nil

        sidebarHosting?.removeFromParent()
        mainContainerHosting?.removeFromParent()

        sidebarHosting = nil
        mainContainerHosting = nil
        store.send(.onDisappear)
    }

    private func setupSidebarSync() {
        sidebarSync = FileManagerSidebarSync(
            initialSidebarWidth: store.sidebar.sidebarWidth,
            contentVerticalMargin: Constants.contentVerticalMargin,
        )
        sidebarSync.onApplyInitialLayout = { [weak self] sidebarVisible, sidebarWidth, margin in
            self?.applyInitialLayout(
                sidebarVisible: sidebarVisible,
                sidebarWidth: sidebarWidth,
                contentVerticalMargin: margin,
            )
        }
        sidebarSync.onToggleSidebar = { [weak self] isVisible, sidebarWidth, margin in
            self?.updateSidebarVisibility(
                isVisible: isVisible,
                sidebarWidth: sidebarWidth,
                contentVerticalMargin: margin,
            )
        }
        sidebarSync.onAdjustDivider = { [weak self] sidebarWidth in
            self?.windowSplitView?.setPosition(sidebarWidth, ofDividerAt: 0)
            self?.windowSplitView?.adjustSubviews()
        }
        sidebarSync.onUpdateTrafficLights = { [weak self] isSidebarVisible in
            guard let window = self?.view.window else { return }
            FileManagerWindowChrome.applyTrafficLightVisibility(
                to: window,
                isSidebarVisible: isSidebarVisible,
            )
        }
    }

    private func makeMainContainerRootView() -> FileManagerWindowMainContainerView {
        FileManagerWindowMainContainerView(
            store: store,
            isDark: currentIsDark,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
        )
    }

    private func applyInitialLayoutViaSync(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        guard !sidebarSync.hasSetInitialLayout,
              let splitView = windowSplitView,
              splitView.bounds.width > 0
        else { return }

        applyInitialLayout(
            sidebarVisible: sidebarVisible,
            sidebarWidth: sidebarWidth,
            contentVerticalMargin: Constants.contentVerticalMargin,
        )
    }

    private func applyInitialLayout(sidebarVisible: Bool, sidebarWidth: CGFloat, contentVerticalMargin: CGFloat) {
        guard let splitView = windowSplitView,
              splitView.bounds.width > 0
        else { return }

        if sidebarVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: contentVerticalMargin,
            )
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: contentVerticalMargin,
            )
        }

        splitView.adjustSubviews()
        sidebarSync.markInitialLayoutApplied(sidebarVisible: sidebarVisible, sidebarWidth: sidebarWidth)
    }

    private func updateSidebarVisibility(isVisible: Bool, sidebarWidth: CGFloat, contentVerticalMargin: CGFloat) {
        guard let splitView = windowSplitView,
              let sidebarView = sidebarHosting?.view,
              splitView.bounds.width > 0
        else { return }

        if isVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: contentVerticalMargin,
            )
        } else {
            let currentWidth = sidebarView.frame.width
            if currentWidth > sidebarSync.sidebarCollapseThreshold {
                sidebarSync.syncSidebarWidthToStore(currentWidth)
            }
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                constraints.mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: contentVerticalMargin,
            )
        }

        mainContainerView?.layoutSubtreeIfNeeded()
    }

    public func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0: return sidebarSync.sidebarMinWidth
        default: return proposedMinimumPosition
        }
    }

    public func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === windowSplitView else { return proposedMaximumPosition }
        switch dividerIndex {
        case 0: return sidebarSync.sidebarMaxWidth
        default: return proposedMaximumPosition
        }
    }

    public func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard splitView === windowSplitView,
              let index = splitView.arrangedSubviews.firstIndex(of: view)
        else { return false }
        return index == 1
    }

    public func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard splitView === windowSplitView,
              let index = splitView.arrangedSubviews.firstIndex(of: subview)
        else { return false }
        return index == 0
    }

    public func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === windowSplitView,
              let sidebarView = sidebarHosting?.view
        else { return }

        sidebarSync.handleSplitViewResize(
            sidebarViewFrame: sidebarView.frame,
            isCollapsed: splitView.isSubviewCollapsed(sidebarView),
            splitViewWidth: splitView.bounds.width,
        )
    }
}
