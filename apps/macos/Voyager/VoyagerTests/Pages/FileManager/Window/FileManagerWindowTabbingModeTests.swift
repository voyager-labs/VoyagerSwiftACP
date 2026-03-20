import AppKit
@testable import Voyager
import XCTest

@MainActor
final class WindowTabbingModeTests: XCTestCase {
    func testConfigureWindowStyleDisallowsTabbingForNewWindow() {
        let window = NSWindow()

        FileManagerWindowCoordinator.configureWindowStyle(window, tabbingMode: .disallowed)

        XCTAssertEqual(window.tabbingIdentifier, "file-manager")
        XCTAssertEqual(window.tabbingMode, .disallowed)
    }

    func testConfigureWindowStyleAllowsPreferredTabbingForNewTab() {
        let window = NSWindow()

        FileManagerWindowCoordinator.configureWindowStyle(window, tabbingMode: .preferred)

        XCTAssertEqual(window.tabbingIdentifier, "file-manager")
        XCTAssertEqual(window.tabbingMode, .preferred)
    }
}
