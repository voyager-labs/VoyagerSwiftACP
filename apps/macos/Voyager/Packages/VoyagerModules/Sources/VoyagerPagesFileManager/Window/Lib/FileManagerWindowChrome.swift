import AppKit
import Combine
import ComposableArchitecture

import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared

/// Focused window chrome configuration — style, traffic lights, frame, title.
///
/// Extracted from ``FileManagerWindowCoordinator`` to eliminate cross-coordinator
/// static method coupling. Both ``FileManagerWindowCoordinator`` and
/// ``FileManagerWindowSplitCoordinator`` reference this type instead of each other
/// for chrome concerns.
public enum FileManagerWindowChrome {
    public static func configureWindowStyle(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 350)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let toolbar = NSToolbar(identifier: "VoyagerMainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar

        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingIdentifier = "file-manager"
        window.tabbingMode = .preferred
    }

    public static func applyTrafficLightVisibility(to window: NSWindow, isSidebarVisible: Bool) {
        let shouldHide = !isSidebarVisible
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
    }

    public static func applyInitialFrame(
        _ window: NSWindow,
        initialWindowSizeProvider: (() -> NSSize?)?,
    ) {
        window.setFrameAutosaveName("VoyagerMainWindow")

        if !window.setFrameUsingName("VoyagerMainWindow") {
            let desiredSize: NSSize = initialWindowSizeProvider?() ?? NSSize(width: 960, height: 510)
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }
    }

    @discardableResult
    public static func bindWindowTitle(
        store: StoreOf<FileManagerFeature>,
        window: NSWindow,
    ) -> AnyCancellable {
        let makeWindowTitle: (String) -> String = { path in
            let computerName = FileManagerClient.liveValue.displayName("/")
            if path == "/" {
                return computerName
            }
            if path == computerName {
                return path
            }
            return FileManagerClient.liveValue.displayName(path)
        }

        func makeTitle(
            openedCollectionName: String?,
            isCollectionMode: Bool,
            titlePath: String,
            makeWindowTitle: (String) -> String,
        ) -> String {
            if let openedCollectionName {
                return openedCollectionName
            }
            if isCollectionMode {
                return "New Collection"
            }
            return makeWindowTitle(titlePath)
        }

        let initialTitle = makeTitle(
            openedCollectionName: store.state.content.collectionSession.openedName,
            isCollectionMode: store.state.content.isCollectionMode,
            titlePath: store.state.content.navigation.titlePath,
            makeWindowTitle: makeWindowTitle,
        )

        return Publishers.CombineLatest3(
            store.publisher.content.collectionSession.openedName.removeDuplicates(),
            store.publisher.content.isCollectionMode.removeDuplicates(),
            store.publisher.content.navigation.titlePath.removeDuplicates(),
        )
        .map { openedCollectionName, isCollectionMode, titlePath in
            makeTitle(
                openedCollectionName: openedCollectionName,
                isCollectionMode: isCollectionMode,
                titlePath: titlePath,
                makeWindowTitle: makeWindowTitle,
            )
        }
        .prepend(initialTitle)
        .removeDuplicates()
        .sink { [weak window] title in
            window?.title = title
        }
    }
}
