import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FMW002SidebarInitialSelectionTests: XCTestCase {
    /// FMW-002-show_sidebar: 시작 폴더가 location과 정확히 일치하면 source 로드 후 Sidebar 선택을 동기화한다.
    /// File Manager Window가 초기 폴더 경로를 가진 상태에서 Sidebar location 로드 결과를 선택 상태에 반영하는지 검증한다.
    /// - 검증 내용: locationsLoaded가 locations 배열과 selectedSidebarItem을 exact match location으로 갱신하는지 확인
    /// - 사전 조건: initialFolderPath == /Users/test/Documents, location URL도 같은 경로
    /// - 기대 결과: selectedSidebarItem == "Documents"
    func test_initialFolderPath_selectsExactLocationAfterLocationsLoaded() async {
        let path = "/Users/test/Documents"
        let location = SidebarItems.LocationItem(
            name: "Documents",
            url: URL(fileURLWithPath: path),
            iconName: "folder",
        )
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: path)) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.internal(.locationsLoaded([location])))) { state in
            state.sidebar.locations = [location]
            state.sidebar.selectedSidebarItem = "Documents"
        }

        await store.finish()
    }

    /// FMW-002-show_sidebar: 하위 경로는 parent Sidebar item을 선택하지 않는다.
    /// 시작 경로가 location의 하위 폴더일 때 부모 location을 잘못 선택하지 않는지 검증한다.
    /// - 검증 내용: locationsLoaded가 parent location만 제공될 때 selectedSidebarItem을 설정하지 않는지 확인
    /// - 사전 조건: initialFolderPath == /Users/test/Documents/Child, location URL == /Users/test/Documents
    /// - 기대 결과: selectedSidebarItem == nil
    func test_initialFolderPath_doesNotSelectParentLocation() async {
        let location = SidebarItems.LocationItem(
            name: "Documents",
            url: URL(fileURLWithPath: "/Users/test/Documents"),
            iconName: "folder",
        )
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/Users/test/Documents/Child")) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.internal(.locationsLoaded([location])))) { state in
            state.sidebar.locations = [location]
        }

        XCTAssertNil(store.state.sidebar.selectedSidebarItem)

        await store.finish()
    }

    /// FMW-002-show_sidebar: 같은 폴더의 표준화 가능한 path는 exact match로 취급한다.
    /// `..` 세그먼트를 포함한 시작 경로가 표준화 후 favorite URL과 같으면 Sidebar 선택을 동기화하는지 검증한다.
    /// - 검증 내용: favoritesLoaded가 표준화된 경로와 일치하는 favorite을 selectedSidebarItem으로 설정하는지 확인
    /// - 사전 조건: initialFolderPath == /Users/test/Downloads/../Documents, favorite URL == /Users/test/Documents
    /// - 기대 결과: selectedSidebarItem == favorite.displayName
    func test_initialFolderPath_selectsStandardizedExactFavorite() async {
        let canonicalPath = "/Users/test/Documents"
        let seededPath = "/Users/test/Downloads/../Documents"
        let favorite = SidebarItems.FavoriteItem(
            name: "Documents",
            url: URL(fileURLWithPath: canonicalPath),
            iconName: "folder",
        )
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: seededPath)) {
            FileManagerFeature()
        }

        await store.send(.sidebar(.internal(.favoritesLoaded([favorite])))) { state in
            state.sidebar.favorites = [favorite]
            state.sidebar.selectedSidebarItem = favorite.displayName
        }

        await store.finish()
    }
}
