import AppKit
import ComposableArchitecture
import SwiftUI

enum FileManagerWindowSplitLayout {
    struct Components {
        let rootView: NSVisualEffectView
        let splitView: NSSplitView
        let sidebarHosting: NSHostingController<SidebarView>
        let mainContainerHosting: NSHostingController<FileManagerWindowMainContainerView>
        let mainContainerView: NSView
        let mainContainerLeading: NSLayoutConstraint
    }

    static func build(
        store: StoreOf<FileManagerFeature>,
        mainContainerRootView: FileManagerWindowMainContainerView,
        contentVerticalMargin: CGFloat,
        isSidebarVisible: Bool,
    ) -> Components {
        let backgroundEffect = makeBackgroundEffectView()
        let splitView = makeSplitView()
        let sidebarHosting = makeSidebarHosting(store: store, in: splitView)
        let (mainContainerHosting, mainContainerLeading) = makeMainContainerHosting(
            rootView: mainContainerRootView,
            in: splitView,
            contentVerticalMargin: contentVerticalMargin,
            isSidebarVisible: isSidebarVisible,
        )
        embed(splitView: splitView, in: backgroundEffect)

        return Components(
            rootView: backgroundEffect,
            splitView: splitView,
            sidebarHosting: sidebarHosting,
            mainContainerHosting: mainContainerHosting,
            mainContainerView: mainContainerHosting.view,
            mainContainerLeading: mainContainerLeading,
        )
    }

    private static func makeBackgroundEffectView() -> NSVisualEffectView {
        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .sidebar
        backgroundEffect.blendingMode = .behindWindow
        backgroundEffect.state = .active
        backgroundEffect.wantsLayer = true
        return backgroundEffect
    }

    private static func makeSplitView() -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.setValue(NSColor.clear, forKey: "dividerColor")
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor
        return splitView
    }

    private static func makeSidebarHosting(
        store: StoreOf<FileManagerFeature>,
        in splitView: NSSplitView,
    ) -> NSHostingController<SidebarView> {
        let sidebarHosting = NSHostingController(
            rootView: SidebarView(store: store.scope(state: \.sidebar, action: \.sidebar)),
        )
        sidebarHosting.safeAreaRegions = []
        sidebarHosting.view.wantsLayer = true
        sidebarHosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        splitView.addArrangedSubview(sidebarHosting.view)
        splitView.setHoldingPriority(.defaultLow - 1, forSubviewAt: 0)

        return sidebarHosting
    }

    private static func makeMainContainerHosting(
        rootView: FileManagerWindowMainContainerView,
        in splitView: NSSplitView,
        contentVerticalMargin: CGFloat,
        isSidebarVisible: Bool,
    ) -> (NSHostingController<FileManagerWindowMainContainerView>, NSLayoutConstraint) {
        let mainContainerWrapper = NSView()
        mainContainerWrapper.wantsLayer = true
        mainContainerWrapper.layer?.backgroundColor = NSColor.clear.cgColor

        let mainContainerHosting = NSHostingController(rootView: rootView)
        mainContainerHosting.safeAreaRegions = []
        mainContainerHosting.view.wantsLayer = true
        mainContainerHosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        mainContainerHosting.view.translatesAutoresizingMaskIntoConstraints = false

        mainContainerWrapper.addSubview(mainContainerHosting.view)
        let mainContainerLeading = mainContainerHosting.view.leadingAnchor.constraint(
            equalTo: mainContainerWrapper.leadingAnchor,
            constant: isSidebarVisible ? 0 : contentVerticalMargin,
        )

        NSLayoutConstraint.activate([
            mainContainerHosting.view.topAnchor.constraint(
                equalTo: mainContainerWrapper.topAnchor,
                constant: contentVerticalMargin,
            ),
            mainContainerHosting.view.bottomAnchor.constraint(
                equalTo: mainContainerWrapper.bottomAnchor,
                constant: -contentVerticalMargin,
            ),
            mainContainerLeading,
            mainContainerHosting.view.trailingAnchor.constraint(
                equalTo: mainContainerWrapper.trailingAnchor,
                constant: -contentVerticalMargin,
            ),
        ])

        splitView.addArrangedSubview(mainContainerWrapper)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        return (mainContainerHosting, mainContainerLeading)
    }

    private static func embed(splitView: NSSplitView, in backgroundEffect: NSVisualEffectView) {
        splitView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffect.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: backgroundEffect.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: backgroundEffect.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: backgroundEffect.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: backgroundEffect.trailingAnchor),
        ])
    }

    static func applySplitBackground(_ splitView: NSSplitView?) {
        splitView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func updateMainContainerLeading(
        _ constraint: NSLayoutConstraint?,
        isSidebarVisible: Bool,
        contentVerticalMargin: CGFloat,
    ) {
        constraint?.constant = isSidebarVisible ? 0 : contentVerticalMargin
    }
}
