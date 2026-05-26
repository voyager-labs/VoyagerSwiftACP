import AppKit
import ComposableArchitecture

/// Synchronizes sidebar visibility and width between TCA store state and NSSplitView layout.
///
/// Uses a callback pattern (not Combine) so the owning coordinator controls observation lifecycle.
/// The coordinator calls ``applySidebarState(sidebarVisible:sidebarWidth:)`` when store state changes,
/// and ``handleSplitViewResize()`` when the user drags the divider.
@MainActor
struct FileManagerSidebarSync {
    struct Layout {
        let splitView: NSSplitView?
        let sidebarView: NSView?
        let mainContainerLeading: NSLayoutConstraint?
        let contentVerticalMargin: CGFloat
    }

    struct Callbacks {
        let onSidebarVisibilityChanged: (Bool, CGFloat) -> Void
        let onTrafficLightUpdate: (Bool) -> Void
    }

    enum ResizeDecision: Equatable {
        case none
        case hideSidebar
        case restoreSidebar
    }

    private enum Constants {
        static let sidebarMinWidth: CGFloat = 150
        static let sidebarMaxWidth: CGFloat = 280
    }

    private(set) var currentSidebarWidth: CGFloat
    private(set) var currentSidebarVisible: Bool?
    private var hasSetInitialLayout = false

    nonisolated static var sidebarMinWidth: CGFloat { Constants.sidebarMinWidth }
    nonisolated static var sidebarMaxWidth: CGFloat { Constants.sidebarMaxWidth }

    static func isSidebarEffectivelyVisible(
        splitView: NSSplitView?,
        sidebarView: NSView?,
    ) -> Bool {
        guard let splitView,
              let sidebarView
        else { return false }

        return !splitView.isSubviewCollapsed(sidebarView)
            && sidebarView.frame.width >= Constants.sidebarMinWidth
    }

    init(storeSidebarWidth: CGFloat) {
        currentSidebarWidth = Self.clampedWidth(storeSidebarWidth)
    }

    // MARK: - State Application (called when store state changes)

    mutating func applySidebarState(
        sidebarVisible: Bool,
        sidebarWidth: CGFloat,
        layout: Layout,
        callbacks: Callbacks,
    ) {
        let clamped = Self.clampedWidth(sidebarWidth)
        let sidebarWidthChanged = abs(currentSidebarWidth - clamped) > 0.5
        currentSidebarWidth = clamped

        applyInitialLayoutIfNeeded(
            sidebarVisible: sidebarVisible,
            sidebarWidth: clamped,
            splitView: layout.splitView,
            mainContainerLeading: layout.mainContainerLeading,
            contentVerticalMargin: layout.contentVerticalMargin,
            onTrafficLightUpdate: callbacks.onTrafficLightUpdate,
        )

        let needsVisibleLayoutRestore = sidebarVisible
            && !Self.isSidebarEffectivelyVisible(
                splitView: layout.splitView,
                sidebarView: layout.sidebarView,
            )

        if currentSidebarVisible != sidebarVisible {
            updateSidebarVisibility(
                isVisible: sidebarVisible,
                sidebarWidth: clamped,
                layout: layout,
                callbacks: callbacks,
            )
        } else if sidebarVisible, sidebarWidthChanged || needsVisibleLayoutRestore {
            layout.splitView?.setPosition(clamped, ofDividerAt: 0)
            layout.splitView?.adjustSubviews()
        }

        currentSidebarVisible = sidebarVisible
    }

    // MARK: - Initial Layout

    mutating func applyInitialLayoutIfNeeded(
        sidebarVisible: Bool,
        sidebarWidth: CGFloat,
        splitView: NSSplitView?,
        mainContainerLeading: NSLayoutConstraint?,
        contentVerticalMargin: CGFloat,
        onTrafficLightUpdate: (Bool) -> Void,
    ) {
        guard !hasSetInitialLayout,
              let splitView,
              splitView.bounds.width > 0
        else { return }

        let clampedSidebarWidth = Self.clampedWidth(sidebarWidth)

        if sidebarVisible {
            splitView.setPosition(clampedSidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: contentVerticalMargin,
            )
        } else {
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: contentVerticalMargin,
            )
        }

        splitView.adjustSubviews()
        hasSetInitialLayout = true
        currentSidebarVisible = sidebarVisible
        onTrafficLightUpdate(sidebarVisible)
    }

    // MARK: - Split View Resize Handling (called from splitViewDidResizeSubviews)

    func handleSplitViewResize(
        splitView: NSSplitView,
        sidebarView: NSView,
        storeSidebarVisible: Bool,
        isUserInitiatedCollapse: Bool,
        syncWidthToStore: (CGFloat) -> Void,
    ) -> ResizeDecision {
        guard hasSetInitialLayout else { return .none }

        let sidebarWidth = sidebarView.frame.width

        if Self.isSidebarEffectivelyVisible(splitView: splitView, sidebarView: sidebarView) {
            syncWidthToStore(sidebarWidth)
            return .none
        }

        guard storeSidebarVisible else { return .none }
        return isUserInitiatedCollapse ? .hideSidebar : .restoreSidebar
    }

    // MARK: - Private Helpers

    private mutating func updateSidebarVisibility(
        isVisible: Bool,
        sidebarWidth: CGFloat,
        layout: Layout,
        callbacks: Callbacks,
    ) {
        guard let splitView = layout.splitView,
              let sidebarView = layout.sidebarView,
              splitView.bounds.width > 0
        else { return }

        if isVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                layout.mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: layout.contentVerticalMargin,
            )
        } else {
            let currentWidth = sidebarView.frame.width
            if currentWidth >= Constants.sidebarMinWidth {
                callbacks.onSidebarVisibilityChanged(false, currentWidth)
            }
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                layout.mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: layout.contentVerticalMargin,
            )
        }

        callbacks.onTrafficLightUpdate(isVisible)
    }

    private static func clampedWidth(_ width: CGFloat) -> CGFloat {
        max(Constants.sidebarMinWidth, min(Constants.sidebarMaxWidth, width))
    }
}
