import AppKit
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowControllerTests: XCTestCase {
    func testUndoManagerIsUniquePerWindowController() throws {
        let firstController = FileManagerWindowController(
            registryClient: .testValue,
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
        )
        let secondController = FileManagerWindowController(
            registryClient: .testValue,
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
        )

        let firstWindow = try XCTUnwrap(firstController.window)
        let secondWindow = try XCTUnwrap(secondController.window)

        let firstUndoManager = try XCTUnwrap(firstController.windowWillReturnUndoManager(firstWindow))
        let secondUndoManager = try XCTUnwrap(secondController.windowWillReturnUndoManager(secondWindow))

        XCTAssertNotIdentical(firstUndoManager, secondUndoManager)
    }

    func testWindowLifecycleClientReceivesEvents() {
        var didUpdateFocus = false
        var didUpdateMenu = false
        var didWindowWillClose = false

        let lifecycleClient = FileManagerWindowLifecycleClient(
            updateFocusHistory: { _ in didUpdateFocus = true },
            updateMenuState: { _ in didUpdateMenu = true },
            windowWillClose: { _ in didWindowWillClose = true },
            existingWindowSize: { nil },
        )

        let controller = FileManagerWindowController(
            registryClient: .testValue,
            asTab: true,
            windowLifecycleClient: lifecycleClient,
            makeContentViewController: { _, _ in NSViewController() },
        )

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        XCTAssertTrue(didUpdateFocus)
        XCTAssertTrue(didUpdateMenu)
        XCTAssertTrue(didWindowWillClose)
    }
}
