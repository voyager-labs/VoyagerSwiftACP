import AppKit
import Combine
import ComposableArchitecture
import SwiftUI

struct FileManagerWindowView: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSViewController(context _: Context) -> FileManagerWindowSplitController {
        FileManagerWindowSplitController(
            store: store,
            isDark: colorScheme == .dark,
        )
    }

    func updateNSViewController(_ nsViewController: FileManagerWindowSplitController, context: Context) {
        nsViewController.updateAppearance(isDark: colorScheme == .dark)
        context.coordinator.bindWindowIfNeeded(nsViewController.view.window)
    }

    static func dismantleNSViewController(
        _ nsViewController: FileManagerWindowSplitController,
        coordinator: Coordinator,
    ) {
        coordinator.tearDown()
        nsViewController.tearDown()
    }

    @MainActor
    final class Coordinator {
        private let store: StoreOf<FileManagerFeature>
        private let computerNameClient = FileManagerComputerNameClient.liveValue
        private var cancellables: Set<AnyCancellable> = []
        private weak var boundWindow: NSWindow?

        init(store: StoreOf<FileManagerFeature>) {
            self.store = store
        }

        func bindWindowIfNeeded(_ window: NSWindow?) {
            guard let window else { return }

            if boundWindow !== window {
                tearDown()
                boundWindow = window
                bindTitle(window: window)
                return
            }

            if cancellables.isEmpty {
                bindTitle(window: window)
            }
        }

        func tearDown() {
            cancellables.removeAll()
            boundWindow = nil
        }

        private func bindTitle(window: NSWindow) {
            let titleClient = computerNameClient
            let makeWindowTitle: (String) -> String = { path in
                if path == "/" {
                    return titleClient.computerName()
                }
                if path == titleClient.computerName() {
                    return path
                }
                return titleClient.displayNameAtPath(path)
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
                isCollectionMode: store.state.content.entries.isCollectionMode,
                titlePath: store.state.content.navigation.titlePath,
                makeWindowTitle: makeWindowTitle,
            )

            let titlePublisher = Publishers.CombineLatest3(
                store.publisher.content.collectionSession.openedName.removeDuplicates(),
                store.publisher.content.entries.isCollectionMode.removeDuplicates(),
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

            titlePublisher
                .sink { [weak window] title in
                    window?.title = title
                }
                .store(in: &cancellables)
        }
    }
}

extension FileManagerWindowView {
    static func makeWindow(
        store: StoreOf<FileManagerFeature>,
        path: String?,
        makeContentViewController: ((StoreOf<FileManagerFeature>, String?) -> NSViewController)?,
        initialWindowSizeProvider: (() -> NSSize?)?,
    ) -> NSWindow {
        let contentViewController: NSViewController
        if let makeContentViewController {
            contentViewController = makeContentViewController(store, path)
        } else {
            let hostingController = NSHostingController(rootView: FileManagerWindowView(store: store))
            hostingController.safeAreaRegions = []
            contentViewController = hostingController
        }

        let window = NSWindow(contentViewController: contentViewController)
        configureWindowStyle(window)
        applyInitialFrame(window, initialWindowSizeProvider: initialWindowSizeProvider)
        return window
    }

    private static func configureWindowStyle(_ window: NSWindow) {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.minSize = NSSize(width: 600, height: 350)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingIdentifier = "file-manager"
        window.tabbingMode = .preferred
    }

    private static func applyInitialFrame(
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
}
