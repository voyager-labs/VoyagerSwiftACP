import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerShared

@MainActor
enum FileManagerWindowMainContainerLayout {
    struct Components {
        let containerView: NSView
        let contentBackgroundEffectView: NSVisualEffectView
        let splitView: NSSplitView
        let contentHosting: NSHostingController<AnyView>
    }

    static func build(
        contentRootView: AnyView,
        materialOverride: FileManagerWindowMaterialOverride? = nil,
    ) -> Components {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.zPosition = 5
        containerView.layer?.cornerRadius = VoyagerDS.Radius.contentPane
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentBackground = makeContentBackgroundEffectView(
            materialOverride: materialOverride,
        )
        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.setValue(NSColor.clear, forKey: "dividerColor")
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.clear.cgColor

        let contentHosting = NSHostingController(rootView: contentRootView)
        if #available(macOS 13.3, *) {
            contentHosting.safeAreaRegions = []
        }
        applyContentPaneStyle(contentHosting.view)

        splitView.addArrangedSubview(contentHosting.view)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)

        containerView.addSubview(contentBackground)
        containerView.addSubview(splitView)
        NSLayoutConstraint.activate([
            contentBackground.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentBackground.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            contentBackground.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentBackground.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: containerView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        return Components(
            containerView: containerView,
            contentBackgroundEffectView: contentBackground,
            splitView: splitView,
            contentHosting: contentHosting,
        )
    }

    static func makeInspectorHosting(
        store: StoreOf<FileManagerInspectorFeature>,
        isDark: Bool,
    ) -> NSHostingController<InspectorPaneView> {
        let hosting = NSHostingController(rootView: InspectorPaneView(store: store))
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []
        }
        applyInspectorPaneStyle(hosting.view, isDark: isDark)
        hosting.view.setFrameSize(NSSize(width: FileManagerInspectorLayoutMetrics.minWidth, height: 0))
        return hosting
    }

    static func applyAppearance(
        splitView: NSSplitView?,
        containerView _: NSView?,
        contentView: NSView?,
        inspectorView: NSView?,
        isDark: Bool,
    ) {
        splitView?.layer?.backgroundColor = NSColor.clear.cgColor
        applyContentPaneStyle(contentView)
        applyInspectorPaneStyle(inspectorView, isDark: isDark)
    }

    static func updateMaterialOverride(
        _ override: FileManagerWindowMaterialOverride?,
        contentBackgroundEffectView: NSVisualEffectView?,
    ) {
        guard let contentBackgroundEffectView else { return }
        applyMaterialOverride(override, to: contentBackgroundEffectView)
    }

    static func applyContentPaneStyle(_ view: NSView?) {
        view?.wantsLayer = true
        view?.layer?.zPosition = 10
        view?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func applyInspectorPaneStyle(_ view: NSView?, isDark _: Bool) {
        view?.wantsLayer = true
        view?.layer?.zPosition = 10
        view?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func makeContentBackgroundEffectView(
        materialOverride: FileManagerWindowMaterialOverride?,
    ) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.state = .followsWindowActiveState
        applyMaterialOverride(materialOverride, to: view)
        return view
    }

    private static func applyMaterialOverride(
        _ override: FileManagerWindowMaterialOverride?,
        to contentBackgroundEffectView: NSVisualEffectView,
    ) {
        if let override {
            override.contentBackground.apply(to: contentBackgroundEffectView)
        } else {
            VoyagerDS.SurfaceMaterialRole.mainContentBackground.apply(to: contentBackgroundEffectView)
        }
    }
}
