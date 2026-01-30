import AppKit
import ComposableArchitecture
import SwiftUI

extension FileManagerSplitViewController {
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

    @MainActor
    func updateInspectorPane(visible: Bool) {
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

    private func setupInspectorLayer(for view: NSView) {
        view.wantsLayer = true
        view.layer?.zPosition = 10
        updateInspectorPaneColor(for: view)
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
            userDefaultsClient.setObject(sidebarWidth, "sidebarWidth")
        }

        let shouldBeVisible = !isCollapsed
        if store.sidebarVisible != shouldBeVisible {
            store.send(.setSidebarVisible(shouldBeVisible))

            containerLeadingConstraint?.constant = shouldBeVisible ? 0 : contentVerticalMargin
            contentInspectorContainer?.layoutSubtreeIfNeeded()
        }
    }
}
