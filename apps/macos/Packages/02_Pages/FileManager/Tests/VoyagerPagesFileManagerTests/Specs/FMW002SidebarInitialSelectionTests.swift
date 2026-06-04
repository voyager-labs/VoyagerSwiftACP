import ComposableArchitecture
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class FMW002SidebarInitialSelectionTests: XCTestCase {
    /// FMW-002-show_sidebar: 시작 폴더가 location과 정확히 일치하면 source 로드 후 Sidebar 선택을 동기화
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

    /// FMW-002-show_sidebar: 하위 경로는 parent Sidebar item을 선택하지 않음
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

    /// FMW-002-show_sidebar: 같은 폴더의 표준화 가능한 path는 exact match로 취급
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
