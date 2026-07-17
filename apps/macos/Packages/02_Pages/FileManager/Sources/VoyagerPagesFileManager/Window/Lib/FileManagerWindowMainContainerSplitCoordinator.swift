import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

struct FileManagerWindowMainContainerObservationInput: Equatable {
    let activeTabID: ContentTabID?
    let activePageAnchor: ContentTabPageAnchor
    let navigationState: ContentPageNavigationRoute
    let navigationTitlePath: String
    let backHistory: [ContentPageNavigationHistorySnapshot]
    let forwardHistory: [ContentPageNavigationHistorySnapshot]
    let isComposerPresented: Bool
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
    let inspectorMount: InspectorMountViewState
    let inspectorWidth: CGFloat

    init(state: FileManagerWindowState) {
        activeTabID = state.contentTabs.activeTabID
        activePageAnchor = ContentTabProjection.activePageAnchor(from: state.contentTabs) ?? .homeDefault
        navigationState = state.content.navigation.navigationState
        navigationTitlePath = state.content.navigation.titlePath
        backHistory = state.content.navigation.backHistory
        forwardHistory = state.content.navigation.forwardHistory
        isComposerPresented = state.content.composer.isPresented
        isDiscardEnabled = state.content.isCollectionMode
            && state.content.collection.collectionSession.metadata.baseline != nil
            && state.content.isOpenedCollectionDirty
        canSaveCollection = state.content.canSaveCollection
        isTemporaryCollection = !state.content.openedCollectionURLExists
        inspectorMount = InspectorMountViewState(state: state)
        inspectorWidth = state.inspector.inspectorWidth
    }
}

