@testable import Voyager
import XCTest

@MainActor
final class EntryRenameExtensionPolicyTests: XCTestCase {
    // MARK: - extensionTransition 테스트

    func testExtensionChanged() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report.md", isFolder: false,
        )
        XCTAssertEqual(transition, .changed)
    }

    func testExtensionRemoved() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report", isFolder: false,
        )
        XCTAssertEqual(transition, .removed)
    }

    func testExtensionAdded() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "README", to: "README.md", isFolder: false,
        )
        XCTAssertEqual(transition, .added)
    }

    func testSameExtensionNoTransition() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report.txt", isFolder: false,
        )
        XCTAssertEqual(transition, .none)
    }

    func testFolderAlwaysNone() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "folder.txt", to: "folder.md", isFolder: true,
        )
        XCTAssertEqual(transition, .none)
    }

    func testDotfileToDotfileBackupIsAdded() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: ".env", to: ".env.backup", isFolder: false,
        )
        XCTAssertEqual(transition, .added)
    }

    func testDotfileSameNameNoTransition() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: ".env", to: ".env", isFolder: false,
        )
        XCTAssertEqual(transition, .none)
    }

    func testMultiDotExtensionChange() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "archive.tar.gz", to: "archive.tar.zip", isFolder: false,
        )
        XCTAssertEqual(transition, .changed)
    }
}
