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

    /// EVM-001-route_entry_selection_commands: 라우트 변경 직후 도착하는 이전 세대 터미널은 새 pending selection을 소비하지 않는다.
    /// 목적지 loadItems가 아직 세대를 증가시키기 전에 이전 로딩의 streamFinished가 도착해도 네비게이션 요청 선택을 유지하는지 검증한다.
    /// - 검증 내용: 라우트 /a와 destination /a가 일치하는 pending pair가 미바인딩 상태일 때 streamFinished(7)를 무시하고
    /// pendingSelectEntryID/pendingSelectEntryDestinationPath와 빈 selection을 유지한다.
    /// - 사전 조건: route=/a, pending entry=/a/b, destination=/a, loadingContext.generation=7이며 목적지 loadItems는 아직 통과하지 않았다.
    /// - 기대 결과: pending ID/destination이 유지되고 selection은 빈 채로 남는다.
    func testStaleTerminalBeforeDestinationLoadDoesNotConsumePendingSelection() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/a")
        state.setPendingEntrySelection(entryID: "/a/b", destinationPath: "/a")
        state.entryViewLayout.entryOperations.loadingContext.generation = 7

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: EntryViewLayout progressive loading의 부수 상태는 stale terminal의 선택 불변성 범위가 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamFinished(generation: 7)))))
        XCTAssertEqual(store.state.pendingSelectEntryID, "/a/b")
        XCTAssertEqual(store.state.pendingSelectEntryDestinationPath, "/a")
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

    /// EVM-001-route_entry_selection_commands: 목적지와 다른 경로의 loadItems는 pending selection 세대를 바인딩하지 않는다.
    /// stale 디렉터리 로드가 목적지 로드보다 먼저 통과해도 네비게이션 기원 pending이 잘못된 세대에 묶이지 않는지 검증한다.
    /// - 검증 내용: loadItems 경로가 pending destination과 표준화 기준으로 일치할 때만 자식 리듀서가 증가시킨 현재 세대에
    /// pendingSelectEntryLoadGeneration을 바인딩한다. /old 로드는 세대만 증가시키고 바인딩하지 않으며, /A(/A/. 표준화 동일) 로드는 바인딩한다.
    /// - 사전 조건: route=/A, pending entry=/A/target, destination=/A/., loadingContext.generation=7이며 staged load stream은
    /// 방출이 없다.
    /// - 기대 결과: /old 로드 후 generation=8에서 pendingSelectEntryLoadGeneration=nil이 유지되고, /A 로드 후 generation=9에
    /// pendingSelectEntryLoadGeneration=9가 바인딩된다.
    func testStaleLoadItemsPathDoesNotBindPendingSelectionGeneration() async {
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/A")
        state.setPendingEntrySelection(entryID: "/A/target", destinationPath: "/A/.")
        state.entryViewLayout.entryOperations.loadingContext.generation = 7

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            // 방출 없는 결정적 staged load stream: 로딩 이벤트 없이 세대 증가와 바인딩 규칙만 검증한다.
            $0.entryLoadingClient.stagedLoadItems = { _, _, _ in
                AsyncThrowingStream { _ in }
            }
        }
        // store.exhaustivity = .off: EntryViewLayout progressive loading의 부수 상태는 세대 바인딩 범위가 아님
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: "/old",
            showHidden: false,
            priority: .none,
        )))))
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 8)
        XCTAssertNil(store.state.pendingSelectEntryLoadGeneration)

        await store.send(.entryViewLayout(.entryOperations(.loading(.loadItems(
            path: "/A",
            showHidden: false,
            priority: .none,
        )))))
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 9)
        XCTAssertEqual(store.state.pendingSelectEntryLoadGeneration, 9)

        await store.skipInFlightEffects()
    }
}
