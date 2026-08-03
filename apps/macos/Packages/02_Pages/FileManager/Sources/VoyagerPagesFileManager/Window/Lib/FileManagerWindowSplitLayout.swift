import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

@MainActor
enum FileManagerWindowSplitLayout {
    struct Components {
        let rootView: NSVisualEffectView
        let rootShellEffectView: NSVisualEffectView
        let splitView: NSSplitView
        let sidebarSurface: NSView
        let sidebarHosting: NSHostingController<AnyView>
        let mainContainerHosting: NSHostingController<FileManagerWindowMainContainerView>
        let mainContainerView: NSView
        let mainContainerLeading: NSLayoutConstraint
    }

    static func build(
        store: StoreOf<FileManagerFeature>,
        workspaceClient: WorkspaceClient,
        keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator,
        mainContainerRootView: FileManagerWindowMainContainerView,
        materialOverride: FileManagerWindowMaterialOverride?,
        contentVerticalMargin: CGFloat,
        isSidebarVisible: Bool,
    ) -> Components {
        let rootShell = VoyagerDS.SurfaceMaterialRole.windowShell.makeBackgroundView()
        applyMaterialOverride(materialOverride, to: rootShell)
        let splitView = makeSplitView()
        let sidebarHosting = makeSidebarHosting(
            store: store,
            workspaceClient: workspaceClient,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
            in: splitView,
        )
        let (mainContainerHosting, mainContainerLeading) = makeMainContainerHosting(
            rootView: mainContainerRootView,
            in: splitView,
            contentVerticalMargin: contentVerticalMargin,
            isSidebarVisible: isSidebarVisible,
        )
        embed(splitView: splitView, in: rootShell)

        return Components(
            rootView: rootShell,
            rootShellEffectView: rootShell,
            splitView: splitView,
            sidebarSurface: sidebarHosting.view,
            sidebarHosting: sidebarHosting,
            mainContainerHosting: mainContainerHosting,
            mainContainerView: mainContainerHosting.view,
            mainContainerLeading: mainContainerLeading,
        )
    }

    static func applySplitBackground(_ splitView: NSSplitView?) {
        splitView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func updateMaterialOverride(
        _ override: FileManagerWindowMaterialOverride?,
        rootShellEffectView: NSVisualEffectView?,
    ) {
        guard let rootShellEffectView else { return }
        applyMaterialOverride(override, to: rootShellEffectView)
    }

    static func updateMainContainerLeading(
        _ constraint: NSLayoutConstraint?,
        isSidebarVisible: Bool,
        contentVerticalMargin: CGFloat,
    ) {
        constraint?.constant = isSidebarVisible ? 0 : contentVerticalMargin
    }

    private static func applyMaterialOverride(
        _ override: FileManagerWindowMaterialOverride?,
        to rootShellEffectView: NSVisualEffectView,
    ) {
        if let override {
            override.windowShell.apply(to: rootShellEffectView)
        } else {
            VoyagerDS.SurfaceMaterialRole.windowShell.apply(to: rootShellEffectView)
        }
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
        workspaceClient: WorkspaceClient,
        keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator,
        in splitView: NSSplitView,
    ) -> NSHostingController<AnyView> {
        let rootView = AnyView(
            SidebarView(
                sidebarStore: store.scope(state: \.sidebar, action: \.sidebar),
                contentTabStore: store.scope(state: \.contentTabs, action: \.contentTabs),
                interactionStore: store.scope(
                    state: \.contentTabRowInteractionSurface,
                    action: \.sidebar,
                ),
                workspaceClient: workspaceClient,
            )
            .environment(\.fileManagerKeyCommandFocusCoordinator, keyCommandFocusCoordinator),
        )
        let sidebarHosting = NSHostingController(rootView: rootView)
        let sidebarSurface = SidebarHostingView(rootView: rootView)
        if #available(macOS 13.3, *) {
            sidebarSurface.safeAreaRegions = []
        }
        sidebarSurface.wantsLayer = true
        sidebarSurface.layer?.backgroundColor = NSColor.clear.cgColor
        sidebarHosting.view = sidebarSurface

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
        if #available(macOS 13.3, *) {
            mainContainerHosting.safeAreaRegions = []
        }
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

    private static func embed(splitView: NSSplitView, in rootShell: NSView) {
        splitView.translatesAutoresizingMaskIntoConstraints = false
        rootShell.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: rootShell.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootShell.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: rootShell.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootShell.trailingAnchor),
        ])
    }
}
