import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesCollection
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared

@MainActor
final class MainContainerSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let defaultInspectorWidth: CGFloat = 300
        static let inspectorMinWidth: CGFloat = 200
        static let inspectorRightReservedWidth: CGFloat = 400
    }

    let store: StoreOf<FileManagerFeature>
    let keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator

    @Dependency(\.fileManagerClient)
    private var fileManagerClient

    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var hasTornDown = false

    private var currentInspectorVisible: Bool?
    private var inspectorWidth: CGFloat = Constants.defaultInspectorWidth
    private var currentIsDark: Bool
    // TODO(VOY-202 후속): ContentPane/Toolbar/Breadcrumb/Composer 책임선을
    // 더 좁은 장기 구조로 다시 정리하면, 이 임시 chrome/overlay props는
    // 삭제한다. 현재는 의존성/결합 정리를 위한 과도기 seam이다.
    private var currentContentChromeProps: FileManagerContentChromeProps?
    private var currentContentOverlayProps: FileManagerContentOverlayProps?
    private var needsInspectorWidthApply = false

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
        let chromeProps = makeContentChromeProps(from: store.state, fileManagerClient: fileManagerClient)
        let overlayProps = makeContentOverlayProps(from: store.state)
        currentContentChromeProps = chromeProps
        currentContentOverlayProps = overlayProps

        let components = FileManagerWindowMainContainerLayout.build(
            contentRootView: makeContentRootView(
                chromeProps: chromeProps,
                overlayProps: overlayProps,
            ),
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
        let chromeProps = makeContentChromeProps(from: state, fileManagerClient: fileManagerClient)
        let overlayProps = makeContentOverlayProps(from: state)
        guard chromeProps != currentContentChromeProps || overlayProps != currentContentOverlayProps else {
            return
        }
        currentContentChromeProps = chromeProps
        currentContentOverlayProps = overlayProps
        contentHosting?.rootView = makeContentRootView(
            chromeProps: chromeProps,
            overlayProps: overlayProps,
        )
    }

    private func makeContentRootView(
        chromeProps: FileManagerContentChromeProps,
        overlayProps: FileManagerContentOverlayProps,
    ) -> AnyView {
        AnyView(
            FileManagerContentPaneView(
                store: store.scope(state: \.content, action: \.content),
                chromeProps: chromeProps,
                overlayProps: overlayProps,
                onNavigationAction: { [weak self] action in
                    self?.store.send(.navigation(.view(action)))
                },
                onNavigate: { [weak self] path in
                    self?.store.send(.navigation(.view(.navigateToPath(path))))
                },
            )
            .environment(\.fileManagerKeyCommandFocusCoordinator, keyCommandFocusCoordinator),
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
                store: store.scope(state: \.inspector, action: \.inspector),
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

private func makeContentChromeProps(
    from state: FileManagerWindowState,
    fileManagerClient: FileManagerClient,
) -> FileManagerContentChromeProps {
    let computerName = fileManagerClient.displayName("/")
    let trashPath = fileManagerClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
    let breadcrumbRoots = FileManagerBreadcrumbRoots(
        homePath: NSHomeDirectory(),
        trashPath: trashPath,
    )
    let specialDirectoryIconNames = makeSpecialDirectoryIconNames(fileManagerClient: fileManagerClient)

    return FileManagerContentChromeProps(
        computerName: computerName,
        breadcrumbRoots: breadcrumbRoots,
        pathDisplayNames: makePathDisplayNames(
            contentState: state.content,
            fileManagerClient: fileManagerClient,
            computerName: computerName,
            roots: breadcrumbRoots,
        ),
        specialDirectoryIconNames: specialDirectoryIconNames,
    )
}

private func makeContentOverlayProps(from state: FileManagerWindowState) -> FileManagerContentOverlayProps {
    FileManagerContentOverlayProps(
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
        isDiscardEnabled: state.content.isCollectionMode
            && state.content.collection.collectionSession.metadata.baseline != nil
            && state.content.isOpenedCollectionDirty,
        canSaveCollection: state.content.canSaveCollection,
        isTemporaryCollection: state.content.collection.collectionSession.document?.url == nil,
    )
}

private func makeSpecialDirectoryIconNames(fileManagerClient: FileManagerClient) -> [String: String] {
    var result: [String: String] = [:]
    for mapping in FileManagerSpecialDirectoryIconConfig.specialDirectoryIconMappings {
        if let path = fileManagerClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path {
            result[path] = mapping.iconSystemName
        }
    }
    return result
}

private func makePathDisplayNames(
    contentState: FileManagerContentState,
    fileManagerClient: FileManagerClient,
    computerName: String,
    roots: FileManagerBreadcrumbRoots,
) -> [String: String] {
    var paths = Set<String>()

    paths.formUnion(
        BreadcrumbBuilder.breadcrumbPaths(
            navigationState: contentState.navigation.navigationState,
            roots: roots,
        ),
    )

    if contentState.navigation.titlePath.hasPrefix("/") {
        paths.insert(contentState.navigation.titlePath)
    }

    for history in contentState.navigation.backHistory + contentState.navigation.forwardHistory {
        switch history.navigationState {
        case let .folder(path):
            paths.insert(path)
        case .computer:
            paths.insert("/")
        case .recents, .tags, .collection:
            break
        }
    }

    if !computerName.isEmpty {
        paths.insert("/")
    }

    var result: [String: String] = [:]
    for path in paths {
        result[path] = fileManagerClient.displayName(path)
    }
    return result
}
