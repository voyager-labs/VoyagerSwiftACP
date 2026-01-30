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

    func testContentViewControllerFactoryReceivesPath() {
        let path = "/tmp"
        var capturedPath: String?
        var didReceiveStore = false

        _ = FileManagerWindowController(
            registryClient: .testValue,
            path: path,
            asTab: true,
            makeContentViewController: { _, path in
                didReceiveStore = true
                capturedPath = path
                return NSViewController()
            },
        )

        XCTAssertTrue(didReceiveStore)
        XCTAssertEqual(capturedPath, path)
    }

    func testWindowTitleUsesPathWhenProvided() throws {
        let path = "/tmp"
        let controller = FileManagerWindowController(
            registryClient: .testValue,
            path: path,
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
        )

        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.title, FileManagerFeature.makeWindowTitle(for: path))
    }

    func testTabbingModeRespectsConfiguration() throws {
        let tabController = FileManagerWindowController(
            registryClient: .testValue,
            asTab: true,
            makeContentViewController: { _, _ in NSViewController() },
        )
        let tabWindow = try XCTUnwrap(tabController.window)
        XCTAssertEqual(tabWindow.tabbingMode, .preferred)
        XCTAssertEqual(tabWindow.tabbingIdentifier, "file-manager")

        let windowController = FileManagerWindowController(
            registryClient: .testValue,
            asTab: false,
            makeContentViewController: { _, _ in NSViewController() },
        )
        let window = try XCTUnwrap(windowController.window)
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertNotEqual(window.tabbingIdentifier, "file-manager")
    }
}
