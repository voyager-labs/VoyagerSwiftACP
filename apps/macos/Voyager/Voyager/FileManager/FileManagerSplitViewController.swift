// swiftlint:disable file_length
import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

class AppearanceAwareSplitView: NSSplitView {
    var onAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
        onAppearanceChanged?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundColor()
    }

    func updateBackgroundColor() {
        wantsLayer = true
        // 투명하게 설정 (뒤의 블러가 보이도록)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

class FileManagerSplitViewController: NSViewController, NSSplitViewDelegate {
    private struct ContentPaneViewState: Equatable {
        let isComposerPresented: Bool
    }

    let store: StoreOf<FileManagerFeature>
    let initialPath: String?
    private var hasSetInitialLayout = false
    private var inspectorHosting: NSViewController?
    private var observationTask: Task<Void, Never>?
    private var sidebarHosting: NSViewController?

    private var contentInspectorContainer: NSView?
    private var contentHosting: NSViewController?
    private var contentInspectorDivider: ContentInspectorDivider?
    private var mainSplitView: NSSplitView?
    private var inspectorWidth: CGFloat = 300
    private let contentVerticalMargin: CGFloat = 4
    private var contentLeadingConstraint: NSLayoutConstraint?
    private var containerLeadingConstraint: NSLayoutConstraint?
    private var contentTrailingConstraint: NSLayoutConstraint?
    private var contentTopConstraint: NSLayoutConstraint?
    private var contentBottomConstraint: NSLayoutConstraint?
    private var inspectorTrailingConstraint: NSLayoutConstraint?
    private var inspectorTopConstraint: NSLayoutConstraint?
    private var inspectorBottomConstraint: NSLayoutConstraint?
    private var inspectorWidthConstraint: NSLayoutConstraint?
    private var dividerLeadingConstraint: NSLayoutConstraint?
    private var dividerTopConstraint: NSLayoutConstraint?
    private var dividerBottomConstraint: NSLayoutConstraint?

    init(store: StoreOf<FileManagerFeature>, initialPath: String? = nil) {
        self.store = store
        self.initialPath = initialPath
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        observationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        // 전체 창을 감싸는 NSVisualEffectView
        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .sidebar
        backgroundEffect.blendingMode = .behindWindow
        backgroundEffect.state = .active
        backgroundEffect.wantsLayer = true

        let mainSplit = createMainSplitView()
        mainSplitView = mainSplit
        setupSidebar(in: mainSplit)
        setupContentContainer(in: mainSplit)

        // Split view를 블러 배경 위에 배치
        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffect.addSubview(mainSplit)
        NSLayoutConstraint.activate([
            mainSplit.topAnchor.constraint(equalTo: backgroundEffect.topAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: backgroundEffect.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: backgroundEffect.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: backgroundEffect.trailingAnchor),
        ])

        view = backgroundEffect
    }

    private func updateContentInspectorLayout() {
        guard let container = contentInspectorContainer,
              let contentView = contentHosting?.view else { return }

        if let inspectorView = inspectorHosting?.view {
            setupLayoutWithInspector(container: container, contentView: contentView, inspectorView: inspectorView)
        } else {
            setupLayoutWithoutInspector(container: container, contentView: contentView)
        }

        container.layoutSubtreeIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let mainSplit = mainSplitView as? AppearanceAwareSplitView {
            mainSplit.updateBackgroundColor()
        }

        store.send(.loadFavorites)
        store.send(.loadLocations)
        store.send(.loadTags)

        if let path = initialPath {
            store.send(.navigateTo(path))
        } else {
            store.send(.onAppear)
        }

        store.send(.fsItems(.onAppear))

        observeInspectorState()
        observeSidebarState()
    }

    private func observeInspectorState() {
        observationTask = Task { @MainActor in
            for await inspectorVisible in store.publisher.inspectorVisible.values {
                updateInspectorPane(visible: inspectorVisible)
            }
        }
    }

    private func observeSidebarState() {
        Task { @MainActor in
            for await sidebarVisible in store.publisher.sidebarVisible.values {
                guard let mainSplitView,
                      let sidebarView = sidebarHosting?.view else { continue }

                if sidebarVisible {
                    let savedWidth = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double ?? 220
                    mainSplitView.setPosition(CGFloat(savedWidth), ofDividerAt: 0)
                    containerLeadingConstraint?.constant = 0
                } else {
                    let currentWidth = sidebarView.frame.width
                    if currentWidth > 0 {
                        UserDefaults.standard.set(currentWidth, forKey: "sidebarWidth")
                    }
                    mainSplitView.setPosition(0, ofDividerAt: 0)
                    containerLeadingConstraint?.constant = contentVerticalMargin
                }

                updateTrafficLightVisibility(isSidebarVisible: sidebarVisible)
                contentInspectorContainer?.layoutSubtreeIfNeeded()
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasSetInitialLayout,
              let mainSplitView,
              mainSplitView.bounds.width > 0 else { return }

        let savedWidth = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double ?? 220
        if store.sidebarVisible {
            mainSplitView.setPosition(CGFloat(savedWidth), ofDividerAt: 0)
        } else {
            mainSplitView.setPosition(0, ofDividerAt: 0)
        }

        mainSplitView.adjustSubviews()
        hasSetInitialLayout = true

        updateTrafficLightVisibility(isSidebarVisible: store.sidebarVisible)
        updateAllPaneColors()
    }

    private func updateTrafficLightVisibility(isSidebarVisible: Bool) {
        guard let window = view.window else { return }
        let shouldHide = !isSidebarVisible
        // 사이드바 숨김 상태에서는 트래픽 라이트 버튼을 감춥니다.
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
    }
}

extension FileManagerSplitViewController {
    private func createMainSplitView() -> NSSplitView {
        let mainSplit = AppearanceAwareSplitView()
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        mainSplit.setValue(NSColor.clear, forKey: "dividerColor")
        mainSplit.delegate = self
        mainSplit.wantsLayer = true
        // 배경을 투명하게 설정 (뒤의 블러가 보이도록)
        mainSplit.layer?.backgroundColor = NSColor.clear.cgColor

        mainSplit.onAppearanceChanged = { [weak self] in
            self?.updateAllPaneColors()
        }

        return mainSplit
    }

    private func updateAllPaneColors() {
        if let contentView = contentHosting?.view {
            updateContentPaneColor(for: contentView)
        }
        if let inspectorView = inspectorHosting?.view {
            updateInspectorPaneColor(for: inspectorView)
        }
        updateContentInspectorContainerColor()
    }

    private func updateContentInspectorContainerColor() {
        guard let mainSplit = mainSplitView,
              let container = contentInspectorContainer else { return }
        let appearance = mainSplit.effectiveAppearance
        let isDark = isDarkMode(appearance: appearance)

        appearance.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func updateContentPaneColor(for view: NSView) {
        // container의 검정색 50% 배경이 보이도록 투명하게 설정
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func setupSidebar(in mainSplit: NSSplitView) {
        let sidebarHosting = NSHostingController(
            rootView: SidebarView(store: store).ignoresSafeArea(.all, edges: .top),
        )
        sidebarHosting.safeAreaRegions = []

        // SwiftUI 뷰를 투명하게 설정 (뒤의 블러가 보이도록)
        sidebarHosting.view.wantsLayer = true
        sidebarHosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        mainSplit.addArrangedSubview(sidebarHosting.view)
        mainSplit.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        addChild(sidebarHosting)
        self.sidebarHosting = sidebarHosting
    }

    private func setupContentContainer(in mainSplit: NSSplitView) {
        // wrapper를 투명하게 설정 (뒤의 블러가 보이도록)
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSView()
        container.wantsLayer = true
        container.layer?.zPosition = 5
        container.layer?.cornerRadius = VoyagerDS.Radius.contentPane
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        contentInspectorContainer = container

        wrapper.addSubview(container)
        setupContentPane(in: container)

        let initialLeading: CGFloat = store.sidebarVisible ? 0 : contentVerticalMargin
        containerLeadingConstraint = container.leadingAnchor.constraint(
            equalTo: wrapper.leadingAnchor,
            constant: initialLeading,
        )

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: contentVerticalMargin),
            container.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -contentVerticalMargin),
            containerLeadingConstraint,
            container.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -contentVerticalMargin),
        ].compactMap(\.self))

        mainSplit.addArrangedSubview(wrapper)
        mainSplit.setHoldingPriority(.defaultLow, forSubviewAt: 1)
    }

    private func setupContentPane(in container: NSView) {
        let contentHosting = NSHostingController(rootView: makeContentRootView())
        contentHosting.safeAreaRegions = []
        contentHosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentHosting.view)
        addChild(contentHosting)
        self.contentHosting = contentHosting
        setupElevatedLayer(for: contentHosting.view)
        setupContentPaneConstraints(container: container, contentView: contentHosting.view)
    }

    private func makeContentRootView() -> some View {
        let store = store
        return WithViewStore(
            store,
            observe: { ContentPaneViewState(isComposerPresented: $0.composer.isPresented) },
            content: { viewStore in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ToolbarView(store: store)
                        ContentPaneView(store: store)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1),
                    )

                    if viewStore.isComposerPresented {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { store.send(.exitComposer) }
                    }

                    if viewStore.isComposerPresented {
                        ComposerView(store: store)
                            .padding(.horizontal, VoyagerDS.Spacing.composerHorizontalPadding)
                            .padding(.top, VoyagerDS.Spacing.composerTopPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .background(.thickMaterial)
                .overlay(ContentPaneMaterialTint())
                .ignoresSafeArea(.all, edges: .top)
                .animation(
                    .spring(response: 0.25, dampingFraction: 0.75),
                    value: viewStore.isComposerPresented,
                )
            },
        )
    }

    private struct ContentPaneMaterialTint: View {
        @Environment(\.colorScheme)
        private var colorScheme

        var body: some View {
            // 다크 모드에서만 머티리얼 대비를 살리는 얇은 틴트
            if colorScheme == .dark {
                Color.white.opacity(0.06)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
    }

    private func setupContentPaneConstraints(container: NSView, contentView: NSView) {
        contentLeadingConstraint = contentView.leadingAnchor.constraint(
            equalTo: container.leadingAnchor,
        )
        contentTopConstraint = contentView.topAnchor.constraint(
            equalTo: container.topAnchor,
        )
        contentBottomConstraint = contentView.bottomAnchor.constraint(
            equalTo: container.bottomAnchor,
        )
        contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
        )
        NSLayoutConstraint.activate(
            [
                contentLeadingConstraint,
                contentTopConstraint,
                contentBottomConstraint,
                contentTrailingConstraint,
            ].compactMap(\.self),
        )
    }

    private func setupElevatedLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 10
        updateContentPaneColor(for: view)
    }

    private func setupInspectorLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 10
        updateInspectorPaneColor(for: view)
    }

    private func updateInspectorPaneColor(for view: NSView) {
        guard let mainSplit = mainSplitView else { return }
        let appearance = mainSplit.effectiveAppearance
        let isDark = isDarkMode(appearance: appearance)

        appearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = VoyagerDS.AppKitSurface.inspectorPaneBackground(isDark: isDark).cgColor
        }
    }

    private func isDarkMode(appearance: NSAppearance) -> Bool {
        appearance.name == .darkAqua || appearance.name == .vibrantDark
    }
}

