import AppKit
import Combine
import ComposableArchitecture
import VoyagerShared

/// Window chrome styling, traffic-light visibility, frame initialization, and title binding.
///
/// Extracts all NSWindow appearance/configuration concerns from FileManagerWindowCoordinator
/// so the coordinator remains a thin wiring layer.
enum FileManagerWindowChrome {
    private enum Constants {
        static let minimumWindowSize = NSSize(width: 600, height: 350)
        static let defaultWindowSize = NSSize(width: 960, height: 510)
    }

    // MARK: - Appearance Helpers

    static var currentIsDark: Bool {
        let appearance = NSApp.effectiveAppearance
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        return best == .darkAqua
    }

    // MARK: - Window Style

    static func configureWindowStyle(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = Constants.minimumWindowSize

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

    // MARK: - Traffic Lights

    static func applyTrafficLightVisibility(to window: NSWindow, isSidebarVisible: Bool) {
        let shouldHide = !isSidebarVisible
        window.standardWindowButton(.closeButton)?.isHidden = shouldHide
        window.standardWindowButton(.miniaturizeButton)?.isHidden = shouldHide
        window.standardWindowButton(.zoomButton)?.isHidden = shouldHide
    }

    // MARK: - Initial Frame

    static func applyInitialFrame(
        _ window: NSWindow,
        initialWindowSizeProvider: (() -> NSSize?)?,
        reservesSidebarWidth: Bool = false,
    ) {
        window.setFrameAutosaveName("VoyagerMainWindow")
        let minimumInitialWidth = minimumInitialWidth(reservesSidebarWidth: reservesSidebarWidth)

        if !window.setFrameUsingName("VoyagerMainWindow") {
            let desiredSize = constrainedInitialSize(
                initialWindowSizeProvider?() ?? Constants.defaultWindowSize,
                minimumWidth: minimumInitialWidth,
                minimumHeight: window.minSize.height,
            )
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: screenFrame.midX - desiredSize.width / 2,
                y: screenFrame.midY - desiredSize.height / 2,
            )
            window.setFrame(NSRect(origin: origin, size: desiredSize), display: false)
        }

        expandInitialFrameIfNeeded(
            window,
            minimumWidth: minimumInitialWidth,
            minimumHeight: window.minSize.height,
        )
    }

    static func minimumInitialWidth(reservesSidebarWidth: Bool) -> CGFloat {
        Constants.minimumWindowSize.width
            + (reservesSidebarWidth ? FileManagerSidebarSync.sidebarMinWidth : 0)
    }

    static func constrainedInitialSize(
        _ size: NSSize,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat,
    ) -> NSSize {
        NSSize(
            width: max(size.width, minimumWidth),
            height: max(size.height, minimumHeight),
        )
    }

    // MARK: - Title Binding

    static func bindTitle(
        to window: NSWindow,
        store: StoreOf<FileManagerFeature>,
        cancellables: inout Set<AnyCancellable>,
    ) {
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

        let initialTitle = makeTitle(
            openedCollectionName: store.state.content.collection.collectionSession.document?.name,
            isCollectionMode: store.state.content.isCollectionMode,
            titlePath: store.state.content.navigation.titlePath,
            makeWindowTitle: makeWindowTitle,
        )

        makeWindowTitlePublisher(store: store, makeWindowTitle: makeWindowTitle)
            .prepend(initialTitle)
            .removeDuplicates()
            .sink { [weak window] title in
                window?.title = title
            }
            .store(in: &cancellables)
    }

    // MARK: - Title Internals

    static func makeTitle(
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

    private static func expandInitialFrameIfNeeded(
        _ window: NSWindow,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat,
    ) {
        let currentFrame = window.frame
        let constrainedSize = constrainedInitialSize(
            currentFrame.size,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight,
        )
        guard constrainedSize != currentFrame.size else { return }

        window.setFrame(NSRect(origin: currentFrame.origin, size: constrainedSize), display: false)
    }

    private static func makeWindowTitlePublisher(
        store: StoreOf<FileManagerFeature>,
        makeWindowTitle: @escaping (String) -> String,
    ) -> some Publisher<String, Never> {
        Publishers.CombineLatest3(
            store.publisher.content.collection.collectionSession.document
                .map { $0?.name }
                .removeDuplicates(),
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
    }
}
