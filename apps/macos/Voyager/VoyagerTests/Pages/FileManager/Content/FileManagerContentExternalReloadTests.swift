import ComposableArchitecture
@testable import Voyager
import struct VoyagerEntitiesCollection.CollectionContext
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

/// FileManager content 외부 파일시스템 이벤트가 페이지 리로드 계약과 맞는지 검증한다.
@MainActor
final class FileManagerContentExternalReloadTests: XCTestCase {
    private func extractLoadItems(from action: FileManagerContentAction) -> (path: String, showHidden: Bool)? {
        let evAction = (/FileManagerContentAction.entryViewLayout).extract(from: action)
        let eoAction = evAction.flatMap { (/EntryViewLayoutFeature.Action.entryOperations).extract(from: $0) }
        let loadingAction = eoAction.flatMap { (/EntryOperationsAction.loading).extract(from: $0) }
        guard let loadingAction, case let .loadItems(path, showHidden) = loadingAction else { return nil }
        return (path, showHidden)
    }

    /// testFileSystemChangedReloadsCurrentFolderForDirectChildPath 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedReloadsCurrentFolderForDirectChildPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.receive { action in
            guard let result = self.extractLoadItems(from: action) else { return false }
            return result.path == "/tmp/voyager" && !result.showHidden
        }
    }

    /// testFileSystemChangedReloadsCurrentFolderForNestedPath 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedReloadsCurrentFolderForNestedPath() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        store.exhaustivity = .off

        await store.send(.externalFileSystemChanged(["/tmp/voyager/subdir/a.txt"]))
        await store.receive { action in
            guard let result = self.extractLoadItems(from: action) else { return false }
            return result.path == "/tmp/voyager" && !result.showHidden
        }
    }

    /// testFileSystemChangedDoesNotReloadUnrelatedFolder 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReloadUnrelatedFolder() async {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/other/a.txt"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotReloadCollectionRoute 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReloadCollectionRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .collection(
            .init(
                kind: .temporary,
                context: .init(query: "q", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotReloadRecentsRoute 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReloadRecentsRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotReloadTagRoute 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReloadTagRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .tags("blue")

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }

    /// testFileSystemChangedDoesNotReloadComputerRoute 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testFileSystemChangedDoesNotReloadComputerRoute() async {
        var initialState = FileManagerContentState()
        initialState.navigation.navigationState = .computer

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }

        await store.send(.externalFileSystemChanged(["/tmp/voyager/a.txt"]))
        await store.finish()
    }
}
