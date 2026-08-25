import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
extension EVM001FileManagerNavigationTests {
    // MARK: - EVM-001-route_entry_selection_commands

    /// EVM-001-route_entry_selection_commands: stale coreBatch는 pending selection을 소비하지 않는다.
    /// 이전 로딩 세대 또는 순서가 어긋난 배치가 도착해도 현재 네비게이션에서 요청한 entry 선택을 변경하지 않는지 검증한다.
    /// - 검증 내용: generation 또는 batchIndex가 loadingContext와 다르면 pendingSelectEntryID와 selection state를 유지하고
    /// selectionChanged를 발행하지 않는다.
    /// - 사전 조건: generation=7, expectedCoreBatchIndex=3이며 대상 entry가 포함된 stale coreBatch 두 개가 순서대로 도착한다.
    /// - 기대 결과: pendingSelectEntryID와 빈 selection이 유지되고 미소비 effect가 없다.
    func testStaleCoreBatchDoesNotConsumePendingSelection() async {
        let targetEntry = EntryModel.temporaryFolder(id: "/tmp/pending-selection", name: "pending-selection")
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetEntry.id
        state.pendingSelectEntryDestinationPath = "/tmp"
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 3
        state.entryViewLayout.entryOperations.loadingContext.items = [targetEntry]

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: EntryViewLayout progressive loading의 부수 상태는 stale event의 선택 불변성 범위가 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 6,
            event: .coreBatch(items: [targetEntry], batchIndex: 3),
        ))))))
        XCTAssertEqual(store.state.pendingSelectEntryID, targetEntry.id)
        XCTAssertEqual(store.state.pendingSelectEntryDestinationPath, "/tmp")
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 7,
            event: .coreBatch(items: [targetEntry], batchIndex: 2),
        ))))))
        XCTAssertEqual(store.state.pendingSelectEntryID, targetEntry.id)
        XCTAssertEqual(store.state.pendingSelectEntryDestinationPath, "/tmp")
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        await store.finish()
    }

    /// EVM-001-route_entry_selection_commands: current coreBatch는 pending selection을 적용한다.
    /// 현재 로딩 세대의 기대한 배치가 대상 entry를 전달하면 네비게이션 요청 선택을 복원하는지 검증한다.
    /// - 검증 내용: generation과 batchIndex가 loadingContext와 일치하는 coreBatch가 pendingSelectEntryID를 소비하고 selectionChanged를
    /// 발행한다.
    /// - 사전 조건: generation=7, expectedCoreBatchIndex=3이며 대상 entry를 포함한 동일 generation/batchIndex coreBatch가 도착한다.
    /// - 기대 결과: 대상 entry가 선택되고 pendingSelectEntryID가 nil이며 selectionChanged가 한 번 발행된다.
    func testCurrentCoreBatchAppliesPendingSelection() async {
        let targetEntry = EntryModel.temporaryFolder(id: "/tmp/pending-selection", name: "pending-selection")
        var state = FileManagerContentState()
        state.pendingSelectEntryID = targetEntry.id
        state.entryViewLayout.entryOperations.loadingContext.generation = 7
        state.entryViewLayout.entryOperations.loadingContext.expectedCoreBatchIndex = 3

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: EntryViewLayout progressive loading의 부수 상태는 pending selection 복원 범위가 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 7,
            event: .coreBatch(items: [targetEntry], batchIndex: 3),
        )))))) {
            $0.pendingSelectEntryID = nil
            $0.entryViewLayout.selectedIds = [targetEntry.id]
            $0.entryViewLayout.lastSelectedId = targetEntry.id
            $0.entryViewLayout.rangeAnchorId = targetEntry.id
        }
        await store.receive(\.entryViewLayout.delegate.selectionChanged)
        await store.finish()
    }
}
