import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

@MainActor
final class MainContainerSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let defaultInspectorWidth: CGFloat = 300
        static let inspectorMinWidth: CGFloat = 200
        static let inspectorRightReservedWidth: CGFloat = 400
    }

    let store: StoreOf<FileManagerFeature>

    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasTornDown = false

    private var currentInspectorVisible: Bool?
    private var inspectorWidth: CGFloat = Constants.defaultInspectorWidth
    private var currentIsDark: Bool
    private var currentContentPaneState: FileManagerContentPaneViewState?
    private var needsInspectorWidthApply = false

    private var inspectorHosting: NSHostingController<InspectorPaneView>?
    private var contentHosting: NSHostingController<FileManagerContentPaneView>?
    private weak var mainSplitView: NSSplitView?
    private weak var containerView: NSView?

    init(store: StoreOf<FileManagerFeature>, isDark: Bool) {
        self.store = store
        currentIsDark = isDark
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let paneState = makeContentPaneViewState(from: store.state)
        currentContentPaneState = paneState

        let components = FileManagerWindowMainContainerLayout.build(
            contentRootView: makeContentRootView(paneState: paneState),
        )
        components.splitView.delegate = self

        mainSplitView = components.splitView
        containerView = components.containerView
        contentHosting = components.contentHosting

        addChild(components.contentHosting)
        view = components.containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if needsInspectorWidthApply {
            applyInspectorWidthIfNeeded()
        }
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
        Publishers.CombineLatest3(
            store.publisher.map(\.sidebar).removeDuplicates(),
            store.publisher.map(\.content),
            store.publisher.map(\.inspector).removeDuplicates(),
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self else { return }
            render(state: store.state)
        }
        .store(in: &cancellables)
    }

    private func render(state: FileManagerWindowState) {
        updateContentRootViewIfNeeded(state: state)
        applyInspectorState(inspectorVisible: state.inspector.inspectorVisible)
        updateAppearance(isDark: currentIsDark)
    }

    private func updateContentRootViewIfNeeded(state: FileManagerWindowState) {
        let paneState = makeContentPaneViewState(from: state)
        guard paneState != currentContentPaneState else { return }
        currentContentPaneState = paneState
        contentHosting?.rootView = makeContentRootView(paneState: paneState)
    }

    private func makeContentPaneViewState(from state: FileManagerWindowState) -> FileManagerContentPaneViewState {
        FileManagerContentPaneViewState(
            isComposerPresented: state.content.composer.isPresented,
            favorites: state.sidebar.favorites.map { favorite in
                ScopeFavoriteItem(
                    name: favorite.name,
                    url: favorite.url,
                    iconName: favorite.iconName,
                )
            },
            historyPaths: state.content.navigation.backHistory.compactMap { entry in
                if case let .folder(path) = entry.navigationState {
                    return path
                }
                return nil
            },
            isDiscardEnabled: state.content.entryOperations.loadingContext.isCollectionMode
                && state.content.collectionSession.baseline != nil
                && state.content.isOpenedCollectionDirty,
            canSaveCollection: state.content.canSaveCollection,
            isTemporaryCollection: state.content.collectionSession.openedURL == nil,
        )
    }

    private func makeContentRootView(paneState: FileManagerContentPaneViewState) -> FileManagerContentPaneView {
        FileManagerContentPaneView(
            store: store.scope(state: \.content, action: \.content),
            paneState: paneState,
            onNavigationAction: { [weak self] action in
                self?.store.send(.navigation(.view(action)))
            },
            onNavigate: { [weak self] path in
                self?.store.send(.navigation(.view(.navigateToPath(path))))
            },
        )
    }

    private func applyInspectorState(inspectorVisible: Bool) {
        if currentInspectorVisible != inspectorVisible {
            updateInspectorPane(visible: inspectorVisible)
        }
        currentInspectorVisible = inspectorVisible
    }

    private func updateInspectorPane(visible: Bool) {
        guard let splitView = mainSplitView else { return }

        if visible {
            guard inspectorHosting == nil else { return }
            let hosting = FileManagerWindowMainContainerLayout.makeInspectorHosting(
                store: store,
                isDark: currentIsDark,
            )
            inspectorHosting = hosting

            splitView.addArrangedSubview(hosting.view)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
            addChild(hosting)

            needsInspectorWidthApply = true
            applyInspectorWidthIfNeeded()

            store.send(.inspector(.setInspectorPaneExists(true)))
            return
        }

        guard let hosting = inspectorHosting else { return }
        updateInspectorWidthFromSplitView()
        splitView.removeArrangedSubview(hosting.view)
        hosting.view.removeFromSuperview()
        hosting.removeFromParent()
        inspectorHosting = nil
        needsInspectorWidthApply = false
        splitView.adjustSubviews()

        store.send(.inspector(.setInspectorPaneExists(false)))
    }

    private func applyInspectorWidthIfNeeded() {
        guard let splitView = mainSplitView,
              let inspectorView = inspectorHosting?.view
        else { return }

        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return }

        let dividerPosition = max(
            Constants.inspectorRightReservedWidth,
            totalWidth - inspectorWidth,
        )
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
        inspectorWidth = inspectorView.frame.width
        needsInspectorWidthApply = false
    }

    private func updateInspectorWidthFromSplitView() {
        guard let inspectorView = inspectorHosting?.view else { return }
        inspectorWidth = inspectorView.frame.width
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        guard splitView === mainSplitView else { return proposedMinimumPosition }
        switch dividerIndex {
        case 0: return max(proposedMinimumPosition, Constants.inspectorRightReservedWidth)
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

    func splitView(_ splitView: NSSplitView, canCollapseSubview _: NSView) -> Bool {
        guard splitView === mainSplitView else { return false }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === mainSplitView
        else { return }
        updateInspectorWidthFromSplitView()
    }
}
