import AppKit
import ComposableArchitecture
@testable import VoyagerPagesFileManager
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
}
