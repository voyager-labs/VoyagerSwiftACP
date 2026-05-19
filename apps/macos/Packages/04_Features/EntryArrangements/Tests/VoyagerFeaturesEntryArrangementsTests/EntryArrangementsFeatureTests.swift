import ComposableArchitecture
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryArrangements
import XCTest

@MainActor
final class EntryArrangementsFeatureTests: XCTestCase {
    /// 그룹 키가 없을 때 정렬된 항목이 하나의 그룹으로 묶여 delegate까지 전달되는지 검증
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

    /// kind 그룹이 활성화되면 폴더/이미지/텍스트/기타 순으로 그룹화되는지 검증
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

    /// VOY-213: tags 그룹이 태그 색상 코드를 함께 보존하는지 검증
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
                GroupedItems(groupName: "Blue", items: [itemA, itemB], colorCode: 6),
                GroupedItems(groupName: "Red", items: [itemB], colorCode: 1),
                GroupedItems(groupName: "No Tags", items: [itemC]),
            ]
        }
        await store.receive(.delegate(.applied(sortedItems: [itemA, itemB, itemC], isCollectionMode: false)))
        await store.finish()
    }

    /// VOY-213: 동일 태그 이름이 입력 순서와 무관하게 안정적인 색상 선택을 유지하는지 검증
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
                GroupedItems(groupName: "Blue", items: [second, first], colorCode: 6),
            ]
        }
        await store.receive(.delegate(.applied(sortedItems: [second, first], isCollectionMode: false)))
        await store.finish()
    }

    /// VOY-213: lastOpenedDate가 없으면 더 이른 그룹으로 폴백되는지 검증
    func testVOY213DateLastOpenedFallsBackToEarlierForMissingDates() async {
        let today = Date()
        let missing = makeEntry(
            today,
            "missing.txt",
            "/tmp/missing.txt",
            10,
            ext: "txt",
            kind: "Text",
            lastOpenedDate: nil,
        )
        let opened = makeEntry(
            today,
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
            $0.date = .constant(today)
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

    /// VOY-213: tags 그룹의 표시 이름과 fallback 그룹 이름이 사용자가 읽을 수 있게 유지되는지 검증
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

    // MARK: - 지속성 계약 회귀 테스트

    /// persistence key 문자열이 저장소 계약과 정확히 일치하는지 검증
    func testPersistenceKeyLiterals() {
        XCTAssertEqual(EntryArrangementsPersistenceKey.sortKey, "sortKey")
        XCTAssertEqual(EntryArrangementsPersistenceKey.sortOrder, "sortOrder")
        XCTAssertEqual(EntryArrangementsPersistenceKey.groupKey, "groupKey")
    }

    /// enum rawValue가 저장/복원 계약에 필요한 문자열을 유지하는지 검증
    func testSortKeyGroupKeySortOrderRawValues() {
        // SortKey 원시값: 정렬 기준 저장 문자열이 바뀌면 설정 복원이 깨진다.
        XCTAssertEqual(SortKey.application.rawValue, "Application")
        XCTAssertEqual(SortKey.tags.rawValue, "Tags")
        XCTAssertEqual(SortKey.name.rawValue, "name")
        XCTAssertEqual(SortKey.kind.rawValue, "kind")
        XCTAssertEqual(SortKey.size.rawValue, "size")

        // SortOrder 원시값: 오름/내림차순 계약이 그대로 유지되어야 한다.
        XCTAssertEqual(SortOrder.ascending.rawValue, "ascending")
        XCTAssertEqual(SortOrder.descending.rawValue, "descending")

        // GroupKey 원시값: 그룹 복원 시 사용자 표시 이름과 일치해야 한다.
        XCTAssertEqual(GroupKey.none.rawValue, "None")
        XCTAssertEqual(GroupKey.tags.rawValue, "Tags")
        XCTAssertEqual(GroupKey.name.rawValue, "Name")
        XCTAssertEqual(GroupKey.kind.rawValue, "Kind")
        XCTAssertEqual(GroupKey.application.rawValue, "Application")
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
