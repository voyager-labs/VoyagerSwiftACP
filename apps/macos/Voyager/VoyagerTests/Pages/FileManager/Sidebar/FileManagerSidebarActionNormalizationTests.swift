import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

// MARK: - VOY-201 작업 5: FileManagerSidebarAction 정규화 테스트

// 이 테스트들은 FileManagerSidebarAction이 정규화된 액션 구조를 사용하는지 확인합니다.
// view/internal/delegate 케이스가 TCA 액션 분류 규약을 따르는지 확인합니다.

@MainActor
final class SidebarActionNormalizationTests: XCTestCase {
    // MARK: - Action Structure Tests

    /// FileManagerSidebarAction이 예상한 view/internal/delegate 케이스를 포함하는지 확인
    func testActionHasViewInternalDelegateCases() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // 뷰 액션이 존재하고 전송 가능한지 확인
        await store.send(.view(.setSidebarVisible(true)))
        await store.send(.view(.toggleFavoritesSection))
        await store.send(.view(.toggleLocationsSection))
        await store.send(.view(.toggleTagsSection))

        await store.finish()
    }

    /// 사이드바 너비가 150...400 범위로 클램프되는지 검증
    func testSidebarWidthClamp() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // 최소값 미만 너비 테스트 (150으로 제한되어야 함)
        await store.send(.view(.setSidebarWidth(50)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 150, "Width should be clamped to minimum 150")

        // 최대값 초과 너비 테스트 (400으로 제한되어야 함)
        await store.send(.view(.setSidebarWidth(500)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 400, "Width should be clamped to maximum 400")

        // 유효한 너비 테스트 (변경 없이 유지되어야 함)
        await store.send(.view(.setSidebarWidth(250)))
        await store.finish()
        XCTAssertEqual(store.state.sidebarWidth, 250, "Valid width should be preserved")
    }

    /// pendingSidebarSelectionRestore가 올바르게 처리되는지 확인
    func testPendingSidebarSelectionRestore() async {
        var state = FileManagerSidebarState()
        state.pendingSidebarSelectionRestore = "favorite:/Users/test"

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // 복원 액션 전송
        await store.send(.internal(.restoreSidebarSelection))
        await store.finish()

        // 선택이 복원되고 대기 플래그가 해제되었는지 확인
        XCTAssertEqual(store.state.selectedSidebarItem, "favorite:/Users/test", "Selection should be restored")
        XCTAssertNil(store.state.pendingSidebarSelectionRestore, "Pending restore should be cleared after restore")
    }

    /// 상위에서 소유한 인텐트용 델리게이트 액션이 존재하는지 확인
    func testDelegateActionsExist() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // 델리게이트 액션을 전송할 수 있는지 확인 (실제 라우팅은 상위에서 처리)
        let favoriteItem = SidebarItems.FavoriteItem(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp"),
            iconName: "folder",
        )
        await store.send(.delegate(.openFavorite(favoriteItem)))

        await store.send(.delegate(.showRecents))
        await store.send(.delegate(.showComputer))

        await store.finish()
    }

    /// 로딩용 내부 액션이 존재하는지 확인
    func testInternalLoadingActions() async {
        let state = FileManagerSidebarState()

        let store = TestStore(initialState: state) {
            FileManagerSidebarFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.entryLoadingClient = .testValue
            $0.fileManagerFavoritesClient = .testValue
            $0.fileManagerLocationsClient = .testValue
            $0.finderFavoritesTagClient = .testValue
            $0.notificationCenterClient = .testValue
            $0.fileManagerIconClient = .testValue
        }
        store.exhaustivity = .off

        // 즐겨찾기 로딩 흐름 테스트
        await store.send(.internal(.loadFavorites))
        await store.finish()

        // 위치 로딩 흐름 테스트
        await store.send(.internal(.loadLocations))
        await store.finish()

        // 태그 로딩 흐름 테스트
        await store.send(.internal(.loadTags))
        await store.finish()
    }
}
