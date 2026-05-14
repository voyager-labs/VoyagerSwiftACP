import AppKit
import ComposableArchitecture
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import XCTest

@MainActor
final class FileManagerSidebarDelegateRoutingTests: XCTestCase {
    // MARK: - 1. openFavorite - collection file branch와 path navigation branch 둘 다 검증

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

    // MARK: - 2. openLocation - path navigation으로 라우팅

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

    // MARK: - 3. showTag - tag name(String)으로 라우팅

    func testShowTagRoutesByTagName() async {
        var initialState = FileManagerFeature.State()
        let tagName = "Important"

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
        }
        store.exhaustivity = .off

        // String payload만 검증
        await store.send(.sidebar(.delegate(.showTag(tagName))))
        await store.receive {
            guard case let .navigation(.view(.showTag(receivedTagName))) = $0 else { return false }
            return receivedTagName == tagName
        }
        await store.finish()
    }

    // MARK: - 4. showRecents와 showComputer - navigation으로 라우팅

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

    // MARK: - 5. dropItems - folder-drop과 tag-drop 둘 다 검증

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

        // .content(.delegate(.dropItemsToSidebarFolder(...))) handoff를 검증
        await store.send(.sidebar(.delegate(.dropItemsToSidebarFolder(providers: providers, targetURL: targetURL))))
        await store.receive {
            guard case let .content(.delegate(.dropItemsToSidebarFolder(receivedProviders, receivedURL))) = $0
            else { return false }
            return receivedURL.path == targetURL.path && receivedProviders.count == providers.count
        }
        await store.finish()
    }

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

        // .content(.delegate(.dropItemsToTag(...))) handoff를 검증
        await store.send(.sidebar(.delegate(.dropItemsToTag(providers: providers, tagName: tagName))))
        await store.receive {
            guard case let .content(.delegate(.dropItemsToTag(receivedProviders, receivedTagName))) = $0
            else { return false }
            return receivedTagName == tagName && receivedProviders.count == providers.count
        }
        await store.finish()
    }
}
