import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

extension FileManagerSplitViewController {
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

        store.send(.entries(.onAppear))

        observeInspectorState()
        observeSidebarState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasSetInitialLayout,
              let mainSplitView,
              mainSplitView.bounds.width > 0 else { return }

        // TODO: Constant 값 이동
        let savedWidth = userDefaultsClient.object(SettingsKeys.sidebarWidth) as? Double ?? 220
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
                      let sidebarView = sidebarHosting?.view,
                      mainSplitView.bounds.width > 0 else { continue }

                if sidebarVisible {
                    // TODO: Constant 값 이동
                    let savedWidth = userDefaultsClient.object(SettingsKeys.sidebarWidth) as? Double ?? 220
                    mainSplitView.setPosition(CGFloat(savedWidth), ofDividerAt: 0)
                    containerLeadingConstraint?.constant = 0
                } else {
                    let currentWidth = sidebarView.frame.width
                    if currentWidth > 0 {
                        userDefaultsClient.setObject(currentWidth, SettingsKeys.sidebarWidth)
                    }
                    mainSplitView.setPosition(0, ofDividerAt: 0)
                    containerLeadingConstraint?.constant = contentVerticalMargin
                }

                updateTrafficLightVisibility(isSidebarVisible: sidebarVisible)
                contentInspectorContainer?.layoutSubtreeIfNeeded()
            }
        }
    }

    private func updateTrafficLightVisibility(isSidebarVisible: Bool) {
        guard let window = view.window else { return }
        let shouldHide = !isSidebarVisible
        // 사이드바 숨김 상태에서는 트래픽 라이트 버튼을 감춥니다.
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
    }

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
        FileManagerWindowContentView(store: store)
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

    func updateInspectorPaneColor(for view: NSView) {
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
