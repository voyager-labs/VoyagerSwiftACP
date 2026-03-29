import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowChromeTests: XCTestCase {
    func testTrafficLightsAreVisibleAfterConfiguration() {
        let window = NSWindow(contentViewController: nil)

        FileManagerWindowCoordinator.configureWindowStyle(window)

        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(window.standardWindowButton(.zoomButton))

        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true, "Close button should not be hidden")
        XCTAssertFalse(
            window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true,
            "Miniaturize button should not be hidden",
        )
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true, "Zoom button should not be hidden")
    }

    func testTitleBarStyleIsConfiguredCorrectly() {
        let window = NSWindow(contentViewController: nil)

        FileManagerWindowCoordinator.configureWindowStyle(window)

        XCTAssertEqual(window.titleVisibility, .hidden, "Title visibility should be hidden")
        XCTAssertTrue(window.titlebarAppearsTransparent, "Title bar should appear transparent")
    }
}
