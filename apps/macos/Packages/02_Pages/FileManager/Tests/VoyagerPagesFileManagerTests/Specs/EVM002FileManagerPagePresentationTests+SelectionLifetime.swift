import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
extension EVM002FileManagerPagePresentationTests {
    // MARK: - EVM-002-update_entry_selection

    /// EVM-002-update_entry_selection: Quick Look open은 active content의 canonical selection을 바꾸지 않는다.
    /// 선택된 A에서 Quick Look command를 실행해도 FileManager composition이 selected IDs와 두 cursor를 유지하는지 검증한다.
    /// - 검증 내용: navigation.quickLookSelectedItem command가 A를 Quick Look client에 전달한 뒤 selection tuple이 유지되는지 확인
    /// - 사전 조건: /root의 A, B 중 A가 선택된 FileManagerContentFeature와 mocked Quick Look client
    /// - 기대 결과: Quick Look open은 A 한 번만 호출하고 selectedIds, focus, anchor는 모두 A로 유지된다.
    func testQuickLookOpenPreservesActiveContentSelectionTuple() async {
        let first = selectionLifetimeEntry(id: "/root/a.txt", name: "a.txt")
        let second = selectionLifetimeEntry(id: "/root/b.txt", name: "b.txt")
        let quickLookCalls = LockIsolated<[[String]]>([])
        let quickLookOpened = expectation(description: "Quick Look opened for selected entry")
        let initialTuple = SelectionLifetimeTuple(
            selectedIds: [first.id],
            lastSelectedId: first.id,
            rangeAnchorId: first.id,
        )
        let store = makeSelectionLifetimeStore(
            entries: [first, second],
            selectedID: first.id,
            quickLook: { urls, _ in
                quickLookCalls.withValue { $0.append(urls.map(\.path)) }
                quickLookOpened.fulfill()
            },
        )
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
        await fulfillment(of: [quickLookOpened], timeout: 2)

        XCTAssertEqual(quickLookCalls.value, [[first.fullPath]])
        XCTAssertEqual(
            SelectionLifetimeTuple(state: store.state.entryViewLayout),
            initialTuple,
        )
        await store.skipReceivedActions()
    }

    /// EVM-002-update_entry_selection: Quick Look open 이후의 정상 selection 이동은 새 항목을 정확히 한 번 sync한다.
    /// A를 미리 본 뒤 normal view selection action으로 B로 이동할 때 composition bridge가 B만 한 번 동기화하는지 검증한다.
    /// - 검증 내용: A Quick Look open 후 `.view(.updateSelection)`이 B의 Quick Look sync와 canonical tuple을 만드는지 확인
    /// - 사전 조건: A가 선택된 FileManagerContentFeature, mocked Quick Look client, A open 완료
    /// - 기대 결과: B path sync가 정확히 한 번 발생하고 tuple은 B로 이동하며 추가 sync는 없다.
    func testSelectionMoveAfterQuickLookSyncsNewEntryOnce() async {
        let first = selectionLifetimeEntry(id: "/root/a.txt", name: "a.txt")
        let second = selectionLifetimeEntry(id: "/root/b.txt", name: "b.txt")
        let quickLookCalls = LockIsolated<[[String]]>([])
        let syncCalls = LockIsolated<[(paths: [String], selectedIndex: Int)]>([])
        let quickLookOpened = expectation(description: "Quick Look opened for selected entry")
        let selectionSynced = expectation(description: "new selection synchronized to Quick Look")
        let store = makeSelectionLifetimeStore(
            entries: [first, second],
            selectedID: first.id,
            quickLook: { urls, _ in
                quickLookCalls.withValue { $0.append(urls.map(\.path)) }
                quickLookOpened.fulfill()
            },
            syncQuickLookSelection: { urls, selectedIndex in
                syncCalls.withValue { $0.append((urls.map(\.path), selectedIndex)) }
                selectionSynced.fulfill()
            },
        )
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
        await fulfillment(of: [quickLookOpened], timeout: 2)
        await store.skipReceivedActions()

        await store.send(.entryViewLayout(.view(.updateSelection(
            ids: [second.id],
            lastSelectedId: second.id,
            rangeAnchorId: second.id,
            shouldScrollToSelection: false,
        ))))
        await store.receive(\.entryViewLayout.internal.setSelectionState)
        await fulfillment(of: [selectionSynced], timeout: 2)

        XCTAssertEqual(quickLookCalls.value, [[first.fullPath]])
        XCTAssertEqual(syncCalls.value.map(\.paths), [[second.fullPath]])
        XCTAssertEqual(syncCalls.value.map(\.selectedIndex), [0])
        XCTAssertEqual(
            SelectionLifetimeTuple(state: store.state.entryViewLayout),
            SelectionLifetimeTuple(
                selectedIds: [second.id],
                lastSelectedId: second.id,
                rangeAnchorId: second.id,
            ),
        )
        await store.skipReceivedActions()
    }

    private func makeSelectionLifetimeStore(
        entries: [EntryModel],
        selectedID: EntryModel.ID,
        quickLook: @escaping @Sendable ([URL], Int) async throws -> Void,
        syncQuickLookSelection: @escaping @Sendable ([URL], Int) async -> Void = { _, _ in },
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/root")
        state.entryViewLayout.entries = entries
        state.entryViewLayout.entryOperations.items = .init(uniqueElements: entries)
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.loadingContext.directoryPath = "/root"
        state.entryViewLayout.entryOperations.loadingContext.coreFinished = true
        state.entryViewLayout.entryOperations.loadingContext.streamTerminal = true
        state.entryViewLayout.entryOperations.loadingContext.acceptedCoreFinishedGeneration = 1
        state.entryViewLayout.selectedIds = [selectedID]
        state.entryViewLayout.lastSelectedId = selectedID
        state.entryViewLayout.rangeAnchorId = selectedID

        return TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.coreBatch(items: entries, batchIndex: 0))
                    continuation.yield(.coreFinished(batchCount: 1))
                    continuation.finish()
                }
            }
            $0.entryQuickLookClient = .init(
                quickLook: quickLook,
                syncQuickLookSelection: syncQuickLookSelection,
            )
        }
    }

    private func selectionLifetimeEntry(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: Date(timeIntervalSince1970: 0),
            fileExtension: "txt",
            facets: .init(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

private struct SelectionLifetimeTuple: Equatable {
    let selectedIds: [EntryModel.ID]
    let lastSelectedId: EntryModel.ID?
    let rangeAnchorId: EntryModel.ID?

    init(
        selectedIds: [EntryModel.ID],
        lastSelectedId: EntryModel.ID?,
        rangeAnchorId: EntryModel.ID?,
    ) {
        self.selectedIds = selectedIds
        self.lastSelectedId = lastSelectedId
        self.rangeAnchorId = rangeAnchorId
    }

    init(state: EntryViewLayoutState) {
        self.init(
            selectedIds: Array(state.selectedIds),
            lastSelectedId: state.lastSelectedId,
            rangeAnchorId: state.rangeAnchorId,
        )
    }
}
