import AppKit
import ComposableArchitecture
import SwiftUI

public enum FileManagerWindowMainContainerLayout {
    public struct Components {
        let containerView: NSView
        let splitView: NSSplitView
        let contentHosting: NSHostingController<AnyView>
    }

    static func build(contentRootView: AnyView) -> Components {
        nonisolated(unsafe) let safeRootView = contentRootView
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

        let contentHosting = NSHostingController(rootView: safeRootView)
        if #available(macOS 13.3, *) { contentHosting.safeAreaRegions = [] }
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
        store: StoreOf<FileManagerInspectorFeature>,
        isDark: Bool,
    ) -> NSHostingController<InspectorPaneView> {
        let hosting = NSHostingController(rootView: InspectorPaneView(store: store))
        if #available(macOS 13.3, *) { hosting.safeAreaRegions = [] }
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
