import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

extension EVM002ManageEntriesViewPresentationTests {
    // MARK: - EVM-002-toggle_directory_expansion_in_list

    /// EVM-002-toggle_directory_expansion_in_list: grouped list는 disclosure와 retry를 flat projection으로 무시한다.
    ///
    /// - 검증 내용: active grouping 중 hierarchy intent가 child loader를 호출하지 않고 root selection을 유지
    /// - 사전 조건: directory root folder가 선택되어 있고 kind grouping이 활성화됨
    /// - 기대 결과: loader 요청은 0회이며 list mode와 root-only visible selection이 유지됨
    func testGroupedListDoesNotLoadChildren() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let recorder = EntryListHierarchyLoadRecorder()
        let store = flatModeCompatibilityStore(roots: [folder], recorder: recorder) { state in
            state.groupKey = .kind
            state.selectedIds = [folder.id]
            state.lastSelectedId = folder.id
            state.rangeAnchorId = folder.id
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.folderRetryRequested(id: folder.id)))
        await Task.yield()

        let requests = await recorder.recordedRequests()
        XCTAssertEqual(requests.count, 0)
        guard requests.isEmpty else { return }
        XCTAssertEqual(store.state.mode, .list)
        XCTAssertEqual(store.state.selectedIds, [folder.id])
        XCTAssertEqual(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [folder.id])
        await store.finish()
    }

    /// EVM-002-toggle_directory_expansion_in_list: grid는 disclosure와 retry를 flat projection으로 무시한다.
    ///
    /// - 검증 내용: grid mode hierarchy intent가 child loader를 호출하지 않고 selection을 유지
    /// - 사전 조건: directory root folder가 선택된 grid mode
    /// - 기대 결과: loader 요청은 0회이며 grid mode와 root-only visible selection이 유지됨
    func testGridDoesNotLoadChildren() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let recorder = EntryListHierarchyLoadRecorder()
        let store = flatModeCompatibilityStore(roots: [folder], recorder: recorder) { state in
            state.mode = .grid
            state.selectedIds = [folder.id]
            state.lastSelectedId = folder.id
            state.rangeAnchorId = folder.id
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.folderRetryRequested(id: folder.id)))
        await Task.yield()

        let requests = await recorder.recordedRequests()
        XCTAssertEqual(requests.count, 0)
        guard requests.isEmpty else { return }
        XCTAssertEqual(store.state.mode, .grid)
        XCTAssertEqual(store.state.selectedIds, [folder.id])
        XCTAssertEqual(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [folder.id])
        await store.finish()
    }

    /// EVM-002-toggle_directory_expansion_in_list: collection은 disclosure와 retry를 flat projection으로 무시한다.
    ///
    /// - 검증 내용: collection mode hierarchy intent가 child loader를 호출하지 않고 collection selection을 유지
    /// - 사전 조건: collection mode가 활성화되고 root folder가 선택됨
    /// - 기대 결과: loader 요청은 0회이며 list mode와 root-only visible selection이 유지됨
    func testCollectionDoesNotLoadChildren() async {
        let folder = EntryModel.temporaryFolder(id: "/root/a", name: "a")
        let recorder = EntryListHierarchyLoadRecorder()
        let store = flatModeCompatibilityStore(roots: [folder], recorder: recorder) { state in
            state.isCollectionMode = true
            state.selectedIds = [folder.id]
            state.lastSelectedId = folder.id
            state.rangeAnchorId = folder.id
        }
        store.exhaustivity = .off

        await store.send(.hierarchy(.folderExpansionRequested(id: folder.id)))
        await store.send(.hierarchy(.folderRetryRequested(id: folder.id)))
        await Task.yield()

        let requests = await recorder.recordedRequests()
        XCTAssertEqual(requests.count, 0)
        guard requests.isEmpty else { return }
        XCTAssertEqual(store.state.mode, .list)
        XCTAssertTrue(store.state.isCollectionMode)
        XCTAssertEqual(store.state.selectedIds, [folder.id])
        XCTAssertEqual(store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true), [folder.id])
        await store.finish()
    }

    private func flatModeCompatibilityStore(
        roots: [EntryModel],
        recorder: EntryListHierarchyLoadRecorder,
        configure: (inout EntryViewLayoutState) -> Void,
    ) -> TestStore<EntryViewLayoutState, EntryViewLayoutAction> {
        var state = EntryViewLayoutState()
        state.entries = roots
        state.hierarchy = .init(rootPath: "/root")
        configure(&state)
        return TestStore(initialState: state) {
            EntryViewLayoutFeature()
        } withDependencies: {
            $0.entryLoadingClient.loadItems = { url, showHidden in
                try await recorder.load(url: url, showHidden: showHidden)
            }
        }
    }
}
