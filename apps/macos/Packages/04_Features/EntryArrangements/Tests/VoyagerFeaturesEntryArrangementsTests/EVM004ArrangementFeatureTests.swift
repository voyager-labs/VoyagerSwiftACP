import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryArrangements
import XCTest

// MARK: - EVM-004 Arrangement (Sort / Group) AC Coverage

@MainActor
final class EVM004ArrangementFeatureTests: XCTestCase {
    // MARK: - EVM-004-sort_entries_by_property

    func testSetSortKeyChangesSortKeyAndRequestsApply() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setSortKey(.kind)) {
            $0.sortKey = .kind
            $0.sortOrder = .ascending
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testSetSortKeyDateDefaultsToDescending() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setSortKey(.dateModified)) {
            $0.sortKey = .dateModified
            $0.sortOrder = .descending
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testSetSortOrderUpdatesOrderAndMarksUserSet() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setSortOrder(.descending)) {
            $0.sortOrder = .descending
            $0.hasUserSetSortOrder = true
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testSetSortKeyPreservesUserSetSortOrder() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setSortOrder(.descending)) {
            $0.sortOrder = .descending
            $0.hasUserSetSortOrder = true
        }
        await store.receive(.delegate(.requestApply))

        await store.send(.setSortKey(.kind)) {
            $0.sortKey = .kind
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testReapplyRequestsApply() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.reapply)
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    // MARK: - EVM-004-group_entries_by_property

    func testSetGroupKeyChangesGroupKeyAndRequestsApply() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setGroupKey(.kind)) {
            $0.groupKey = .kind
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testSetGroupKeyToNoneRemovesGrouping() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.setGroupKey(.kind)) {
            $0.groupKey = .kind
        }
        await store.receive(.delegate(.requestApply))

        await store.send(.setGroupKey(.none)) {
            $0.groupKey = .none
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    func testToggleCollapsedGroupAddsAndRemoves() async {
        let store = TestStore(
            initialState: EntryArrangementsState(),
        ) {
            EntryArrangementsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        }

        await store.send(.toggleCollapsedGroup("folder")) {
            $0.collapsedGroups.insert("folder")
        }

        await store.send(.toggleCollapsedGroup("folder")) {
            $0.collapsedGroups.remove("folder")
        }
        await store.finish()
    }

    // MARK: - EVM-004-sort + apply 통합

    func testApplySortsByNameAscending() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let itemC = makeEntry(fixedDate, "c", "/tmp/c", 3)
        let itemA = makeEntry(fixedDate, "a", "/tmp/a", 1)
        let itemB = makeEntry(fixedDate, "b", "/tmp/b", 2)

        let expectedSorted = [itemA, itemB, itemC]

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

        await store.send(.apply(items: [itemC, itemA, itemB], isCollectionMode: false)) {
            $0.groupedItems = [GroupedItems(groupName: "", items: expectedSorted)]
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSorted, isCollectionMode: false)))
        await store.finish()
    }

    // MARK: - EVM-004-group + apply 통합

    func testApplyGroupByKindGroupsCorrectly() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let folder = makeEntry(fixedDate, "Zoo", "/tmp/Zoo", dir: true, kind: "Folder")
        let imageB = makeEntry(fixedDate, "b.png", "/tmp/b.png", 20, ext: "png", kind: "Image")
        let imageA = makeEntry(fixedDate, "a.png", "/tmp/a.png", 10, ext: "png", kind: "Image")
        let text = makeEntry(fixedDate, "c.txt", "/tmp/c.txt", 30, ext: "txt", kind: "Text")

        let expectedSorted = [imageA, imageB, text, folder]
        let expectedGrouped: [GroupedItems] = [
            GroupedItems(groupName: "Folders", items: [folder]),
            GroupedItems(groupName: "Image", items: [imageA, imageB]),
            GroupedItems(groupName: "Text", items: [text]),
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

        await store.send(.apply(items: [imageB, folder, text, imageA], isCollectionMode: false)) {
            $0.groupedItems = expectedGrouped
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSorted, isCollectionMode: false)))
        await store.finish()
    }
}

// MARK: - Test Helpers

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
