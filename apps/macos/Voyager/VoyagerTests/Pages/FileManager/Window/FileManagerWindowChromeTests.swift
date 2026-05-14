import AppKit
import @preconcurrency import Combine
import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowChromeTests: XCTestCase {
    func testTrafficLightsNotHiddenAfterBaseConfiguration() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    func testTrafficLightsVisibleWhenSidebarVisible() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window, isSidebarVisible: true)
        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    func testTrafficLightsHiddenWhenSidebarHidden() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window, isSidebarVisible: false)
        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden ?? false)
    }

    func testTitleBarStyleIsConfiguredCorrectly() {
        let contentViewController = NSViewController()
        let window = NSWindow(contentViewController: contentViewController)
        FileManagerWindowCoordinator.configureWindowStyle(window)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
    }

    // MARK: - FileManagerWindowChrome direct forwarding

    func testChromeConfigureWindowStyleMatchesCoordinatorForwarding() {
        let window1 = NSWindow(contentViewController: NSViewController())
        let window2 = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.configureWindowStyle(window1)
        FileManagerWindowCoordinator.configureWindowStyle(window2)

        XCTAssertEqual(window1.styleMask, window2.styleMask)
        XCTAssertEqual(window1.minSize, window2.minSize)
        XCTAssertEqual(window1.titleVisibility, window2.titleVisibility)
        XCTAssertEqual(window1.titlebarAppearsTransparent, window2.titlebarAppearsTransparent)
        XCTAssertEqual(window1.isMovableByWindowBackground, window2.isMovableByWindowBackground)
        XCTAssertEqual(window1.tabbingIdentifier, window2.tabbingIdentifier)
    }

    func testChromeApplyTrafficLightVisibilityMatchesCoordinatorForwarding() {
        let window1 = NSWindow(contentViewController: NSViewController())
        let window2 = NSWindow(contentViewController: NSViewController())

        FileManagerWindowChrome.applyTrafficLightVisibility(to: window1, isSidebarVisible: false)
        FileManagerWindowCoordinator.applyTrafficLightVisibility(to: window2, isSidebarVisible: false)

        XCTAssertEqual(
            window1.standardWindowButton(.closeButton)?.isHidden,
            window2.standardWindowButton(.closeButton)?.isHidden,
        )
        XCTAssertEqual(
            window1.standardWindowButton(.miniaturizeButton)?.isHidden,
            window2.standardWindowButton(.miniaturizeButton)?.isHidden,
        )
        XCTAssertEqual(
            window1.standardWindowButton(.zoomButton)?.isHidden,
            window2.standardWindowButton(.zoomButton)?.isHidden,
        )
    }

    // MARK: - FileManagerWindowChrome.makeTitle

    func testChromeMakeTitleReturnsCollectionNameWhenPresent() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: "My Collection",
            isCollectionMode: false,
            titlePath: "/Users/test",
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "My Collection")
    }

    func testChromeMakeTitleReturnsNewCollectionWhenCollectionMode() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: true,
            titlePath: "/Users/test",
            makeWindowTitle: { $0 },
        )
        XCTAssertEqual(title, "New Collection")
    }

    func testChromeMakeTitleReturnsWindowTitleForFolderPath() {
        let title = FileManagerWindowChrome.makeTitle(
            openedCollectionName: nil,
            isCollectionMode: false,
            titlePath: "/Users/test/Documents",
            makeWindowTitle: { "Display: \($0)" },
        )
        XCTAssertEqual(title, "Display: /Users/test/Documents")
    }

    // MARK: - FileManagerContentChromePropsBuilder

    func testContentChromePropsBuilderProducesComputerName() {
        let state = FileManagerFeature.State()
        let props = FileManagerContentChromePropsBuilder.makeContentChromeProps(
            from: state,
            fileManagerClient: .previewValue,
        )
        XCTAssertFalse(props.computerName.isEmpty)
    }

    func testContentOverlayPropsBuilderReflectsComposerState() {
        var state = FileManagerFeature.State()
        state.content.composer.isPresented = true
        let props = FileManagerContentChromePropsBuilder.makeContentOverlayProps(from: state)
        XCTAssertTrue(props.isComposerPresented)
    }

    func testContentOverlayPropsBuilderDefaultNoComposer() {
        let state = FileManagerFeature.State()
        let props = FileManagerContentChromePropsBuilder.makeContentOverlayProps(from: state)
        XCTAssertFalse(props.isComposerPresented)
    }

    // MARK: - FileManagerSidebarSync

    func testSidebarSyncClampsInitialWidth() {
        let sync = FileManagerSidebarSync(storeSidebarWidth: 500)
        XCTAssertLessThanOrEqual(sync.currentSidebarWidth, sync.sidebarMaxWidth)
    }

    func testSidebarSyncClampsBelowMinWidth() {
        let sync = FileManagerSidebarSync(storeSidebarWidth: 10)
        XCTAssertGreaterThanOrEqual(sync.currentSidebarWidth, sync.sidebarMinWidth)
    }
}
