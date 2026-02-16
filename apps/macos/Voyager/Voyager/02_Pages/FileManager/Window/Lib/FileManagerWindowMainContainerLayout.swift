import AppKit
import ComposableArchitecture
import SwiftUI

enum FileManagerWindowMainContainerLayout {
    struct Components {
        let containerView: NSView
        let splitView: NSSplitView
        let contentHosting: NSHostingController<FileManagerContentPaneView>
    }

    static func build(contentRootView: FileManagerContentPaneView) -> Components {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.zPosition = 5
        containerView.layer?.cornerRadius = VoyagerDS.Radius.contentPane
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.setValue(NSColor.clear, forKey: "dividerColor")
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentHosting = NSHostingController(rootView: contentRootView)
        contentHosting.safeAreaRegions = []
        applyContentPaneStyle(contentHosting.view)

        splitView.addArrangedSubview(contentHosting.view)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)

        containerView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        return Components(
            containerView: containerView,
            splitView: splitView,
            contentHosting: contentHosting,
        )
    }

    static func makeInspectorHosting(
        store: StoreOf<FileManagerFeature>,
        isDark: Bool,
    ) -> NSHostingController<InspectorPaneView> {
        let hosting = NSHostingController(rootView: InspectorPaneView(store: store))
        hosting.safeAreaRegions = []
        applyInspectorPaneStyle(hosting.view, isDark: isDark)
        return hosting
    }

    static func applyAppearance(
        splitView: NSSplitView?,
        containerView: NSView?,
        contentView: NSView?,
        inspectorView: NSView?,
        isDark: Bool,
    ) {
        splitView?.layer?.backgroundColor = NSColor.clear.cgColor
        applyContentPaneStyle(contentView)
        applyInspectorPaneStyle(inspectorView, isDark: isDark)
        containerView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func applyContentPaneStyle(_ view: NSView?) {
        view?.wantsLayer = true
        view?.layer?.zPosition = 10
        view?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func applyInspectorPaneStyle(_ view: NSView?, isDark: Bool) {
        view?.wantsLayer = true
        view?.layer?.zPosition = 10
        view?.layer?.backgroundColor = VoyagerDS.AppKitSurface.inspectorPaneBackground(isDark: isDark).cgColor
    }
}
