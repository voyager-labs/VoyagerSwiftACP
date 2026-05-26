import AppKit
import ComposableArchitecture
@testable import Voyager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

/// FileManager 사이드바에서 라우팅/드롭 핸드오프 경계(사이드바-콘텐츠-내비게이션)의 계약을 검증한다.
@MainActor
final class FileManagerSidebarDelegateRoutingTests: XCTestCase {
    // MARK: - 1. openFavorite - 컬렉션 파일 분기와 경로 네비게이션 분기 모두 검증

    /// testOpenFavoriteRoutesToCollectionFileWhenExtensionMatches 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testOpenFavoriteRoutesToCollectionFileWhenExtensionMatches() async {
        var initialState = FileManagerFeature.State()
        let collectionURL = URL(fileURLWithPath: "/tmp/test.collection")
        let favorite = SidebarItems.FavoriteItem(
            name: "Test Collection",
            url: collectionURL,
            iconName: "folder",
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openFavorite(favorite))))
        await store.receive {
            guard case let .navigation(.view(.openCollectionFile(url))) = $0 else { return false }
            return url.path == collectionURL.path
        }
        await store.finish()
    }

    /// testOpenFavoriteRoutesToPathNavigationWhenNotCollectionFile 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testOpenFavoriteRoutesToPathNavigationWhenNotCollectionFile() async {
        var initialState = FileManagerFeature.State()
        let folderURL = URL(fileURLWithPath: "/tmp/folder")
        let favorite = SidebarItems.FavoriteItem(
            name: "Test Folder",
            url: folderURL,
            iconName: "folder",
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openFavorite(favorite))))
        await store.receive {
            guard case let .navigation(.view(.navigateToPath(path))) = $0 else { return false }
            return path == folderURL.path
        }
        await store.finish()
    }

    // MARK: - 2. openLocation - 경로 네비게이션으로 라우팅

    /// testOpenLocationRoutesToPathNavigation 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testOpenLocationRoutesToPathNavigation() async {
        var initialState = FileManagerFeature.State()
        let locationURL = URL(fileURLWithPath: "/Users/test")
        let location = SidebarItems.LocationItem(
            name: "Home",
            url: locationURL,
            iconName: "house",
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.openLocation(location))))
        await store.receive {
            guard case let .navigation(.view(.navigateToPath(path))) = $0 else { return false }
            return path == locationURL.path
        }
        await store.finish()
    }

    // MARK: - 3. showTag - 태그 이름(String)으로 라우팅

    /// testShowTagRoutesByTagName 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testShowTagRoutesByTagName() async {
        var initialState = FileManagerFeature.State()
        let tagName = "Important"

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        // String 페이로드만 검증
        await store.send(.sidebar(.delegate(.showTag(tagName))))
        await store.receive {
            guard case let .navigation(.view(.showTag(receivedTagName))) = $0 else { return false }
            return receivedTagName == tagName
        }
        await store.finish()
    }

    // MARK: - 4. showRecents와 showComputer - 네비게이션으로 라우팅

    /// testShowRecentsRoutesToNavigation 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testShowRecentsRoutesToNavigation() async {
        var initialState = FileManagerFeature.State()

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.showRecents)))
        await store.receive {
            guard case .navigation(.view(.showRecents)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    /// testShowComputerRoutesToNavigation 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testShowComputerRoutesToNavigation() async {
        var initialState = FileManagerFeature.State()

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.sidebar(.delegate(.showComputer)))
        await store.receive {
            guard case .navigation(.view(.showComputer)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - 5. dropItems - 폴더 드롭과 태그 드롭 모두 검증

    /// testDropItemsToSidebarFolderRoutesToContentDelegate 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testDropItemsToSidebarFolderRoutesToContentDelegate() async {
        var initialState = FileManagerFeature.State()
        let targetURL = URL(fileURLWithPath: "/tmp/target")
        let providers: [NSItemProvider] = [NSItemProvider(item: nil, typeIdentifier: "public.file-url")]

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        // .content(.delegate(.dropItemsToSidebarFolder(...))) 핸드오프를 검증
        await store.send(.sidebar(.delegate(.dropItemsToSidebarFolder(providers: providers, targetURL: targetURL))))
        await store.receive {
            guard case let .content(.delegate(.dropItemsToSidebarFolder(receivedProviders, receivedURL))) = $0
            else { return false }
            return receivedURL.path == targetURL.path && receivedProviders.count == providers.count
        }
        await store.finish()
    }

    /// testDropItemsToTagRoutesToContentDelegate 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testDropItemsToTagRoutesToContentDelegate() async {
        var initialState = FileManagerFeature.State()
        let tagName = "Work"
        let providers: [NSItemProvider] = [NSItemProvider(item: nil, typeIdentifier: "public.file-url")]

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        // .content(.delegate(.dropItemsToTag(...))) 핸드오프를 검증
        await store.send(.sidebar(.delegate(.dropItemsToTag(providers: providers, tagName: tagName))))
        await store.receive {
            guard case let .content(.delegate(.dropItemsToTag(receivedProviders, receivedTagName))) = $0
            else { return false }
            return receivedTagName == tagName && receivedProviders.count == providers.count
        }
        await store.finish()
    }
}
