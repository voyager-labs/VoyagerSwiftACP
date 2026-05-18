import AppKit
import ComposableArchitecture

/// Synchronizes sidebar visibility and width between TCA store state and NSSplitView layout.
///
/// Uses a callback pattern (not Combine) so the owning coordinator controls observation lifecycle.
/// The coordinator calls ``applySidebarState(sidebarVisible:sidebarWidth:)`` when store state changes,
/// and ``handleSplitViewResize()`` when the user drags the divider.
struct FileManagerSidebarSync {
    private enum Constants {
        static let sidebarMinWidth: CGFloat = 150
        static let sidebarMaxWidth: CGFloat = 280
        static let sidebarCollapseThreshold: CGFloat = 2
    }

    private(set) var currentSidebarWidth: CGFloat
    private(set) var currentSidebarVisible: Bool?
    private var hasSetInitialLayout = false

    var sidebarMinWidth: CGFloat { Constants.sidebarMinWidth }
    var sidebarMaxWidth: CGFloat { Constants.sidebarMaxWidth }

    init(storeSidebarWidth: CGFloat) {
        currentSidebarWidth = Self.clampedWidth(storeSidebarWidth)
    }

    // MARK: - State Application (called when store state changes)

    mutating func applySidebarState(
        sidebarVisible: Bool,
        sidebarWidth: CGFloat,
        splitView: NSSplitView?,
        sidebarView: NSView?,
        mainContainerLeading: NSLayoutConstraint?,
        contentVerticalMargin: CGFloat,
        onSidebarVisibilityChanged: (Bool, CGFloat) -> Void,
        onTrafficLightUpdate: (Bool) -> Void,
    ) {
        let clamped = Self.clampedWidth(sidebarWidth)
        let sidebarWidthChanged = abs(currentSidebarWidth - clamped) > 0.5
        currentSidebarWidth = clamped

        applyInitialLayoutIfNeeded(
            sidebarVisible: sidebarVisible,
            sidebarWidth: clamped,
            splitView: splitView,
            mainContainerLeading: mainContainerLeading,
            contentVerticalMargin: contentVerticalMargin,
            onTrafficLightUpdate: onTrafficLightUpdate,
        )

        if currentSidebarVisible != sidebarVisible {
            updateSidebarVisibility(
                isVisible: sidebarVisible,
                sidebarWidth: clamped,
                splitView: splitView,
                sidebarView: sidebarView,
                mainContainerLeading: mainContainerLeading,
                contentVerticalMargin: contentVerticalMargin,
                onSidebarVisibilityChanged: onSidebarVisibilityChanged,
                onTrafficLightUpdate: onTrafficLightUpdate,
            )
        } else if sidebarVisible, sidebarWidthChanged {
            splitView?.setPosition(clamped, ofDividerAt: 0)
            splitView?.adjustSubviews()
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

        if sidebarVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
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
        onTrafficLightUpdate(sidebarVisible)
    }

    // MARK: - Split View Resize Handling (called from splitViewDidResizeSubviews)

    mutating func handleSplitViewResize(
        splitView: NSSplitView,
        sidebarView: NSView,
        storeSidebarVisible: Bool,
        syncWidthToStore: (CGFloat) -> Void,
        forceRestoreSidebar: (Bool, CGFloat) -> Void,
    ) {
        guard hasSetInitialLayout else { return }

        let sidebarWidth = sidebarView.frame.width
        let isCollapsed = splitView.isSubviewCollapsed(sidebarView)

        if !isCollapsed, sidebarWidth > Constants.sidebarCollapseThreshold {
            syncWidthToStore(sidebarWidth)
        }

        if storeSidebarVisible, isCollapsed {
            let width = currentSidebarWidth
            forceRestoreSidebar(true, width)
        }
    }

    // MARK: - Private Helpers

    private mutating func updateSidebarVisibility(
        isVisible: Bool,
        sidebarWidth: CGFloat,
        splitView: NSSplitView?,
        sidebarView: NSView?,
        mainContainerLeading: NSLayoutConstraint?,
        contentVerticalMargin: CGFloat,
        onSidebarVisibilityChanged: (Bool, CGFloat) -> Void,
        onTrafficLightUpdate: (Bool) -> Void,
    ) {
        guard let splitView,
              let sidebarView,
              splitView.bounds.width > 0
        else { return }

        if isVisible {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                mainContainerLeading,
                isSidebarVisible: true,
                contentVerticalMargin: contentVerticalMargin,
            )
        } else {
            let currentWidth = sidebarView.frame.width
            if currentWidth > Constants.sidebarCollapseThreshold {
                onSidebarVisibilityChanged(false, currentWidth)
            }
            splitView.setPosition(0, ofDividerAt: 0)
            FileManagerWindowSplitLayout.updateMainContainerLeading(
                mainContainerLeading,
                isSidebarVisible: false,
                contentVerticalMargin: contentVerticalMargin,
            )
        }

        onTrafficLightUpdate(isVisible)
    }

    private static func clampedWidth(_ width: CGFloat) -> CGFloat {
        max(Constants.sidebarMinWidth, min(Constants.sidebarMaxWidth, width))
    }
}
