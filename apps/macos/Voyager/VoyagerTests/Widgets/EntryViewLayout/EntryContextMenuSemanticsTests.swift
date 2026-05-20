import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import XCTest

@MainActor
/// 정렬/헤더/메뉴 동작 회귀를 검증하는 테스트 모음이다.
final class EntryContextMenuSemanticsTests: XCTestCase {
    /// 선택 상태 전환 경계를 검증해 회귀를 방지한다.
    func testBlankSpaceWithoutSelectionUsesContainerSelectionCountZero() {
        let selected = Set<EntryModel.ID>()
        let selectedEntries: [EntryModel] = []

        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: selected,
            selectedEntries: selectedEntries,
            rowEntry: nil,
            isTrashFolder: false,
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )

        XCTAssertEqual(spec.selectedCount, 0)
        XCTAssertNil(spec.rowEntryPathForOpenInNewTab)
    }

    /// 선택 상태 전환 경계를 검증해 회귀를 방지한다.
    func testUnselectedRowWithoutSelectionUsesRowAsSingleSelection() {
        let rowEntry = makeEntry(name: "Folder", fullPath: "/tmp/folder", isFolder: true)

        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [],
            selectedEntries: [rowEntry],
            rowEntry: rowEntry,
            isTrashFolder: false,
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )

        XCTAssertEqual(spec.selectedCount, 1)
        XCTAssertEqual(spec.rowEntryPathForOpenInNewTab, "/tmp/folder")
    }

    /// 선택 상태 전환 경계를 검증해 회귀를 방지한다.
    func testSelectedSetKeepsActualSelectionCountEvenWithRowEntry() {
        let rowEntry = makeEntry(name: "Folder", fullPath: "/tmp/folder", isFolder: true)
        let another = makeEntry(name: "File", fullPath: "/tmp/file.txt", isFolder: false)
        let selectedIds: Set<EntryModel.ID> = [rowEntry.id, another.id]

        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: selectedIds,
            selectedEntries: [rowEntry, another],
            rowEntry: rowEntry,
            isTrashFolder: false,
            canPaste: false,
            favoriteTags: [],
            openWithApplications: [],
        )

        XCTAssertEqual(spec.selectedCount, 2)
        XCTAssertEqual(spec.rowEntryPathForOpenInNewTab, "/tmp/folder")
    }

    /// 선택 상태 전환 경계를 검증해 회귀를 방지한다.
    func testTagMenuPrefersFavoriteColorWhenSelectedEntryTagColorIsNeutral() {
        let selectedEntry = makeEntry(
            name: "Tagged.txt",
            fullPath: "/tmp/tagged.txt",
            isFolder: false,
            tags: [Tag(name: "Orange", colorCode: 0)],
        )
        let favoriteTags = [Tag(name: "Orange", colorCode: 7)]

        let spec = EntryContextMenuSpecFactory.make(
            selectedIds: [selectedEntry.id],
            selectedEntries: [selectedEntry],
            rowEntry: selectedEntry,
            isTrashFolder: false,
            canPaste: false,
            favoriteTags: favoriteTags,
            openWithApplications: [],
        )

        XCTAssertEqual(spec.tags.first?.name, "Orange")
        XCTAssertEqual(spec.tags.first?.colorCode, 7)
    }

    private func makeEntry(name: String, fullPath: String, isFolder: Bool, tags: [Tag]? = nil) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: isFolder ? "" : "txt",
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Text",
                creatorApplication: nil,
                tags: tags,
                supplementaryMetadata: nil,
            ),
        )
    }
}
