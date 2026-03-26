import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryContextMenuSemanticsTests: XCTestCase {
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

    private func makeEntry(name: String, fullPath: String, isFolder: Bool) -> EntryModel {
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
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
