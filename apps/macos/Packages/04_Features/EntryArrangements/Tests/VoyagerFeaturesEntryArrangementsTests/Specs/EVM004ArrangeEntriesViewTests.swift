import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryArrangements
import XCTest

@MainActor
final class EVM004ArrangeEntriesViewTests: XCTestCase {
    // MARK: - EVM-004-sort_entries_by_property

    /// EVM-004-sort_entries_by_property: sort key 변경 시 상태 업데이트 및 재적용 요청
    /// 사용자가 정렬 기준을 변경하면 리듀서가 sortKey를 업데이트하고 delegate를 통해 재적용을 요청한다.
    /// - 검증 내용: setSortKey 액션이 sortKey 상태를 변경하고 .delegate(.requestApply)를 발생시키는지 확인
    /// - 사전 조건: 기본 초기 상태 (sortKey 기본값, sortOrder 기본값)
    /// - 기대 결과: sortKey가 .kind로 변경되고, sortOrder가 .ascending으로 리셋됨, requestApply 발생
    func testSetSortKeyChangesSortKeyAndRequestsApply() async {
        let store = makeEntryArrangementsStore()

        await store.send(.setSortKey(.kind)) {
            $0.sortKey = .kind
            $0.sortOrder = .ascending
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    /// EVM-004-sort_entries_by_property: 날짜 정렬 키 선택 시 기본 내림차순
    /// 사용자가 정렬 기준을 날짜로 변경하면 리듀서가 자동으로 내림차순으로 설정한다.
    /// - 검증 내용: setSortKey(.dateModified) 액션이 sortOrder를 .descending으로 기본 설정하는지 확인
    /// - 사전 조건: 기본 초기 상태
    /// - 기대 결과: sortKey가 .dateModified로 변경되고, sortOrder가 .descending으로 설정됨, requestApply 발생
    func testSetSortKeyDateDefaultsToDescending() async {
        let store = makeEntryArrangementsStore()

        await store.send(.setSortKey(.dateModified)) {
            $0.sortKey = .dateModified
            $0.sortOrder = .descending
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    /// EVM-004-sort_entries_by_property: 정렬 순서 직접 변경 시 hasUserSetSortOrder 마킹
    /// 사용자가 정렬 순서를 직접 변경하면 리듀서가 sortOrder를 업데이트하고 사용자 설정 플래그를 마킹한다.
    /// - 검증 내용: setSortOrder 액션이 sortOrder와 hasUserSetSortOrder를 함께 변경하는지 확인
    /// - 사전 조건: 기본 초기 상태 (hasUserSetSortOrder = false)
    /// - 기대 결과: sortOrder가 .descending으로 변경되고, hasUserSetSortOrder가 true로 설정됨, requestApply 발생
    func testSetSortOrderUpdatesOrderAndMarksUserSet() async {
        let store = makeEntryArrangementsStore()

        await store.send(.setSortOrder(.descending)) {
            $0.sortOrder = .descending
            $0.hasUserSetSortOrder = true
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    /// EVM-004-sort_entries_by_property: sort key 변경 시 사용자 설정 정렬 순서 보존
    /// 사용자가 이미 정렬 순서를 설정한 후 sort key를 변경하면 기존 sortOrder가 유지된다.
    /// - 검증 내용: setSortKey 변경 시 hasUserSetSortOrder가 true인 경우 sortOrder가 리셋되지 않는지 확인
    /// - 사전 조건: setSortOrder(.descending)으로 hasUserSetSortOrder = true 상태
    /// - 기대 결과: 이후 setSortKey(.kind)에서 sortOrder가 유지되고 sortKey만 .kind로 변경됨
    func testSetSortKeyPreservesUserSetSortOrder() async {
        let store = makeEntryArrangementsStore()

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

    /// EVM-004-sort_entries_by_property: 재적용 요청
    /// 사용자가 재적용 버튼을 누르면 리듀서가 상태 변경 없이 재적용을 요청한다.
    /// - 검증 내용: reapply 액션이 상태 변경 없이 .delegate(.requestApply)만 발생시키는지 확인
    /// - 사전 조건: 기본 초기 상태
    /// - 기대 결과: 상태 변경 없이 requestApply 발생
    func testReapplyRequestsApply() async {
        let store = makeEntryArrangementsStore()

        await store.send(.reapply)
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    /// EVM-004-sort_entries_by_property: extracted sibling sorter preserves flat arrangement semantics.
    /// hierarchy projection과 root arrangement가 동일 comparator를 공유하도록 public sorter seam을 검증한다.
    /// - 검증 내용: sibling sorter가 name ascending 입력을 existing arrangement와 동일하게 정렬한다.
    /// - 사전 조건: name order가 c, a, b인 flat sibling input과 name ascending configuration이다.
    /// - 기대 결과: sorter 결과가 a, b, c이며 reducer apply semantic과 일치한다.
    func testSiblingSorterPreservesFlatArrangementSemantics() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let itemC = makeEntry(fixedDate, "c", "/tmp/c", 3)
        let itemA = makeEntry(fixedDate, "a", "/tmp/a", 1)
        let itemB = makeEntry(fixedDate, "b", "/tmp/b", 2)

        let sorted = EntrySiblingSorter().sort(
            [itemC, itemA, itemB],
            by: .name,
            order: .ascending,
        )

        XCTAssertEqual(sorted.map(\.id), [itemA.id, itemB.id, itemC.id])
    }

    /// EVM-004-sort_entries_by_property: 이름 오름차순 정렬 적용
    /// 정렬 기준이 이름 오름차순일 때 apply 액션이 항목을 올바르게 정렬하여 groupedItems와 delegate에 전달한다.
    /// - 검증 내용: apply(items:isCollectionMode:) 액션이 sortKey=.name, sortOrder=.ascending에 따라 정렬하는지 확인
    /// - 사전 조건: initialState에 sortKey=.name, sortOrder=.ascending, groupKey=.none 설정, 3개 항목 (c, a, b 순서)
    /// - 기대 결과: groupedItems가 [a, b, c] 순서로 정렬되고, .delegate(.applied)가 정렬된 항목과 함께 발생
    func testApplySortsByNameAscending() async {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let itemC = makeEntry(fixedDate, "c", "/tmp/c", 3)
        let itemA = makeEntry(fixedDate, "a", "/tmp/a", 1)
        let itemB = makeEntry(fixedDate, "b", "/tmp/b", 2)

        let expectedSorted = [itemA, itemB, itemC]

        let store = makeEntryArrangementsStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .none,
            ),
            date: fixedDate,
        )

        await store.send(.apply(items: [itemC, itemA, itemB], isCollectionMode: false)) {
            $0.groupedItems = [GroupedItems(groupName: "", items: expectedSorted)]
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSorted, isCollectionMode: false)))
        await store.finish()
    }

    // MARK: - EVM-004-group_entries_by_property

    /// EVM-004-group_entries_by_property: 그룹 키 변경 시 상태 업데이트 및 재적용 요청
    /// 사용자가 그룹 기준을 변경하면 리듀서가 groupKey를 업데이트하고 재적용을 요청한다.
    /// - 검증 내용: setGroupKey(.kind) 액션이 groupKey를 .kind로 변경하고 .delegate(.requestApply)를 발생시키는지 확인
    /// - 사전 조건: 기본 초기 상태 (groupKey = .none)
    /// - 기대 결과: groupKey가 .kind로 변경되고, requestApply 발생
    func testSetGroupKeyChangesGroupKeyAndRequestsApply() async {
        let store = makeEntryArrangementsStore()

        await store.send(.setGroupKey(.kind)) {
            $0.groupKey = .kind
        }
        await store.receive(.delegate(.requestApply))
        await store.finish()
    }

    /// EVM-004-group_entries_by_property: 그룹 키를 none으로 변경 시 그룹핑 해제
    /// 사용자가 그룹 기준을 none으로 변경하면 기존 그룹핑이 해제된다.
    /// - 검증 내용: .kind → .none으로 setGroupKey 변경 시 groupKey가 올바르게 전이되는지 확인
    /// - 사전 조건: groupKey = .kind 상태에서 시작
    /// - 기대 결과: .kind 설정 후 .none으로 변경 시 groupKey가 .none으로 복원되고, 각각 requestApply 발생
    func testSetGroupKeyToNoneRemovesGrouping() async {
        let store = makeEntryArrangementsStore()

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

    /// EVM-004-group_entries_by_property: 그룹 접기/펼치기 토글
    /// 사용자가 그룹 헤더를 클릭하면 해당 그룹이 collapsedGroups에 추가되거나 제거된다.
    /// - 검증 내용: toggleCollapsedGroup 액션이 collapsedGroups Set에 요소를 추가/제거하는지 확인
    /// - 사전 조건: 기본 초기 상태 (collapsedGroups 빈 Set)
    /// - 기대 결과: 첫 번째 토글 시 "folder"가 추가되고, 두 번째 토글 시 제거됨
    func testToggleCollapsedGroupAddsAndRemoves() async {
        let store = makeEntryArrangementsStore()

        await store.send(.toggleCollapsedGroup("folder")) {
            $0.collapsedGroups.insert("folder")
        }

        await store.send(.toggleCollapsedGroup("folder")) {
            $0.collapsedGroups.remove("folder")
        }
        await store.finish()
    }

    /// EVM-004-group_entries_by_property: 종류별 그룹핑 적용 시 올바른 그룹 분류
    /// 정렬 기준이 이름 오름차순이고 그룹 기준이 종류일 때 apply가 항목을 종류별로 올바르게 그룹화한다.
    /// - 검증 내용: apply 액션이 groupKey=.kind에 따라 항목을 종류별 그룹으로 분류하고 정렬하는지 확인
    /// - 사전 조건: initialState에 sortKey=.name, sortOrder=.ascending, groupKey=.kind, Folder/Image/Text 종류 항목
    /// - 기대 결과: Folders, Image, Text 그룹으로 분류되고 그룹 내 항목이 이름순 정렬됨, .delegate(.applied) 발생
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

        let store = makeEntryArrangementsStore(
            initialState: EntryArrangementsState(
                sortKey: .name,
                sortOrder: .ascending,
                groupKey: .kind,
            ),
            date: fixedDate,
        )

        await store.send(.apply(items: [imageB, folder, text, imageA], isCollectionMode: false)) {
            $0.groupedItems = expectedGrouped
        }
        await store.receive(.delegate(.applied(sortedItems: expectedSorted, isCollectionMode: false)))
        await store.finish()
    }

    /// EVM-004-group_entries_by_property: kind 그룹 활성화 시 Other 엣지 케이스 포함 그룹 순서 검증
    /// kind가 공백/미확인인 항목이 "Other" 그룹으로 분류되는 불변 조건을 검증한다.
    /// - 검증 내용: apply가 groupKey=.kind에서 Folder/Image/Text/Other 순으로 그룹화하는지 확인
    /// - 사전 조건: sortKey=.name, sortOrder=.ascending, groupKey=.kind, Other 항목(kind="   ") 포함
    /// - 기대 결과: Folders, Image, Text, Other 그룹 순서로 분류됨
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

    /// EVM-004-group_entries_by_property: VOY-213 태그 그룹 colorCode 보존 회귀 검증
    /// 태그 그룹이 EntryArrangements의 colorCode를 GroupedItems에 올바르게 전달하는지 확인한다.
    /// - 검증 내용: apply가 groupKey=.tags에서 각 태그 그룹의 colorCode를 GroupedItems에 설정하는지 확인
    /// - 사전 조건: sortKey=.name, sortOrder=.ascending, groupKey=.tags, Blue(colorCode=6)/Red(colorCode=1) 태그
    /// - 기대 결과: Blue 그룹 colorCode=6, Red 그룹 colorCode=1, No Tags 그룹 colorCode=nil
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

    /// EVM-004-group_entries_by_property: VOY-213 동일 태그명 colorCode 안정성 회귀 검증
    /// 동일 태그명에 다른 colorCode가 있을 때 첫 번째 항목의 colorCode가 선택되는 안정성을 보장한다.
    /// - 검증 내용: 동일 태그명 "Blue"에 colorCode 6과 1이 있을 때 첫 항목의 colorCode(6)가 선택되는지 확인
    /// - 사전 조건: sortKey=.name, sortOrder=.ascending, groupKey=.tags, Blue 태그 두 개(각각 colorCode=6, 1)
    /// - 기대 결과: Blue 그룹의 colorCode가 6으로 설정됨
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

    /// EVM-004-group_entries_by_property: VOY-213 lastOpenedDate 누락 시 Earlier 폴백 회귀 검증
    /// lastOpenedDate가 nil인 항목이 "Earlier" 그룹으로 분류되는 날짜 폴백 동작을 보장한다.
    /// - 검증 내용: apply가 groupKey=.dateLastOpened에서 lastOpenedDate=nil인 항목을 "Earlier"로 분류하는지 확인
    /// - 사전 조건: sortKey=.name, sortOrder=.ascending, groupKey=.dateLastOpened, nil/오늘 lastOpenedDate 항목 혼합
    /// - 기대 결과: Today 그룹에 opened 항목, Earlier 그룹에 missing 항목 분류됨
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

    /// EVM-004-group_entries_by_property: VOY-213 태그/fallback 그룹명 가시성 회귀 검증
    /// 태그 그룹은 태그명을, 미분류 항목은 "No Tags"를 표시하는지 확인한다.
    /// - 검증 내용: apply가 groupKey=.tags에서 태그명과 "No Tags"를 groupName으로 설정하고 colorCode를 보존하는지 확인
    /// - 사전 조건: sortKey=.name, sortOrder=.ascending, groupKey=.tags, 태그있는 항목/태그없는 항목 혼합
    /// - 기대 결과: Blue(colorCode=6), No Tags(colorCode=nil) 그룹명과 colorCode 올바르게 설정됨
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
}