extension FileManagerSplitViewController {
    @MainActor
    private func updateInspectorPane(visible: Bool) {
        guard let container = contentInspectorContainer else { return }

        if visible {
            if inspectorHosting == nil {
                let inspectorView = InspectorPaneView(store: store)
                    .ignoresSafeArea(.all, edges: .top)
                let hosting = NSHostingController(rootView: inspectorView)
                hosting.view.translatesAutoresizingMaskIntoConstraints = false
                hosting.safeAreaRegions = []
                inspectorHosting = hosting
                addChild(hosting)

                container.addSubview(hosting.view)
                setupInspectorLayer(for: hosting.view)

                let divider = createDivider()
                divider.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(divider)
                contentInspectorDivider = divider
                updateContentInspectorLayout()

                store.send(.setInspectorPaneExists(true))
            }
        } else {
            if let hosting = inspectorHosting {
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
                inspectorHosting = nil

                contentInspectorDivider?.removeFromSuperview()
                contentInspectorDivider = nil

                updateContentInspectorLayout()

                store.send(.setInspectorPaneExists(false))
            }
        }
    }

    private func createDivider() -> ContentInspectorDivider {
        let divider = ContentInspectorDivider()
        divider.onResize = { [weak self] deltaX in
            guard let self,
                  let container = contentInspectorContainer else { return }

            let newInspectorWidth = inspectorWidth + deltaX
            let minInspectorWidth: CGFloat = 200
            let maxInspectorWidth: CGFloat = container.bounds.width - 400

            if newInspectorWidth >= minInspectorWidth, newInspectorWidth <= maxInspectorWidth {
                inspectorWidth = newInspectorWidth
                inspectorWidthConstraint?.constant = inspectorWidth
            }
        }
        return divider
    }
}

