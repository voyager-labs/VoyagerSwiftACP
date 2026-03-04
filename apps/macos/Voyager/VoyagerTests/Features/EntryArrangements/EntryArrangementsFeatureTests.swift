import Foundation

import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class EntryArrangementsFeatureTests: XCTestCase {
    func testApply_sortsAndUpdatesGroupedItems_whenGroupKeyNone() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let itemB = makeEntry(fixedDate, "b", "/tmp/b", 2)
        let itemA = makeEntry(fixedDate, "a", "/tmp/a", 1)
        let itemC = makeEntry(fixedDate, "c", "/tmp/c", 3)

        let expectedSortedItems = [itemA, itemB, itemC]

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .none,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [itemB, itemC, itemA], isCollectionMode: false)) {
            $0.groupedItems = [GroupedItems(groupName: "", items: expectedSortedItems)]
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSortedItems, isCollectionMode: false)))
        await store.finish()
    }

    func testApply_groupsByKind_andKeepsGroupOrderingSemantics() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let folder = makeEntry(fixedDate, "Zoo", "/tmp/Zoo", dir: true, kind: "Folder")
        let imageB = makeEntry(fixedDate, "b.png", "/tmp/b.png", 20, ext: "png", kind: "Image")
        let imageA = makeEntry(fixedDate, "a.png", "/tmp/a.png", 10, ext: "png", kind: "Image")
        let text = makeEntry(fixedDate, "c.txt", "/tmp/c.txt", 30, ext: "txt", kind: "Text")
        let other = makeEntry(fixedDate, "d", "/tmp/d", 40, ext: "bin", kind: "   ")

        let expectedSortedItems = [imageA, imageB, text, other, folder]
        let expectedGroupedItems: [GroupedItems] = [
            GroupedItems(groupName: "Folders", items: [folder]),
            GroupedItems(groupName: "Image", items: [imageA, imageB]),
            GroupedItems(groupName: "Text", items: [text]),
            GroupedItems(groupName: "Other", items: [other]),
        ]

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .kind,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [other, imageB, folder, text, imageA], isCollectionMode: true)) {
            $0.groupedItems = expectedGroupedItems
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSortedItems, isCollectionMode: true)))
        await store.finish()
    }

    private func makeEntry(
        _ date: Date,
        _ name: String,
        _ fullPath: String,
        _ size: Int64 = 0,
        dir: Bool = false,
        ext: String = "",
        kind: String = "",
    ) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: dir,
            isHidden: false,
            size: size,
            modifiedDate: date,
            fileExtension: ext,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: kind,
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}
