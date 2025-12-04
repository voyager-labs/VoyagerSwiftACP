import AppKit
import ComposableArchitecture
import SwiftUI

class FileManagerSplitViewController: NSViewController, NSSplitViewDelegate {
    let store: StoreOf<FileManagerFeature>
    let initialPath: String?
    private var hasSetInitialLayout = false

    init(store: StoreOf<FileManagerFeature>, initialPath: String? = nil) {
        self.store = store
        self.initialPath = initialPath
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self

        let sidebarHosting = NSHostingController(
            rootView: SidebarView(store: store).ignoresSafeArea(.all, edges: .top)
        )
        sidebarHosting.safeAreaRegions = []
        split.addArrangedSubview(sidebarHosting.view)
        split.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)
        addChild(sidebarHosting)

        let contentHosting = NSHostingController(
            rootView: VStack(spacing: 0) {
                ToolbarView(store: store)
                ContentPaneView(store: store)
            }
            .ignoresSafeArea(.all, edges: .top)
        )
        contentHosting.safeAreaRegions = []
        split.addArrangedSubview(contentHosting.view)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        addChild(contentHosting)

        view = split
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
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        guard !hasSetInitialLayout,
              let splitView = view as? NSSplitView,
              splitView.bounds.width > 0 else { return }

        splitView.setPosition(220, ofDividerAt: 0)
        splitView.adjustSubviews()

        hasSetInitialLayout = true
    }

    func splitView(
        _: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        dividerIndex == 0 ? 150 : proposedMinimumPosition
    }

    func splitView(
        _: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        dividerIndex == 0 ? 400 : proposedMaximumPosition
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard let index = splitView.arrangedSubviews.firstIndex(of: view) else { return false }
        return index == 1
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard let index = splitView.arrangedSubviews.firstIndex(of: subview) else { return false }
        return index == 0
    }
}
