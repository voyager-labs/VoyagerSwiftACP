import AppKit
@testable import Voyager
import XCTest

@MainActor
final class WindowTabbingModeTests: XCTestCase {
    func testConfigureWindowStyleUsesConsistentTabbingMode() {
        let window = NSWindow()

        FileManagerWindowCoordinator.configureWindowStyle(window)

        XCTAssertEqual(window.tabbingIdentifier, "file-manager")
        XCTAssertEqual(window.tabbingMode, .preferred)
    }
}