extension FileManagerSplitViewController {
    private func setupLayoutWithInspector(container: NSView, contentView: NSView, inspectorView: NSView) {
        if let contentTrailing = contentTrailingConstraint {
            contentTrailing.isActive = false
        }
        contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: inspectorView.leadingAnchor,
        )
        contentTrailingConstraint?.isActive = true

        [
            inspectorTrailingConstraint, inspectorTopConstraint,
            inspectorBottomConstraint, inspectorWidthConstraint,
        ].forEach { constraint in
            constraint?.isActive = false
        }
        inspectorTrailingConstraint = inspectorView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
        )
        inspectorTopConstraint = inspectorView.topAnchor.constraint(
            equalTo: container.topAnchor,
        )
        inspectorBottomConstraint = inspectorView.bottomAnchor.constraint(
            equalTo: container.bottomAnchor,
        )
        inspectorWidthConstraint = inspectorView.widthAnchor.constraint(equalToConstant: inspectorWidth)

        NSLayoutConstraint.activate(
            [
                inspectorTrailingConstraint,
                inspectorTopConstraint,
                inspectorBottomConstraint,
                inspectorWidthConstraint,
            ].compactMap(\.self),
        )

        setupDividerConstraints(container: container, inspectorView: inspectorView)
    }

    private func setupDividerConstraints(container: NSView, inspectorView: NSView) {
        guard let divider = contentInspectorDivider else { return }

        [
            dividerLeadingConstraint, dividerTopConstraint, dividerBottomConstraint,
        ].forEach { $0?.isActive = false }
        dividerLeadingConstraint = divider.leadingAnchor.constraint(
            equalTo: inspectorView.leadingAnchor,
            constant: -1,
        )
        dividerTopConstraint = divider.topAnchor.constraint(equalTo: container.topAnchor)
        dividerBottomConstraint = divider.bottomAnchor.constraint(equalTo: container.bottomAnchor)

        NSLayoutConstraint.activate(
            [
                dividerLeadingConstraint,
                dividerTopConstraint,
                dividerBottomConstraint,
                divider.widthAnchor.constraint(equalToConstant: 2),
            ].compactMap(\.self),
        )
    }

    private func setupLayoutWithoutInspector(container: NSView, contentView: NSView) {
        if let contentTrailing = contentTrailingConstraint {
            contentTrailing.isActive = false
        }
        contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
        )
        contentTrailingConstraint?.isActive = true

        [
            inspectorTrailingConstraint, inspectorTopConstraint,
            inspectorBottomConstraint, inspectorWidthConstraint,
        ].forEach { $0?.isActive = false }
    }
}

