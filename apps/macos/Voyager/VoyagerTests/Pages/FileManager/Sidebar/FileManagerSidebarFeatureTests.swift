import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

// MARK: - VOY-201 작업 5: 사이드바 로컬 가드레일 테스트

// 이 테스트들은 사이드바 너비 클램프 및 복원 선택 정리를 위한 사이드바 로컬 소유 동작을 고정합니다.
// 사이드바 로컬 범주의 회귀 가드레일만 검증합니다.
// 미검증: 상위 네비게이션/콘텐츠 라우팅, delegate 마이그레이션(작업 4에서 처리).

@MainActor
final class FileManagerSidebarFeatureTests: XCTestCase {
    // MARK: - 너비 클램프 테스트

    /// 사이드바 너비가 최소값 미만일 때 하한값(150)으로 클램프되는지 검증
    /// 가드레일: 150 미만 값은 150으로 클램프되어야 함.
    func testSetSidebarWidth_ClampsToLowerBound() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 최소값 미만 너비(100) 전송: 150으로 클램프 예상
        await store.send(.view(.setSidebarWidth(100))) { state in
            state.sidebarWidth = 150
        }

        await store.finish()
    }

    /// 사이드바 너비가 최대값 초과 시 상한값(400)으로 클램프되는지 검증
    /// 가드레일: 400 초과 값은 400으로 클램프되어야 함.
    func testSetSidebarWidth_ClampsToUpperBound() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 최대값 초과 너비(500) 전송: 400으로 클램프 예상
        await store.send(.view(.setSidebarWidth(500))) { state in
            state.sidebarWidth = 400
        }

        await store.finish()
    }

    /// 현재 값에서 0.5 이내 변화는 무시되는지(상태 변경 없음) 검증
    /// 가드레일: 임계값 미만 변경은 조기 반환되어 불필요한 상태 변경을 방지.
    func testSetSidebarWidth_IgnoresSmallChanges() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 현재 값(220.3)에서 0.5 이내 너비 전송: 상태 변경 없음 예상
        await store.send(.view(.setSidebarWidth(220.3)))

        await store.finish()
    }

    /// 허용 범위 내의 유효한 너비가 유지되는지 검증
    /// 가드레일: 150...400 범위 값은 유지됨.
    func testSetSidebarWidth_PreservesValidWidth() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarWidth = 220

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 유효한 너비(300) 전송: 상태 변경 예상
        await store.send(.view(.setSidebarWidth(300))) { state in
            state.sidebarWidth = 300
        }

        await store.finish()
    }

    // MARK: - 복원 선택 테스트

    /// restoreSidebarSelection이 복원 후 pending 플래그를 해제하는지 검증
    /// 가드레일: 복원 액션 이후 pendingSidebarSelectionRestore는 nil이어야 함.
    func testRestoreSidebarSelection_ClearsPendingRestore() async {
        var initialState = FileManagerSidebarState()
        initialState.pendingSidebarSelectionRestore = "favorite:/Users/test"

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 복원 액션 전송, 상태 변경 예상
        await store.send(.internal(.restoreSidebarSelection)) { state in
            state.selectedSidebarItem = "favorite:/Users/test"
            state.pendingSidebarSelectionRestore = nil
        }

        await store.finish()
    }

    /// pending이 nil일 때 restoreSidebarSelection이 아무 동작도 하지 않음을 검증
    /// 가드레일: pending이 nil일 때 충돌이나 예기치 않은 상태 변경이 없어야 함.
    func testRestoreSidebarSelection_DoesNothingWhenPendingIsNil() async {
        let initialState = FileManagerSidebarState()

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // pending이 nil일 때 복원 액션 전송, 상태 변경 없음 예상
        await store.send(.internal(.restoreSidebarSelection))

        await store.finish()
    }

    /// pending이 nil일 때 기존 선택이 보존되는지 검증
    /// 가드레일: pending이 nil일 때 기존 selectedSidebarItem은 덮어쓰면 안 됨.
    func testRestoreSidebarSelection_PreservesExistingSelectionWhenPendingIsNil() async {
        var initialState = FileManagerSidebarState()
        initialState.selectedSidebarItem = "location:/Applications"
        initialState.pendingSidebarSelectionRestore = nil

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // pending이 nil일 때 복원 액션 전송, 상태 변경 없음 예상
        await store.send(.internal(.restoreSidebarSelection))

        await store.finish()
    }

    // MARK: - 태그 로딩 테스트 (VOY-208 작업 1)

    /// loadTags 액션이 클라이언트의 favoriteTags로 state.tags를 업데이트하는지 검증
    /// 기대: loadTags → tagsLoaded → state.tags 업데이트
    func testLoadTags_UpdatesStateWithFavoriteTags() async {
        let initialState = FileManagerSidebarState()

        // 색상 코드가 있는 특정 태그를 반환하도록 favoriteTags를 모킹
        let expectedTags = [
            Tag(name: "Important", colorCode: 1),
            Tag(name: "Work", colorCode: 6),
            Tag(name: "Personal", colorCode: 5),
        ]
        let expectedTagNames = expectedTags.map { tag in tag.name }

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { expectedTagNames },
                favoriteTags: { expectedTags },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // loadTags가 favoriteTags() 결과로 tagsLoaded를 동기적으로 트리거
        await store.send(.internal(.loadTags)) { state in
            state.tags = expectedTags
        }

        await store.finish()
    }

    /// favoriteTags가 비어 있을 때 loadTags 결과가 빈 state.tags가 되는지 검증
    /// 기대: 빈 태그 → state.tags = []
    func testLoadTags_WithEmptyFavoriteTags_SetsEmptyTags() async {
        let initialState = FileManagerSidebarState()

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { [] },
                favoriteTags: { [] },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.loadTags)) { state in
            state.tags = []
        }

        await store.finish()
    }

    /// loadTags가 favoriteTags 클라이언트의 색상 코드를 보존하는지 검증
    /// 기대: 색상 코드가 있는 태그가 정확히 보존됨
    func testLoadTags_PreservesColorCodes() async {
        let initialState = FileManagerSidebarState()

        // TagColor.rawValue: Red=6, Orange=7, Yellow=5, Green=2, Blue=4, Purple=3, Gray=1
        let expectedTags = [
            Tag(name: "Red", colorCode: 6),
            Tag(name: "Orange", colorCode: 7),
            Tag(name: "Yellow", colorCode: 5),
            Tag(name: "Green", colorCode: 2),
            Tag(name: "Blue", colorCode: 4),
            Tag(name: "Purple", colorCode: 3),
            Tag(name: "Gray", colorCode: 1),
        ]
        let expectedTagNames = expectedTags.map { tag in tag.name }

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = FinderFavoritesTagClient(
                favoriteTagNames: { expectedTagNames },
                favoriteTags: { expectedTags },
            )
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.loadTags)) { state in
            state.tags = expectedTags
            // 색상 코드가 보존되었는지 확인
            XCTAssertEqual(state.tags.map(\.colorCode), [6, 7, 5, 2, 4, 3, 1])
        }

        await store.finish()
    }

    /// tagsLoaded 액션이 state.tags를 직접 설정하는지 검증
    /// 기대: tagsLoaded(태그 배열) → state.tags = tags
    func testTagsLoaded_SetsStateTags() async {
        var initialState = FileManagerSidebarState()
        initialState.tags = [Tag(name: "Old", colorCode: 0)]

        let newTags = [
            Tag(name: "New1", colorCode: 3),
            Tag(name: "New2", colorCode: 4),
        ]

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.tagsLoaded(newTags))) { state in
            state.tags = newTags
        }

        await store.finish()
    }

    // MARK: - 시임 분리 테스트 (VOY-335 작업 2)

    /// 선호도(Preference) 시임이 선호도 필드에만 영향을 주는지 확인
    /// .view(.setSidebarVisible(false))를 전송하고 sidebarVisible만 변경되는지 확인
    func testPreferenceSeamOnlyAffectsPreferenceFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true
        initialState.sidebarWidth = 220
        initialState.favorites = [
            SidebarItems.FavoriteItem(
                name: "Test",
                url: URL(fileURLWithPath: "/Test"),
                iconName: "folder",
            ),
        ]
        initialState.contextMenuTargetId = "some-id"
        initialState.contextMenuTargetWasSelected = true

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.view(.setSidebarVisible(false))) { state in
            state.sidebarVisible = false
            XCTAssertEqual(state.sidebarWidth, 220)
            XCTAssertEqual(state.favorites.count, 1)
            XCTAssertEqual(state.contextMenuTargetId, "some-id")
            XCTAssertTrue(state.contextMenuTargetWasSelected)
        }

        await store.finish()
    }

    /// 소스 로딩 시임이 소스 필드에만 영향을 주는지 확인
    /// .internal(.favoritesLoaded)를 전송하고 favorites만 변경되는지 확인
    func testSourceLoadingSeamOnlyAffectsSourceFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = false
        initialState.sidebarWidth = 300
        initialState.contextMenuTargetId = "target-x"
        initialState.contextMenuTargetWasSelected = true

        let newFavorite = SidebarItems.FavoriteItem(
            name: "Loaded",
            url: URL(fileURLWithPath: "/Loaded"),
            iconName: "folder",
        )

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.internal(.favoritesLoaded([newFavorite]))) { state in
            state.favorites = [newFavorite]
            // 선호도/인터랙션 필드가 변경되지 않았는지 확인
            XCTAssertFalse(state.sidebarVisible)
            XCTAssertEqual(state.sidebarWidth, 300)
            XCTAssertEqual(state.contextMenuTargetId, "target-x")
            XCTAssertTrue(state.contextMenuTargetWasSelected)
        }

        await store.finish()
    }

    /// 인터랙션 시임이 인터랙션 필드에만 영향을 주는지 확인
    /// .view(.setContextMenuTarget)를 전송하고 context menu 상태만 변경되는지 확인
    func testInteractionSeamOnlyAffectsInteractionFields() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = true
        initialState.sidebarWidth = 250
        initialState.favorites = [
            SidebarItems.FavoriteItem(
                name: "Fav",
                url: URL(fileURLWithPath: "/Fav"),
                iconName: "folder",
            ),
        ]

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        await store.send(.view(.setContextMenuTarget(id: "ctx-42", wasSelected: true))) { state in
            state.contextMenuTargetId = "ctx-42"
            state.contextMenuTargetWasSelected = true
            // 선호도/소스 필드가 변경되지 않았는지 확인
            XCTAssertTrue(state.sidebarVisible)
            XCTAssertEqual(state.sidebarWidth, 250)
            XCTAssertEqual(state.favorites.count, 1)
        }

        await store.finish()
    }

    /// 분해 후에도 shell contract 필드 접근성이 유지되는지 확인
    /// sidebarVisible 및 sidebarWidth가 state로 읽기/쓰기 가능한지 확인.
    func testShellContractFieldsRemainAccessible() async {
        var initialState = FileManagerSidebarState()
        initialState.sidebarVisible = false
        initialState.sidebarWidth = 180

        let store = TestStore(initialState: initialState) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0[VoyagerEntitiesEntry.EntryLoadingClient.self] = VoyagerEntitiesEntry.EntryLoadingClient.testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }

        // 초기값이 읽을 수 있는지 확인
        XCTAssertEqual(store.state.sidebarVisible, false)
        XCTAssertEqual(store.state.sidebarWidth, 180)

        await store.finish()
    }
}
