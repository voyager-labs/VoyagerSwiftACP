import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

import VoyagerFeaturesEntryOperations

private struct InspectorMountViewState: Equatable {
    let inspectorVisible: Bool
    let inspectorPaneExists: Bool
    let activeMode: FileManagerInspectorMode

    init(state: FileManagerWindowState) {
        inspectorVisible = state.inspector.inspectorVisible
        inspectorPaneExists = state.inspector.inspectorPaneExists
        activeMode = state.inspector.activeMode
    }
}

@MainActor
final class MainContainerSplitCoordinator: NSViewController, NSSplitViewDelegate {
    private enum Constants {
        static let defaultInspectorWidth: CGFloat = 300
        static let inspectorMinWidth: CGFloat = 200
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
    private var inspectorWidth: CGFloat = Constants.defaultInspectorWidth
    private var currentIsDark: Bool
    // TODO(VOY-202 후속): ContentPane/Toolbar/Breadcrumb/Composer 책임선을
    // 더 좁은 장기 구조로 다시 정리하면, 이 임시 chrome/overlay props는
    // 삭제한다. 현재는 의존성/결합 정리를 위한 과도기 seam이다.
    private var currentContentChromeProps: FileManagerContentChromeProps?
    private var currentContentOverlayProps: FileManagerContentOverlayProps?
    private var needsInspectorWidthApply = false
    private var pendingInspectorWidthApply = false
    private var isApplyingInspectorWidth = false

    private var inspectorHosting: NSHostingController<InspectorPaneView>?
    private var contentHosting: NSHostingController<AnyView>?
    private var inspectorWidthConstraint: NSLayoutConstraint?
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
        let inspectorHosting = FileManagerWindowMainContainerLayout.makeInspectorHosting(
            store: store.scope(state: \.inspector, action: \.inspector),
            isDark: currentIsDark,
        )
        self.inspectorHosting = inspectorHosting
        setInspectorWidthConstraint(to: 0)
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
        inspectorWidthConstraint = nil
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
            store.publisher.map(InspectorMountViewState.init).removeDuplicates(),
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
}

private extension MainContainerSplitCoordinator {
    func updateContentRootViewIfNeeded(state: FileManagerWindowState) {
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
        let needsMountRetry = inspectorVisible && !isInspectorPaneMounted
        if currentInspectorVisible != inspectorVisible || needsMountRetry {
            updateInspectorPane(visible: inspectorVisible)
        }
        currentInspectorVisible = inspectorVisible
    }