extension FileManagerSplitViewController {
    func splitView(
        _: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        switch dividerIndex {
        case 0: 150
        default: proposedMinimumPosition
        }
    }

    func splitView(
        _: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int,
    ) -> CGFloat {
        switch dividerIndex {
        case 0: 280
        default: proposedMaximumPosition
        }
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard let index = splitView.arrangedSubviews.firstIndex(of: view) else { return false }
        return index == 1
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard let index = splitView.arrangedSubviews.firstIndex(of: subview) else { return false }
        return index == 0
    }

    func splitViewDidResizeSubviews(_: Notification) {
        updateContentInspectorLayout()
        syncSidebarVisibilityWithWidth()
    }

    private func syncSidebarVisibilityWithWidth() {
        guard hasSetInitialLayout else { return }
        guard let sidebarView = sidebarHosting?.view,
              let mainSplitView else { return }

        let sidebarWidth = sidebarView.frame.width
        let isCollapsed = mainSplitView.isSubviewCollapsed(sidebarView)
        let collapseThreshold: CGFloat = 2

        if !isCollapsed, sidebarWidth > collapseThreshold {
            UserDefaults.standard.set(sidebarWidth, forKey: "sidebarWidth")
        }

        let shouldBeVisible = !isCollapsed
        if store.sidebarVisible != shouldBeVisible {
            store.send(.setSidebarVisible(shouldBeVisible))

            containerLeadingConstraint?.constant = shouldBeVisible ? 0 : contentVerticalMargin
            contentInspectorContainer?.layoutSubtreeIfNeeded()
        }
    }
}

// swiftlint:enable file_length
