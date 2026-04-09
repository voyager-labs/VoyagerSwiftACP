import Foundation

import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
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

    func testVOY213TagsGroupingCarriesColorCodeFromEntryArrangements() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let blueTag = Tag(name: "Blue", colorCode: 6)
        let redTag = Tag(name: "Red", colorCode: 1)

        let itemA = makeEntry(fixedDate, "a.txt", "/tmp/a.txt", 10, ext: "txt", kind: "Text", tags: [blueTag])
        let itemB = makeEntry(fixedDate, "b.txt", "/tmp/b.txt", 20, ext: "txt", kind: "Text", tags: [redTag, blueTag])
        let itemC = makeEntry(fixedDate, "c.txt", "/tmp/c.txt", 30, ext: "txt", kind: "Text", tags: nil)

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .tags,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [itemC, itemB, itemA], isCollectionMode: false)) {
            $0.groupedItems = [
                GroupedItems(groupName: "Red", items: [itemB], colorCode: 1),
                GroupedItems(groupName: "Blue", items: [itemA, itemB], colorCode: 6),
                GroupedItems(groupName: "No Tags", items: [itemC]),
            ]
        }
        await store.receive(.delegate(.applied(sortedItems: [itemA, itemB, itemC], isCollectionMode: false)))
        await store.finish()
    }

    func testVOY213TagColorSelectionIsStableAcrossInputOrder() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let lowPriorityBlue = Tag(name: "Blue", colorCode: 6)
        let highPriorityBlue = Tag(name: "Blue", colorCode: 1)

        let first = makeEntry(fixedDate, "z.txt", "/tmp/z.txt", 10, ext: "txt", kind: "Text", tags: [lowPriorityBlue])
        let second = makeEntry(fixedDate, "a.txt", "/tmp/a.txt", 20, ext: "txt", kind: "Text", tags: [highPriorityBlue])

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .tags,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [first, second], isCollectionMode: false)) {
            $0.groupedItems = [
                GroupedItems(groupName: "Blue", items: [second, first], colorCode: 1),
            ]
        }
        await store.receive(.delegate(.applied(sortedItems: [second, first], isCollectionMode: false)))
        await store.finish()
    }

    func testVOY213DateLastOpenedFallsBackToEarlierForMissingDates() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let today = fixedDate
        let missing = makeEntry(
            fixedDate,
            "missing.txt",
            "/tmp/missing.txt",
            10,
            ext: "txt",
            kind: "Text",
            lastOpenedDate: nil,
        )
        let opened = makeEntry(
            fixedDate,
            "opened.txt",
            "/tmp/opened.txt",
            20,
            ext: "txt",
            kind: "Text",
            lastOpenedDate: today,
        )

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .dateLastOpened,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [missing, opened], isCollectionMode: false)) {
            $0.groupedItems = [
                GroupedItems(groupName: "Today", items: [opened]),
                GroupedItems(groupName: "Earlier", items: [missing]),
            ]
        }
        await store.receive(.delegate(.applied(sortedItems: [missing, opened], isCollectionMode: false)))
        await store.finish()
    }

    func testVOY213GroupedItemsKeepVisibleTitlesForTagAndFallbackGroups() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let blueTag = Tag(name: "Blue", colorCode: 6)
        let tagged = makeEntry(
            fixedDate,
            "tagged.txt",
            "/tmp/tagged.txt",
            10,
            ext: "txt",
            kind: "Text",
            tags: [blueTag],
        )
        let noTag = makeEntry(fixedDate, "untagged.txt", "/tmp/untagged.txt", 20, ext: "txt", kind: "Text", tags: nil)

        let store = TestStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .tags,
            ),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
        }

        await store.send(.apply(items: [tagged, noTag], isCollectionMode: false)) {
            $0.groupedItems = [
                GroupedItems(groupName: "Blue", items: [tagged], colorCode: 6),
                GroupedItems(groupName: "No Tags", items: [noTag]),
            ]
        }
        XCTAssertEqual(store.state.groupedItems.map(\.groupName), ["Blue", "No Tags"])
        XCTAssertEqual(store.state.groupedItems.map(\.colorCode), [6, nil])
        await store.receive(.delegate(.applied(sortedItems: [tagged, noTag], isCollectionMode: false)))
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
        tags: [Tag]? = nil,
        lastOpenedDate: Date? = nil,
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
                lastOpenedDate: lastOpenedDate,
                kind: kind,
                creatorApplication: nil,
                tags: tags,
                supplementaryMetadata: nil,
            ),
        )
    }
}
