import AppKit
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowControllerTests: XCTestCase {
    func testUndoManagerIsUniquePerWindowController() throws {
        let firstController = FileManagerWindowController(
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
            registryClient: .testValue,
        )
        let secondController = FileManagerWindowController(
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
            registryClient: .testValue,
        )

        let firstWindow = try XCTUnwrap(firstController.window)
        let secondWindow = try XCTUnwrap(secondController.window)

        let firstUndoManager = try XCTUnwrap(firstController.windowWillReturnUndoManager(firstWindow))
        let secondUndoManager = try XCTUnwrap(secondController.windowWillReturnUndoManager(secondWindow))

        XCTAssertNotIdentical(firstUndoManager, secondUndoManager)
    }
}
