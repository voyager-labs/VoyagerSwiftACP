@testable import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class EntryRenameExtensionPolicyTests: XCTestCase {
    // MARK: - extensionTransition 테스트

    /// 확장자가 바뀌면 changed로 분류되는지 검증
    func testExtensionChanged() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report.md", isFolder: false,
        )
        XCTAssertEqual(transition, .changed)
    }

    /// 확장자가 제거되면 removed로 분류되는지 검증
    func testExtensionRemoved() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report", isFolder: false,
        )
        XCTAssertEqual(transition, .removed)
    }

    /// 확장자가 새로 붙으면 added로 분류되는지 검증
    func testExtensionAdded() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "README", to: "README.md", isFolder: false,
        )
        XCTAssertEqual(transition, .added)
    }

    /// 동일 확장자는 변경 없음으로 처리되는지 검증
    func testSameExtensionNoTransition() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "report.txt", to: "report.txt", isFolder: false,
        )
        XCTAssertEqual(transition, .none)
    }

    /// 폴더는 확장자 변경 정책을 적용하지 않는지 검증
    func testFolderAlwaysNone() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "folder.txt", to: "folder.md", isFolder: true,
        )
        XCTAssertEqual(transition, .none)
    }

    /// dotfile에서 백업 확장자가 붙는 경우 added로 분류되는지 검증
    func testDotfileToDotfileBackupIsAdded() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: ".env", to: ".env.backup", isFolder: false,
        )
        XCTAssertEqual(transition, .added)
    }

    /// dotfile 동일 이름은 변경 없음으로 유지되는지 검증
    func testDotfileSameNameNoTransition() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: ".env", to: ".env", isFolder: false,
        )
        XCTAssertEqual(transition, .none)
    }

    /// 다중 확장자 파일의 마지막 확장자만 비교되는지 검증
    func testMultiDotExtensionChange() {
        let transition = EntryRenameExtensionPolicy.extensionTransition(
            from: "archive.tar.gz", to: "archive.tar.zip", isFolder: false,
        )
        XCTAssertEqual(transition, .changed)
    }
}
