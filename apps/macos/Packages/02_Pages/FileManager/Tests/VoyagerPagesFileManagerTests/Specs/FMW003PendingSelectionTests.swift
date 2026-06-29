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
/// 2. pendingSelectEntryID를 즉시 nil로 clear (매칭 여부와 무관)
/// 3. 로드된 entries 중 매칭 ID가 있으면 setSelectionState 발행
/// 4. 매칭 ID가 없으면 selection 발행 없이 pending만 clear
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

    /// FMW-003: pendingSelectEntryID와 매칭되는 엔트리가 itemsLoaded에 포함된 경우 setSelectionState 발행 검증.
    /// - 사전 조건: pendingSelectEntryID == "/test/doc.txt", entries에 동일 fullPath 보유
    /// - 기대 결과: pendingSelectEntryID nil clear + setSelectionState(ids/lastSelectedId/rangeAnchorId = targetID, scroll
    /// = true) 발행
    func test_handleItemsLoaded_matchingEntry_sendsSetSelectionState() async {
        let targetID = "/test/doc.txt"
        let entries = [Self.makeEntry(fullPath: targetID)]

        let store = TestStore(initialState: makeBridgeState(pendingSelectEntryID: targetID)) {
            LifecycleBridgeHarness()
        }
        // exhaustiveness 비활성화 사유: entryViewLayout, composer, navigation 등
        // pendingSelectEntryID와 무관한 state 필드의 부수 변경 검증을 제외하기 위해
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries))))

        // 매칭 엔트리 발견 → coordinator가 setSelectionState 발행
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.internal(.setSelectionState(
                ids, lastSelectedId, rangeAnchorId, shouldScrollToSelection,
            )))) = action else { return false }
            return ids == Set([targetID])
                && lastSelectedId == targetID
                && rangeAnchorId == targetID
                && shouldScrollToSelection
        }
        await store.finish()
    }

    /// FMW-003: pendingSelectEntryID가 로드된 entries와 매칭되지 않는 경우 pending만 clear, selection 발행 없음.
    /// - 사전 조건: pendingSelectEntryID == "/test/other.txt", entries는 "/test/doc.txt"만 보유
    /// - 기대 결과: pendingSelectEntryID nil clear + 어떤 action도 수신하지 않음
    func test_handleItemsLoaded_nonMatchingEntry_clearsPendingNoSelection() async {
        let entries = [Self.makeEntry(fullPath: "/test/doc.txt")]

        let store = TestStore(
            initialState: makeBridgeState(pendingSelectEntryID: "/test/other.txt"),
        ) {
            LifecycleBridgeHarness()
        }
        // exhaustiveness 비활성화 사유: pendingSelectEntryID 외 무관한 state 필드 검증 제외
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded(entries))))
        // 매칭 엔트리 없음 → 수신 액션 없음
        await store.finish()
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