@MainActor
final class MainContainerSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let inspectorMinWidth = FileManagerInspectorLayoutMetrics.minWidth
        static let contentMinWidth: CGFloat = 400
    }

    let store: StoreOf<FileManagerFeature>
    let keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator

    @Dependency(\.fileManagerClient)
    private var fileManagerClient

    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasTornDown = false
    private var currentInspectorVisible: Bool?
    private var currentIsDark: Bool
    private var currentContentChromeProps: FileManagerContentChromeProps?
    private var currentContentOverlayProps: FileManagerContentOverlayProps?
    private var pendingInspectorMountRetry = false
    private var isApplyingInspectorWidth = false
    private var inspectorHosting: NSHostingController<InspectorPaneView>?
    private var contentHosting: NSHostingController<AnyView>?
    private weak var mainSplitView: NSSplitView?
    private weak var containerView: NSView?

    init(
        store: StoreOf<FileManagerFeature>,
        isDark: Bool,
        keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator,
    ) {
        self.store = store
        currentIsDark = isDark
        self.keyCommandFocusCoordinator = keyCommandFocusCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let chromeProps = FileManagerContentChromePropsBuilder.makeContentChromeProps(
            from: store.state, contentTabState: store.state.contentTabs, fileManagerClient: fileManagerClient,
        )
        let overlayProps = FileManagerContentChromePropsBuilder.makeContentOverlayProps(
            from: store.state,
            fileManagerClient: fileManagerClient,
        )
        currentContentChromeProps = chromeProps
        currentContentOverlayProps = overlayProps

        let components = FileManagerWindowMainContainerLayout.build(
            contentRootView: makeContentRootView(
                chromeProps: chromeProps,
                overlayProps: overlayProps,
                activePageAnchor: chromeProps.activePageAnchor,
            ),
        )
        components.splitView.delegate = self

        mainSplitView = components.splitView
        containerView = components.containerView
        contentHosting = components.contentHosting

        addChild(components.contentHosting)
        let inspectorHosting = FileManagerWindowMainContainerLayout.makeInspectorHosting(
            store: store.scope(state: \.inspector, action: \.inspector),
            isDark: currentIsDark,
        )
        self.inspectorHosting = inspectorHosting
        components.splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        addChild(inspectorHosting)
        view = components.containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        retryPendingInspectorMountIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        retryPendingInspectorMountIfNeeded()
    }

    func updateAppearance(isDark: Bool) {
        currentIsDark = isDark
        FileManagerWindowMainContainerLayout.applyAppearance(
            splitView: mainSplitView,
            containerView: containerView,
            contentView: contentHosting?.view,
            inspectorView: inspectorHosting?.view,
            isDark: currentIsDark,
        )
    }

    func tearDown() {
        guard !hasTornDown else { return }
        hasTornDown = true
        cancellables.removeAll()
        mainSplitView?.delegate = nil

        inspectorHosting?.removeFromParent()
        contentHosting?.removeFromParent()
        inspectorHosting = nil
        contentHosting = nil
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        observeStore()
        render(state: store.state)
    }

    private func observeStore() {
        store.publisher
            .map(FileManagerWindowMainContainerObservationInput.init)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                render(state: store.state)
            }
            .store(in: &cancellables)
    }

    private func render(state: FileManagerWindowState) {
        updateContentRootViewIfNeeded(state: state)
        applyInspectorVisibilityIfNeeded(
            inspectorVisible: state.inspector.inspectorVisible,
            inspectorWidth: state.inspector.inspectorWidth,
        )
        updateAppearance(isDark: currentIsDark)
    }

    private func updateContentRootViewIfNeeded(state: FileManagerWindowState) {
        let chromeProps = FileManagerContentChromePropsBuilder.makeContentChromeProps(
            from: state, contentTabState: state.contentTabs, fileManagerClient: fileManagerClient,
        )
        let overlayProps = FileManagerContentChromePropsBuilder.makeContentOverlayProps(
            from: state,
            fileManagerClient: fileManagerClient,
        )
        guard chromeProps != currentContentChromeProps || overlayProps != currentContentOverlayProps else {
            return
        }
        currentContentChromeProps = chromeProps
        currentContentOverlayProps = overlayProps
        contentHosting?.rootView = makeContentRootView(
            chromeProps: chromeProps,
            overlayProps: overlayProps,
            activePageAnchor: chromeProps.activePageAnchor,
        )
    }

    private func makeContentRootView(
        chromeProps: FileManagerContentChromeProps,
        overlayProps: FileManagerContentOverlayProps,
        activePageAnchor: ContentTabPageAnchor = .homeDefault,
    ) -> AnyView {
        AnyView(
            FileManagerContentPaneView(
                store: store.scope(state: \.content, action: \.content),
                chromeProps: chromeProps,
                overlayProps: overlayProps,
                activePageAnchor: activePageAnchor,
                onNavigationAction: { [weak self] action in
                    self?.store.send(.navigation(.view(action)))
                },
                onNavigate: { [weak self] path in
                    self?.store.send(.navigation(.view(.navigateToPath(path))))
                },
            )
            .id(chromeProps.renderIdentity)
            .environment(\.fileManagerKeyCommandFocusCoordinator, keyCommandFocusCoordinator),
        )
    }

    private func applyInspectorVisibilityIfNeeded(inspectorVisible: Bool, inspectorWidth: CGFloat) {
        let needsMountRetry = inspectorVisible && !isInspectorPaneMounted
        if currentInspectorVisible != inspectorVisible || needsMountRetry {
            updateInspectorPane(visible: inspectorVisible, inspectorWidth: inspectorWidth)
        }
        currentInspectorVisible = inspectorVisible
    }

    private func updateInspectorPane(visible: Bool, inspectorWidth: CGFloat) {
        guard let splitView = mainSplitView else { return }
        if visible {
            mountInspectorPane(in: splitView, inspectorWidth: inspectorWidth)
            return
        }
        unmountInspectorPane(from: splitView)
    }

    private func mountInspectorPane(in splitView: NSSplitView, inspectorWidth: CGFloat) {
        guard let hosting = inspectorHosting else { return }
        guard canMountInspectorPane(in: splitView) else {
            scheduleInspectorMountRetry()
            return
        }

        if !splitView.arrangedSubviews.contains(hosting.view) {
            if hosting.view.superview != nil {
                hosting.view.removeFromSuperview()
            }
            splitView.addArrangedSubview(hosting.view)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        }

        applyStoredInspectorWidth(inspectorWidth, in: splitView)
        splitView.layoutSubtreeIfNeeded()
        guard isInspectorPaneEffectivelyVisible else {
            scheduleInspectorMountRetry()
            return
        }
        store.send(.inspector(.setInspectorPaneExists(true)))
    }

    private func unmountInspectorPane(from splitView: NSSplitView) {
        guard let hosting = inspectorHosting else { return }
        updateInspectorWidthFromSplitView()
        pendingInspectorMountRetry = false

        if hosting.view.superview === splitView {
            splitView.removeArrangedSubview(hosting.view)
            hosting.view.removeFromSuperview()
        }
        splitView.adjustSubviews()
        splitView.layoutSubtreeIfNeeded()
        store.send(.inspector(.setInspectorPaneExists(false)))
    }

    private func applyStoredInspectorWidth(_ width: CGFloat, in splitView: NSSplitView) {
        guard !isApplyingInspectorWidth else { return }
        isApplyingInspectorWidth = true
        defer { isApplyingInspectorWidth = false }

        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return }

        let targetWidth = targetInspectorWidth(width, totalWidth: totalWidth)
        let contentMinWidth = min(Constants.contentMinWidth, max(0, totalWidth - Constants.inspectorMinWidth))
        let dividerPosition = max(contentMinWidth, totalWidth - targetWidth)
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
        splitView.adjustSubviews()
    }

    private func targetInspectorWidth(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let contentWidth = min(Constants.contentMinWidth, max(0, totalWidth - Constants.inspectorMinWidth))
        let maxWidth = max(Constants.inspectorMinWidth, totalWidth - contentWidth)
        return min(max(Constants.inspectorMinWidth, width), maxWidth)
    }

    private func updateInspectorWidthFromSplitView() {
        guard currentInspectorVisible == true,
              let splitView = mainSplitView,
              let inspectorView = inspectorHosting?.view,
              splitView.arrangedSubviews.contains(inspectorView)
        else { return }

        let width = inspectorView.frame.width
        guard width > 0 else { return }
        syncInspectorWidthToStore(width)
    }

    private func syncInspectorWidthToStore(_ width: CGFloat) {
        let clampedWidth = max(Constants.inspectorMinWidth, width)
        guard abs(store.inspector.inspectorWidth - clampedWidth) > 0.5 else { return }
        store.send(.inspector(.setInspectorWidth(clampedWidth)))
    }

    private var isInspectorPaneMounted: Bool {
        guard let splitView = mainSplitView,
              let inspectorView = inspectorHosting?.view
        else { return false }
        return splitView.arrangedSubviews.contains(inspectorView)
    }

    private var isInspectorPaneEffectivelyVisible: Bool {
        guard isInspectorPaneMounted,
              let inspectorView = inspectorHosting?.view
        else { return false }
        return inspectorView.frame.width >= Constants.inspectorMinWidth
    }

    private func retryPendingInspectorMountIfNeeded() {
        guard currentInspectorVisible == true else { return }
        guard let splitView = mainSplitView,
              canMountInspectorPane(in: splitView)
        else {
            scheduleInspectorMountRetry()
            return
        }

        if isInspectorPaneMounted {
            applyStoredInspectorWidth(store.inspector.inspectorWidth, in: splitView)
            splitView.layoutSubtreeIfNeeded()
            guard isInspectorPaneEffectivelyVisible else {
                scheduleInspectorMountRetry()
                return
            }
            store.send(.inspector(.setInspectorPaneExists(true)))
            return
        }

        mountInspectorPane(in: splitView, inspectorWidth: store.inspector.inspectorWidth)
    }

    private func scheduleInspectorMountRetry() {
        guard !pendingInspectorMountRetry else { return }
        pendingInspectorMountRetry = true

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            guard let self else { return }
            pendingInspectorMountRetry = false
            retryPendingInspectorMountIfNeeded()
        }
    }

    private func canMountInspectorPane(in splitView: NSSplitView) -> Bool {
        splitView.bounds.width >= Constants.inspectorMinWidth + splitView.dividerThickness
    }
}

extension MainContainerSplitCoordinator {
    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === mainSplitView else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0: return max(proposedMinimumPosition, Constants.contentMinWidth)
        default: return proposedMinimumPosition
        }
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === mainSplitView else { return proposedMaximumPosition }
        switch dividerIndex {
        case 0:
            guard currentInspectorVisible == true,
                  let inspectorView = inspectorHosting?.view,
                  splitView.arrangedSubviews.contains(inspectorView)
            else {
                return proposedMaximumPosition
            }
            let maxPosition = splitView.bounds.width - Constants.inspectorMinWidth
            return min(proposedMaximumPosition, maxPosition)
        default:
            return proposedMaximumPosition
        }
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard splitView === mainSplitView,
              let index = splitView.arrangedSubviews.firstIndex(of: view)
        else { return false }
        return index == 0
    }

    func splitView(_: NSSplitView, canCollapseSubview _: NSView) -> Bool {
        false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === mainSplitView
        else { return }
        guard !isApplyingInspectorWidth else { return }
        updateInspectorWidthFromSplitView()
    }
}
