import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

class FileManagerSplitViewController: NSViewController, NSSplitViewDelegate {
    let store: StoreOf<FileManagerFeature>
    let initialPath: String?
    private var hasSetInitialLayout = false
    private var inspectorHosting: NSViewController?
    private var observationTask: Task<Void, Never>?

    private var contentInspectorContainer: NSView?
    private var contentHosting: NSViewController?
    private var contentInspectorDivider: ContentInspectorDivider?
    private var inspectorWidth: CGFloat = 300
    private let contentVerticalMargin: CGFloat = 8
    private var contentLeadingConstraint: NSLayoutConstraint?
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
        let mainSplit = createMainSplitView()
        setupSidebar(in: mainSplit)
        setupContentContainer(in: mainSplit)
        view = mainSplit
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
    }

    private func observeInspectorState() {
        observationTask = Task { @MainActor in
            for await inspectorVisible in store.publisher.inspectorVisible.values {
                updateInspectorPane(visible: inspectorVisible)
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasSetInitialLayout,
              let mainSplitView = view as? NSSplitView,
              mainSplitView.bounds.width > 0 else { return }

        mainSplitView.setPosition(220, ofDividerAt: 0)
        mainSplitView.adjustSubviews()
        hasSetInitialLayout = true
    }
}

extension FileManagerSplitViewController {
    private func createMainSplitView() -> NSSplitView {
        let mainSplit = NSSplitView()
        mainSplit.isVertical = true
        mainSplit.dividerStyle = .thin
        mainSplit.setValue(NSColor.clear, forKey: "dividerColor")
        mainSplit.delegate = self
        mainSplit.wantsLayer = true
        mainSplit.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        return mainSplit
    }

    private func setupSidebar(in mainSplit: NSSplitView) {
        let sidebarHosting = NSHostingController(
            rootView: SidebarView(store: store).ignoresSafeArea(.all, edges: .top)
        )
        sidebarHosting.safeAreaRegions = []
        mainSplit.addArrangedSubview(sidebarHosting.view)
        mainSplit.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        addChild(sidebarHosting)
        setupBackgroundLayer(for: sidebarHosting.view)
    }

    private func setupContentContainer(in mainSplit: NSSplitView) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.zPosition = 5
        contentInspectorContainer = container

        setupContentPane(in: container)
        mainSplit.addArrangedSubview(container)
        mainSplit.setHoldingPriority(.defaultLow, forSubviewAt: 1)
    }

    private func setupContentPane(in container: NSView) {
        let contentHosting = NSHostingController(
            rootView: VStack(spacing: 0) {
                ToolbarView(store: store)
                ContentPaneView(store: store)
            }
            .ignoresSafeArea(.all, edges: .top)
        )
        contentHosting.safeAreaRegions = []
        contentHosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentHosting.view)
        addChild(contentHosting)
        self.contentHosting = contentHosting
        setupElevatedLayer(for: contentHosting.view)
        setupContentPaneConstraints(container: container, contentView: contentHosting.view)
    }

    private func setupContentPaneConstraints(container: NSView, contentView: NSView) {
        contentLeadingConstraint = contentView.leadingAnchor.constraint(
            equalTo: container.leadingAnchor
        )
        contentTopConstraint = contentView.topAnchor.constraint(
            equalTo: container.topAnchor,
            constant: contentVerticalMargin
        )
        contentBottomConstraint = contentView.bottomAnchor.constraint(
            equalTo: container.bottomAnchor,
            constant: -contentVerticalMargin
        )
        contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
            constant: -contentVerticalMargin
        )
        NSLayoutConstraint.activate(
            [
                contentLeadingConstraint,
                contentTopConstraint,
                contentBottomConstraint,
                contentTrailingConstraint,
            ].compactMap { $0 }
        )
    }

    private func setupBackgroundLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 0
    }

    private func setupElevatedLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 10
        view.layer?.backgroundColor = NSColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0).cgColor
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
    }

    private func setupInspectorLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 10
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
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
            guard let self = self,
                  let container = self.contentInspectorContainer else { return }

            let newInspectorWidth = self.inspectorWidth + deltaX
            let minInspectorWidth: CGFloat = 200
            let maxInspectorWidth: CGFloat = container.bounds.width - 400

            if newInspectorWidth >= minInspectorWidth && newInspectorWidth <= maxInspectorWidth {
                self.inspectorWidth = newInspectorWidth
                self.inspectorWidthConstraint?.constant = self.inspectorWidth
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
            equalTo: inspectorView.leadingAnchor
        )
        contentTrailingConstraint?.isActive = true

        [
            inspectorTrailingConstraint, inspectorTopConstraint,
            inspectorBottomConstraint, inspectorWidthConstraint,
        ].forEach { constraint in
            constraint?.isActive = false
        }
        inspectorTrailingConstraint = inspectorView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor
        )
        inspectorTopConstraint = inspectorView.topAnchor.constraint(
            equalTo: container.topAnchor
        )
        inspectorBottomConstraint = inspectorView.bottomAnchor.constraint(
            equalTo: container.bottomAnchor
        )
        inspectorWidthConstraint = inspectorView.widthAnchor.constraint(equalToConstant: inspectorWidth)

        NSLayoutConstraint.activate(
            [
                inspectorTrailingConstraint,
                inspectorTopConstraint,
                inspectorBottomConstraint,
                inspectorWidthConstraint,
            ].compactMap { $0 }
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
            constant: -1
        )
        dividerTopConstraint = divider.topAnchor.constraint(equalTo: container.topAnchor)
        dividerBottomConstraint = divider.bottomAnchor.constraint(equalTo: container.bottomAnchor)

        NSLayoutConstraint.activate(
            [
                dividerLeadingConstraint,
                dividerTopConstraint,
                dividerBottomConstraint,
                divider.widthAnchor.constraint(equalToConstant: 2),
            ].compactMap { $0 }
        )
    }

    private func setupLayoutWithoutInspector(container: NSView, contentView: NSView) {
        if let contentTrailing = contentTrailingConstraint {
            contentTrailing.isActive = false
        }
        contentTrailingConstraint = contentView.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
            constant: -contentVerticalMargin
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
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0: return 150
        default: return proposedMinimumPosition
        }
    }

    func splitView(
        _: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        switch dividerIndex {
        case 0: return 400
        default: return proposedMaximumPosition
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
    }
}
