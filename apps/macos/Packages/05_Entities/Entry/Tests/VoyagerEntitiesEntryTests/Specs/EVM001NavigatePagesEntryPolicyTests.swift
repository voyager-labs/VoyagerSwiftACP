import Foundation
import VoyagerEntitiesEntry
import XCTest

/// EVM-001-open_entry_double_click: `EntryModel.isDirectoryNavigationTarget` open/navigation 정책 진리표.
/// contract는 filesystem directory truth(`isFolder`)에서 package 디렉터리(`.app` 등)를 제외한
/// `isFolder && !isPackage`다. package 디렉터리는 탐색 대상이 아니며 `openFiles`(Launch Services)로 라우팅된다.
/// `.voycoll`은 routing 단계에서 collection heuristic이 이 판정에 앞서 `openCollectionFile`로 연다
/// (이 정책은 directory truth가 아니라 package 제외를 본다).
@MainActor
final class EVM001NavigatePagesEntryPolicyTests: XCTestCase {
    /// EVM-001-open_entry_double_click: ordinary directory는 navigation target이다.
    /// - 검증 내용: isFolder:true, isPackage:false directory가 isDirectoryNavigationTarget == true
    func testOrdinaryDirectoryIsNavigationTarget() {
        let entry = makeEntry(isFolder: true, isPackage: false, fileExtension: "")
        XCTAssertTrue(entry.isDirectoryNavigationTarget)
    }

    /// EVM-001-open_entry_double_click: `.app` package 디렉터리는 navigation target이 아니다.
    /// - 검증 내용: isFolder:true, isPackage:true, fileExtension:"app"이 isDirectoryNavigationTarget == false
    func testAppPackageDirectoryIsNotNavigationTarget() {
        let entry = makeEntry(isFolder: true, isPackage: true, fileExtension: "app")
        XCTAssertFalse(entry.isDirectoryNavigationTarget)
    }

    /// EVM-001-open_entry_double_click: `.voycoll` directory도 navigation policy상 package 제외로 false다.
    /// - 검증 내용: isFolder:true, isPackage:true, fileExtension:"voycoll"이 isDirectoryNavigationTarget == false.
    ///   policy는 package를 제외하며, 실제 `.voycoll` 오픈은 collection heuristic이 이 판정에 앞서
    ///   `openCollectionFile`로 라우팅한다(heuristic 선행으로 보장).
    func testVoycollDirectoryIsNotNavigationTargetByPackageExclusion() {
        let entry = makeEntry(isFolder: true, isPackage: true, fileExtension: "voycoll")
        XCTAssertFalse(entry.isDirectoryNavigationTarget)
    }

    /// EVM-001-open_entry_double_click: 일반 파일은 navigation target이 아니다.
    /// - 검증 내용: isFolder:false file이 isDirectoryNavigationTarget == false
    func testFileIsNotNavigationTarget() {
        let entry = makeEntry(isFolder: false, isPackage: false, fileExtension: "txt")
        XCTAssertFalse(entry.isDirectoryNavigationTarget)
    }

    private func makeEntry(
        isFolder: Bool,
        isPackage: Bool,
        fileExtension: String,
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1)
        return EntryModel(
            name: "entry.\(fileExtension)",
            fullPath: "/fixture/entry.\(fileExtension)",
            isFolder: isFolder,
            isHidden: false,
            size: 0,
            modifiedDate: date,
            fileExtension: fileExtension,
            facets: .init(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "File",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: isPackage,
        )
    }
}
