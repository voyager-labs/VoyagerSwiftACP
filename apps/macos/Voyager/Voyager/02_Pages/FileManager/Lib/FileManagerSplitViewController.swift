import AppKit
import ComposableArchitecture

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

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        super.resizeSubviews(withOldSize: oldSize)
    }

    func updateBackgroundColor() {
        wantsLayer = true
        // 투명하게 설정 (뒤의 블러가 보이도록)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

class FileManagerSplitViewController: NSViewController, NSSplitViewDelegate {
    let store: StoreOf<FileManagerFeature>
    let initialPath: String?
    let userDefaultsClient: UserDefaultsClient
    var hasSetInitialLayout = false
    var inspectorHosting: NSViewController?
    var observationTask: Task<Void, Never>?
    var sidebarHosting: NSViewController?

    var contentInspectorContainer: NSView?
    var contentHosting: NSViewController?
    var contentInspectorDivider: ContentInspectorDivider?
    var mainSplitView: NSSplitView?
    var inspectorWidth: CGFloat = 300
    let contentVerticalMargin: CGFloat = 4
    var contentLeadingConstraint: NSLayoutConstraint?
    var containerLeadingConstraint: NSLayoutConstraint?
    var contentTrailingConstraint: NSLayoutConstraint?
    var contentTopConstraint: NSLayoutConstraint?
    var contentBottomConstraint: NSLayoutConstraint?
    var inspectorTrailingConstraint: NSLayoutConstraint?
    var inspectorTopConstraint: NSLayoutConstraint?
    var inspectorBottomConstraint: NSLayoutConstraint?
    var inspectorWidthConstraint: NSLayoutConstraint?
    var dividerLeadingConstraint: NSLayoutConstraint?
    var dividerTopConstraint: NSLayoutConstraint?
    var dividerBottomConstraint: NSLayoutConstraint?

    init(
        store: StoreOf<FileManagerFeature>,
        initialPath: String? = nil,
        userDefaultsClient: UserDefaultsClient = .liveValue,
    ) {
        self.store = store
        self.initialPath = initialPath
        self.userDefaultsClient = userDefaultsClient
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        observationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
