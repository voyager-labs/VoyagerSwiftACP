import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

/// FMW-003-handle_external_file_open_requests: itemsLoaded + pendingSelectEntryID selection pipeline 테스트.
///
/// `FileManagerContentEntryOpsCoordinator.handleItemsLoaded`가 다음 동작을 수행하는지 검증:
/// 1. pendingSelectEntryID가 nil이면 no-op (기존 동작 유지)
/// 2. 로드된 entries 중 매칭 ID가 있으면 pendingSelectEntryID clear 후 selection state 즉시 반영
/// 3. 매칭 ID가 없으면 다음 itemsLoaded 재시도를 위해 pendingSelectEntryID 유지
@MainActor
final class FMW003PendingSelectionTests: XCTestCase {
    // MARK: - Helpers

    /// deterministic한 EntryModel 생성 (고정 timestamp로 테스트 안정성 확보).
    private static func makeEntry(fullPath: String) -> EntryModel {
        EntryModel(
            name: (fullPath as NSString).lastPathComponent,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 100,
            modifiedDate: Date(timeIntervalSince1970: 1_000_000),
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: Date(timeIntervalSince1970: 0),
                addedDate: Date(timeIntervalSince1970: 0),
                lastOpenedDate: nil,
                kind: "text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    /// bridge harness 초기 state 생성. pendingSelectEntryID만 선택적으로 주입.
    private func makeBridgeState(pendingSelectEntryID: String? = nil) -> LifecycleBridgeHarness.State {
        var state = LifecycleBridgeHarness.State(content: FileManagerContentState())
        state.content.pendingSelectEntryID = pendingSelectEntryID
        return state
    }

    // MARK: - Tests

    /// FMW-003: pendingSelectEntryID와 매칭되는 엔트리가 itemsLoaded에 포함된 경우 selection state 즉시 반영 검증.
    /// - 사전 조건: pendingSelectEntryID == "/test/doc.txt", entries에 동일 fullPath 보유
    /// - 기대 결과: pendingSelectEntryID nil clear + selectedIds/lastSelectedId/rangeAnchorId = targetID, scroll = true
    func test_handleItemsLoaded_matchingEntry_appliesSelectionImmediately() async {
        let targetID = "/test/doc.txt"
        let entries = [Self.makeEntry(fullPath: targetID)]

        let store = TestStore(initialState: makeBridgeState(pendingSelectEntryID: targetID)) {
            LifecycleBridgeHarness()
        }
        // exhaustiveness 비활성화 사유: entryViewLayout, composer, navigation 등
        // pendingSelectEntryID와 무관한 state 필드의 부수 변경 검증을 제외하기 위해
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries)))) {
            $0.content.pendingSelectEntryID = nil
            $0.content.entryViewLayout.selectedIds = Set([targetID])
            $0.content.entryViewLayout.lastSelectedId = targetID
            $0.content.entryViewLayout.rangeAnchorId = targetID
            $0.content.entryViewLayout.shouldScrollToSelection = true
        }

        // 매칭 엔트리 발견 → selectionChanged delegate 발행
        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.delegate(.selectionChanged))) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-003-handle_external_file_open_requests: symlink 경로 요청과 실제 로드 결과가 같은 파일이면 실제 entry ID를 선택한다.
    /// 사용자가 symlink 경로로 파일을 열고 FileManager가 실제 경로 entry를 로드한 경우의 pending selection 매칭을 검증한다.
    /// - 검증 내용: `itemsLoaded` 처리 시 pendingSelectEntryID와 loaded entry fullPath를 symlink 해소 기준으로 매칭한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/98.txt`를 임시 sandbox로 복사하고, pendingSelectEntryID는 sandbox symlink 경로,
    /// entries는 실제 복사본 경로를 사용한다.
    /// - 기대 결과: pendingSelectEntryID를 지우고 UI가 찾을 수 있는 loaded entry ID로 selection state를 반영한다.
    func test_handleItemsLoaded_symlinkEquivalentEntry_selectsLoadedEntryID() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/98.txt",
        )
        defer { sandbox.cleanup() }

        let pendingID = sandbox.symlinkedFileURL.path
        let loadedEntryID = sandbox.fileURL.path
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: loadedEntryID))
        XCTAssertEqual(
            URL(fileURLWithPath: pendingID).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: loadedEntryID).resolvingSymlinksInPath().path,
        )
        let entries = [Self.makeEntry(fullPath: loadedEntryID)]

        let store = TestStore(initialState: makeBridgeState(pendingSelectEntryID: pendingID)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries)))) {
            $0.content.pendingSelectEntryID = nil
            $0.content.entryViewLayout.selectedIds = Set([loadedEntryID])
            $0.content.entryViewLayout.lastSelectedId = loadedEntryID
            $0.content.entryViewLayout.rangeAnchorId = loadedEntryID
            $0.content.entryViewLayout.shouldScrollToSelection = true
        }

        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.delegate(.selectionChanged))) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-003: pendingSelectEntryID가 로드된 entries와 매칭되지 않는 경우 pending을 유지한다.
    /// - 사전 조건: pendingSelectEntryID == "/test/other.txt", entries는 "/test/doc.txt"만 보유
    /// - 기대 결과: selection 발행 없음 + 다음 itemsLoaded 재시도를 위해 pendingSelectEntryID 유지
    func test_handleItemsLoaded_nonMatchingEntry_preservesPendingNoSelection() async {
        let targetID = "/test/other.txt"
        let entries = [Self.makeEntry(fullPath: "/test/doc.txt")]

        let store = TestStore(
            initialState: makeBridgeState(pendingSelectEntryID: targetID),
        ) {
            LifecycleBridgeHarness()
        }
        // exhaustiveness 비활성화 사유: pendingSelectEntryID 외 무관한 state 필드 검증 제외
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries))))
        XCTAssertEqual(store.state.content.pendingSelectEntryID, targetID)
        // 매칭 엔트리 없음 → 수신 액션 없음
        await store.finish()
    }

    /// FMW-003: 첫 로드에서 매칭되지 않아도 이후 로드에서 대상 엔트리를 선택한다.
    /// - 사전 조건: 첫 itemsLoaded에는 대상 없음, 다음 itemsLoaded에는 대상 포함
    /// - 기대 결과: 첫 로드 후 pending 유지 + 다음 로드에서 selection 반영 후 pending clear
    func test_handleItemsLoaded_nonMatchingThenMatchingEntry_selectsOnRetry() async {
        let targetID = "/test/other.txt"
        let firstEntries = [Self.makeEntry(fullPath: "/test/doc.txt")]
        let secondEntries = [Self.makeEntry(fullPath: targetID)]

        let store = TestStore(
            initialState: makeBridgeState(pendingSelectEntryID: targetID),
        ) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(firstEntries))))
        XCTAssertEqual(store.state.content.pendingSelectEntryID, targetID)

        await store.send(.bridge(.loading(.itemsLoaded(secondEntries)))) {
            $0.content.pendingSelectEntryID = nil
            $0.content.entryViewLayout.selectedIds = Set([targetID])
            $0.content.entryViewLayout.lastSelectedId = targetID
            $0.content.entryViewLayout.rangeAnchorId = targetID
            $0.content.entryViewLayout.shouldScrollToSelection = true
        }
        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.delegate(.selectionChanged))) = action else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - FMW-003-handle_external_file_open_requests

    /// FMW-003-handle_external_file_open_requests: progressive coreBatch가 대상 엔트리를 전달하면 pending selection을 적용한다.
    /// 외부 파일 열기 요청 뒤 대상이 없는 첫 배치를 받은 다음, 대상이 포함된 후속 배치에서 선택을 복원하는 경로를 검증한다.
    /// - 검증 내용: 첫 coreBatch는 pendingSelectEntryID를 유지하고, 후속 매칭 coreBatch는 선택 state를 반영한 뒤 selectionChanged를 발행한다.
    /// - 사전 조건: pendingSelectEntryID는 "/test/other.txt"이며 첫 배치는 "/test/doc.txt", 두 번째 배치는 대상 엔트리를 포함한다.
    /// - 기대 결과: 첫 배치 뒤 pending이 유지되고, 두 번째 배치 뒤 pending이 nil이며 대상 ID가 선택되고 selectionChanged가 발행된다.
    func test_contentFeature_coreBatch_nonMatchingThenMatchingEntry_selectsOnLaterBatch() async {
        let targetID = "/test/other.txt"
        let firstEntries = [Self.makeEntry(fullPath: "/test/doc.txt")]
        let secondEntries = [Self.makeEntry(fullPath: targetID)]
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetID

        let store = makeFileManagerContentFeatureStore(initialState: state)
        // exhaustiveness 비활성화 사유: entryViewLayout의 progressive loading 부수 변경은 이 선택 복원 시나리오의 범위가 아님
        store.exhaustivity = .off

        await store.send(
            .entryOperations(
                .loading(
                    .streamEvent(
                        .init(
                            generation: 0,
                            event: .coreBatch(items: firstEntries, batchIndex: 0),
                        ),
                    ),
                ),
            ),
        )
        XCTAssertEqual(store.state.pendingSelectEntryID, targetID)

        await store.send(
            .entryOperations(
                .loading(
                    .streamEvent(
                        .init(
                            generation: 0,
                            event: .coreBatch(items: secondEntries, batchIndex: 1),
                        ),
                    ),
                ),
            ),
        ) {
            $0.pendingSelectEntryID = nil
            $0.entryViewLayout.selectedIds = Set([targetID])
            $0.entryViewLayout.lastSelectedId = targetID
            $0.entryViewLayout.rangeAnchorId = targetID
            $0.entryViewLayout.shouldScrollToSelection = true
        }
        await store.receive { action in
            guard case .entryViewLayout(.delegate(.selectionChanged)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// FMW-003: 전체 FileManagerContentFeature에서 itemsLoaded action pass 안에 pending selection이 반영된다.
    /// - 기대 결과: EntryViewLayoutFeature.updateEntriesAndReapply가 빈 selection으로 되돌리지 않음
    func test_contentFeature_itemsLoaded_appliesPendingSelectionBeforeEntryLayoutReconcile() async {
        let targetID = "/test/doc.txt"
        let entries = [Self.makeEntry(fullPath: targetID)]
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetID

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryOperations(.loading(.itemsLoaded(entries)))) {
            $0.pendingSelectEntryID = nil
            $0.entryViewLayout.selectedIds = Set([targetID])
            $0.entryViewLayout.lastSelectedId = targetID
            $0.entryViewLayout.rangeAnchorId = targetID
            $0.entryViewLayout.shouldScrollToSelection = true
        }
    }

    /// FMW-003-handle_external_file_open_requests: 첫 core batch에 대상이 보이면 terminal 전에 선택한다.
    /// - 사전 조건: pendingSelectEntryID 대상이 generation 1의 첫 core batch에 포함됨
    /// - 기대 결과: pending을 지우고 대상 선택 및 selectionChanged를 즉시 발행함
    func test_contentFeature_coreBatch_appliesPendingSelectionBeforeTerminal() async {
        let targetID = "/test/doc.txt"
        let entry = Self.makeEntry(fullPath: targetID)
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetID
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [entry], batchIndex: 0),
        )))))) {
            $0.pendingSelectEntryID = nil
            $0.entryViewLayout.selectedIds = Set([targetID])
            $0.entryViewLayout.lastSelectedId = targetID
            $0.entryViewLayout.rangeAnchorId = targetID
            $0.entryViewLayout.shouldScrollToSelection = true
        }
        await store.receive { action in
            guard case .entryViewLayout(.delegate(.selectionChanged)) = action else { return false }
            return true
        }
    }

    /// FMW-003: pendingSelectEntryID가 nil인 경우 기존 동작 유지 (no-op).
    /// - 사전 조건: pendingSelectEntryID == nil
    /// - 기대 결과: state 변경 없음, 어떤 action도 수신하지 않음
    func test_handleItemsLoaded_noPending_returnsNone() async {
        let entries = [Self.makeEntry(fullPath: "/test/doc.txt")]

        let store = TestStore(initialState: makeBridgeState()) {
            LifecycleBridgeHarness()
        }
        // exhaustiveness 비활성화 사유: no-op 케이스로 side effect 검증만 수행
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries))))
        // pendingSelectEntryID가 nil이므로 coordinator가 즉시 .none 반환
        await store.finish()
    }

    // MARK: - FMW-003-handle_external_file_open_requests

    /// FMW-003-handle_external_file_open_requests: regular-file reservation은 첫 itemsLoaded 전에 pending selection을 저장한다.
    /// 시스템 open으로 parent Directory tab을 만든 뒤 파일 entry를 reveal하는 기존 pending-selection seam을 검증한다.
    /// - 검증 내용: external initial snapshot의 pending ID가 itemsLoaded에서 소비되어 selection state로 전환된다.
    /// - 사전 조건: caller tab ID, parent Directory anchor, regular-file full path를 가진 reservation 하나다.
    /// - 기대 결과: load 전 pending ID가 존재하고 load 후 clear되며 해당 entry가 선택되고 scroll 요청이 설정된다.
    func testExternalReservation_pendingSelectionExistsBeforeRegularFileLoad() async throws {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/98.txt",
        )
        defer { sandbox.cleanup() }
        let tabID = ContentTabID(rawValue: "external-regular-file")
        let directoryPath = sandbox.fileURL.deletingLastPathComponent().path
        let filePath = sandbox.fileURL.path
        let loadedEntry = Self.makeEntry(fullPath: filePath)
        let loadPaths = LockIsolated<[String]>([])
        let store = TestStore(initialState: FileManagerWindowState.makeInitial(path: "/seed")) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return [loadedEntry]
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { $0.finish() }
            }
        }
        // store.exhaustivity = .off: canonical handoff의 부수 action보다 load 후 pending reveal 소비를 검증한다.
        // bridge sync Reduce가 매 action마다 entryViewLayout.entries 등을 동기화하므로
        // 개별 action 수신 대신 skipReceivedActions로 부수 action을 소비하고 최종 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.reserveExternalContentTabs([
            ExternalContentTabReservation(
                id: tabID,
                anchor: .directory(path: directoryPath),
                pendingSelectEntryID: filePath,
            ),
        ]))
        XCTAssertEqual(store.state.tabContentStates[tabID]?.pendingSelectEntryID, filePath)
        await store.receive(\.contentTabs.setCurrent, tabID)
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryOperations.loading.loadItems)
        await store.receiveTabContent(\.entryOperations.loading.itemsLoaded)
        await store.finish()

        XCTAssertEqual(loadPaths.value, [directoryPath])
        XCTAssertNil(store.state.content.pendingSelectEntryID)
        XCTAssertEqual(store.state.content.entryViewLayout.selectedIds, [filePath])
        XCTAssertTrue(store.state.content.entryViewLayout.shouldScrollToSelection)
    }
}

/// EVM001FileManagerNavigationTests.LifecycleBridgeHarness와 동일한 패턴.
/// EntryOperationsAction을 coordinator로 전달하고 결과 action을 .forwarded로 노출하여
/// coordinator가 발행하는 Effect<FileManagerContentAction>을 TestStore로 검증 가능하게 함.
private struct LifecycleBridgeHarness: @MainActor Reducer {
    struct State: Equatable {
        var content: FileManagerContentState
    }

    enum Action {
        case bridge(EntryOperationsAction)
        case forwarded(FileManagerContentAction)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .bridge(entryAction):
                FileManagerContentEntryOpsCoordinator.handleEntryOperationsAction(
                    entryAction,
                    state: &state.content,
                )
                .map(Action.forwarded)
            case .forwarded:
                .none
            }
        }
    }
}
