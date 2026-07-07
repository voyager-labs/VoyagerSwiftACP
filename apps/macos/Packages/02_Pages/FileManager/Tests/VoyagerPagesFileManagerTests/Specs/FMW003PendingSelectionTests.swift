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

    /// FMW-003: /tmp deep link와 /private/tmp 로드 결과가 symlink 기준으로 동일하면 실제 entry ID를 선택한다.
    /// - 사전 조건: pendingSelectEntryID는 /tmp 경로, entries는 FileManager가 반환한 /private/tmp 경로
    /// - 기대 결과: 매칭 성공 + UI가 찾을 수 있는 loaded entry ID로 selection state 반영
    func test_handleItemsLoaded_symlinkEquivalentEntry_selectsLoadedEntryID() async {
        let pendingID = "/tmp/voyager-qa-folder/sample.txt"
        let loadedEntryID = "/private/tmp/voyager-qa-folder/sample.txt"
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

    /// FMW-003: 전체 FileManagerContentFeature에서 itemsLoaded action pass 안에 pending selection이 반영된다.
    /// - 기대 결과: EntryViewLayoutFeature.updateEntriesAndReapply가 빈 selection으로 되돌리지 않음
    func test_contentFeature_itemsLoaded_appliesPendingSelectionBeforeEntryLayoutReconcile() async {
        let targetID = "/test/doc.txt"
        let entries = [Self.makeEntry(fullPath: targetID)]
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetID

        let store = makeFileManagerContentFeatureStore(initialState: state)
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.itemsLoaded(entries))))) {
            $0.pendingSelectEntryID = nil
            $0.entryViewLayout.selectedIds = Set([targetID])
            $0.entryViewLayout.lastSelectedId = targetID
            $0.entryViewLayout.rangeAnchorId = targetID
            $0.entryViewLayout.shouldScrollToSelection = true
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