    private func updateInspectorPane(visible: Bool) {
        guard let splitView = mainSplitView else { return }

        if visible {
            guard let hosting = inspectorHosting else { return }

            guard canMountInspectorPane(in: splitView) else {
                needsInspectorWidthApply = true
                scheduleInspectorWidthApplyIfNeeded()
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
            setInspectorWidthConstraint(to: inspectorWidth)

            needsInspectorWidthApply = true
            applyInspectorWidthIfNeeded()
            splitView.layoutSubtreeIfNeeded()
            guard isInspectorPaneEffectivelyVisible else {
                needsInspectorWidthApply = true
                scheduleInspectorMountRetry()
                return
            }
            if needsInspectorWidthApply {
                scheduleInspectorWidthApplyIfNeeded()
            }

            store.send(.inspector(.setInspectorPaneExists(true)))
            return
        }

        guard let hosting = inspectorHosting else { return }
        updateInspectorWidthFromSplitView()
        setInspectorWidthConstraint(to: 0)
        needsInspectorWidthApply = false
        pendingInspectorWidthApply = false
        if hosting.view.superview === splitView {
            splitView.removeArrangedSubview(hosting.view)
            hosting.view.removeFromSuperview()
        }
        splitView.adjustSubviews()
        splitView.layoutSubtreeIfNeeded()

        store.send(.inspector(.setInspectorPaneExists(false)))
    }

    private func applyInspectorWidthIfNeeded() {
        guard let splitView = mainSplitView,
              let inspectorView = inspectorHosting?.view
        else { return }

        guard !isApplyingInspectorWidth else { return }
        isApplyingInspectorWidth = true
        defer { isApplyingInspectorWidth = false }

        let totalWidth = splitView.bounds.width
        guard totalWidth > 0 else { return }

        let contentMinWidth = min(
            Constants.contentMinWidth,
            max(0, totalWidth - Constants.inspectorMinWidth),
        )
        let maxDividerPosition = max(0, totalWidth - Constants.inspectorMinWidth)
        let targetInspectorWidth = min(
            max(inspectorWidth, Constants.defaultInspectorWidth, Constants.inspectorMinWidth),
            max(Constants.inspectorMinWidth, totalWidth - contentMinWidth),
        )
        let dividerPosition = min(
            max(contentMinWidth, totalWidth - targetInspectorWidth),
            maxDividerPosition,
        )
        setInspectorWidthConstraint(to: targetInspectorWidth)
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
        splitView.adjustSubviews()
        inspectorWidth = max(targetInspectorWidth, inspectorView.frame.width)
        needsInspectorWidthApply = false
        pendingInspectorWidthApply = false
    }

    private func setInspectorWidthConstraint(to width: CGFloat) {
        guard let inspectorView = inspectorHosting?.view else { return }
        let resolvedWidth = max(0, width)

        if let inspectorWidthConstraint {
            inspectorWidthConstraint.constant = resolvedWidth
            return
        }

        let constraint = inspectorView.widthAnchor.constraint(equalToConstant: resolvedWidth)
        constraint.priority = .required
        constraint.isActive = true
        inspectorWidthConstraint = constraint
    }

    private func scheduleInspectorWidthApplyIfNeeded() {
        guard mainSplitView != nil else { return }

        guard !pendingInspectorWidthApply else { return }
        pendingInspectorWidthApply = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard pendingInspectorWidthApply,
                  currentInspectorVisible == true,
                  inspectorHosting != nil,
                  mainSplitView != nil
            else {
                pendingInspectorWidthApply = false
                return
            }

            guard let splitView = mainSplitView,
                  canMountInspectorPane(in: splitView)
            else {
                pendingInspectorWidthApply = false
                needsInspectorWidthApply = true
                scheduleInspectorMountRetry()
                return
            }

            pendingInspectorWidthApply = false
            if let inspectorView = inspectorHosting?.view,
               !splitView.arrangedSubviews.contains(inspectorView)
            {
                updateInspectorPane(visible: true)
            } else {
                applyInspectorWidthIfNeeded()
                splitView.layoutSubtreeIfNeeded()
                markInspectorPaneExistsIfEffectivelyVisible()
            }
        }
    }

    private func updateInspectorWidthFromSplitView() {
        guard let inspectorView = inspectorHosting?.view else { return }
        let width = inspectorView.frame.width
        guard width > 0 else { return }
        inspectorWidth = width
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

    private func markInspectorPaneExistsIfEffectivelyVisible() {
        guard isInspectorPaneEffectivelyVisible,
              store.state.inspector.inspectorPaneExists == false
        else { return }
        store.send(.inspector(.setInspectorPaneExists(true)))
    }

    private func retryPendingInspectorMountIfNeeded() {
        guard currentInspectorVisible == true else { return }

        if isInspectorPaneMounted {
            if needsInspectorWidthApply {
                scheduleInspectorWidthApplyIfNeeded()
                return
            }
            markInspectorPaneExistsIfEffectivelyVisible()
            return
        }

        guard let splitView = mainSplitView,
              canMountInspectorPane(in: splitView)
        else {
            needsInspectorWidthApply = true
            scheduleInspectorMountRetry()
            return
        }

        updateInspectorPane(visible: true)
    }

    private func scheduleInspectorMountRetry() {
        guard !pendingInspectorWidthApply else { return }
        pendingInspectorWidthApply = true

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            guard let self else { return }
            pendingInspectorWidthApply = false
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

    func splitView(
        _ splitView: NSSplitView,
        shouldCollapseSubview subview: NSView,
        forDoubleClickOnDividerAt dividerIndex: Int,
    ) -> Bool {
        guard splitView === mainSplitView,
              dividerIndex == 0,
              subview === inspectorHosting?.view
        else { return false }
        return false
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview _: NSView) -> Bool {
        guard splitView === mainSplitView else { return false }
        return false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === mainSplitView
        else { return }
        if needsInspectorWidthApply || pendingInspectorWidthApply {
            scheduleInspectorWidthApplyIfNeeded()
        }
        updateInspectorWidthFromSplitView()
    }
}
