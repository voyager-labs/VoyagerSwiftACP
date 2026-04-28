import AppKit
import Combine
import ComposableArchitecture

@MainActor
final class FileManagerSidebarSync {
    private enum Constants {
        static let sidebarMinWidth: CGFloat = 150
        static let sidebarMaxWidth: CGFloat = 280
        static let sidebarCollapseThreshold: CGFloat = 2
    }

    private(set) var hasSetInitialLayout = false
    private(set) var currentSidebarVisible: Bool?
    private(set) var currentSidebarWidth: CGFloat
    private var cancellables: Set<AnyCancellable> = []

    private weak var store: StoreOf<FileManagerFeature>?
    private let contentVerticalMargin: CGFloat

    var onApplyInitialLayout: ((_ sidebarVisible: Bool, _ sidebarWidth: CGFloat, _ contentVerticalMargin: CGFloat)
        -> Void)?
    var onToggleSidebar: ((_ isVisible: Bool, _ sidebarWidth: CGFloat, _ contentVerticalMargin: CGFloat) -> Void)?
    var onAdjustDivider: ((_ sidebarWidth: CGFloat) -> Void)?
    var onUpdateTrafficLights: ((_ isSidebarVisible: Bool) -> Void)?

    init(initialSidebarWidth: CGFloat, contentVerticalMargin: CGFloat) {
        currentSidebarWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, initialSidebarWidth),
        )
        self.contentVerticalMargin = contentVerticalMargin
    }

    func start(store: StoreOf<FileManagerFeature>) {
        self.store = store
        observeSidebarState(store)
        applySidebarState(
            sidebarVisible: store.sidebar.sidebarVisible,
            sidebarWidth: store.sidebar.sidebarWidth,
        )
    }

    func tearDown() {
        cancellables.removeAll()
        store = nil
    }

    private func observeSidebarState(_ store: StoreOf<FileManagerFeature>) {
        store.publisher.sidebar
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sidebarState in
                self?.applySidebarState(
                    sidebarVisible: sidebarState.sidebarVisible,
                    sidebarWidth: sidebarState.sidebarWidth,
                )
            }
            .store(in: &cancellables)
    }

    private func applySidebarState(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        let clampedSidebarWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, sidebarWidth),
        )
        let sidebarWidthChanged = abs(currentSidebarWidth - clampedSidebarWidth) > 0.5
        currentSidebarWidth = clampedSidebarWidth

        if !hasSetInitialLayout {
            onApplyInitialLayout?(sidebarVisible, clampedSidebarWidth, contentVerticalMargin)
            return
        }

        if currentSidebarVisible != sidebarVisible {
            onToggleSidebar?(sidebarVisible, clampedSidebarWidth, contentVerticalMargin)
            onUpdateTrafficLights?(sidebarVisible)
        } else if sidebarVisible, sidebarWidthChanged {
            onAdjustDivider?(clampedSidebarWidth)
        }

        currentSidebarVisible = sidebarVisible
    }

    func markInitialLayoutApplied(sidebarVisible: Bool, sidebarWidth: CGFloat) {
        hasSetInitialLayout = true
        currentSidebarVisible = sidebarVisible
        currentSidebarWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, sidebarWidth),
        )
        onUpdateTrafficLights?(sidebarVisible)
    }

    func handleSplitViewResize(
        sidebarViewFrame: CGRect,
        isCollapsed: Bool,
        splitViewWidth _: CGFloat,
    ) {
        guard hasSetInitialLayout else { return }

        let sidebarWidth = sidebarViewFrame.width

        if !isCollapsed, sidebarWidth > Constants.sidebarCollapseThreshold {
            syncSidebarWidthToStore(sidebarWidth)
        }

        guard let store else { return }
        if store.sidebar.sidebarVisible, isCollapsed {
            let width = currentSidebarWidth
            DispatchQueue.main.async { [weak self] in
                self?.onToggleSidebar?(true, width, self?.contentVerticalMargin ?? 4)
            }
        }
    }

    func shouldSyncWidthToStore(sidebarViewWidth: CGFloat, isCollapsed: Bool) -> Bool {
        !isCollapsed && sidebarViewWidth > Constants.sidebarCollapseThreshold
    }

    func syncSidebarWidthToStore(_ width: CGFloat) {
        let clampedWidth = max(
            Constants.sidebarMinWidth,
            min(Constants.sidebarMaxWidth, width),
        )
        guard let store,
              abs(store.sidebar.sidebarWidth - clampedWidth) > 0.5
        else { return }
        store.send(.sidebar(.view(.setSidebarWidth(clampedWidth))))
    }

    func widthBeforeCollapse(sidebarViewFrame: CGRect) -> CGFloat? {
        let currentWidth = sidebarViewFrame.width
        if currentWidth > Constants.sidebarCollapseThreshold {
            syncSidebarWidthToStore(currentWidth)
        }
        return currentWidth
    }

    var sidebarMinWidth: CGFloat { Constants.sidebarMinWidth }
    var sidebarMaxWidth: CGFloat { Constants.sidebarMaxWidth }
    var sidebarCollapseThreshold: CGFloat { Constants.sidebarCollapseThreshold }
}
