import Foundation
@testable import VoyagerFeaturesEntryOperations
import XCTest

extension EOP003ManageEntryLifecycleTests {
    /// EOP-003-empty_trash: Trash 비우기가 실제 파일 삭제로 이어지는지 검증한다.
    /// 사용자가 `fixtures/fixtures/texts/plain/11.txt`를 fake Trash에 넣은 뒤 empty trash를 실행할 때 파일이 삭제되는지 확인한다.
    /// - 검증 내용: `.trash(.emptyTrash)`가 confirmation 후 trash 항목 전체 삭제와 완료 상태 갱신을 수행한다.
    /// - 사전 조건: `fixtures/fixtures/texts/plain/11.txt`를 FixtureSandbox로 복사한 뒤 fake Trash 디렉터리로 옮겨두고, confirmation
    /// alert는 승인으로 응답한다.
    /// - 기대 결과: trash 파일이 삭제되고, reducer state의 pending/complete 카운터가 초기화되며, 원본 fixture 경로는 유지된다.
    func testEmptyTrash_success() async throws {
        let sandbox = try FixtureSandbox.copyingFile(from: "fixtures/fixtures/texts/plain/11.txt")
        defer { sandbox.cleanup() }

        let recorder = FileOpsRecorder()
        let trashRoot = sandbox.root.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let trashPath = trashRoot.appendingPathComponent("trash.txt")
        try FileManager.default.copyItem(at: sandbox.fileURL, to: trashPath)

        var initialState = EntryOperationsState()
        initialState.loadingContext.coreFinished = true
        let store = EntryOperationsTestSupport.makeStore(initialState: initialState) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showEmptyTrashConfirmationAlert = { _ in true }
        }

        // store.exhaustivity = .off: empty-trash confirmation and deletion are async integration steps.
        // skipReceivedActions로 수신된 action들을 소비해 store.state를 최종 상태로 갱신한다.
        store.exhaustivity = .off

        await store.send(.trash(.emptyTrash(paths: [trashPath.path])))
        await store.finish()
        await store.skipReceivedActions()

        XCTAssertEqual(recorder.deletedPaths, [trashPath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashPath.path))
        XCTAssertEqual(store.state.pendingEmptyTrashItemCount, 0)
        XCTAssertEqual(store.state.emptyTrashCompletedCount, 0)
        XCTAssertTrue(store.state.restorableTrashPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.originalFixture.path))
    }

    /// EOP-003-move_entries_to_trash: 선택된 부모와 하위 항목은 부모만 Trash 이동으로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.moveToTrash)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testMoveEntriesToTrash_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.moveSelectedItemsToTrash),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.moveToTrash(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("Trash 이동 명령은 moveToTrash payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-delete_entries_immediately: 선택된 부모와 하위 항목은 부모만 즉시 삭제로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.deleteImmediately)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testDeleteEntriesImmediately_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.deleteSelectedItemsImmediately),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.deleteImmediately(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("즉시 삭제 명령은 deleteImmediately payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-put_deleted_entries_back: 선택된 부모와 하위 항목은 부모만 원래 위치 복귀로 계획한다.
    /// 사용자가 하위 항목, 같은 raw-prefix peer, 부모를 표시 순서대로 함께 선택할 때 lifecycle planner가 부모와 peer만 유지하는지 확인한다.
    /// - 검증 내용: `.routing(.executeCommand)` planner가 선택된 조상 관계를 pathComponents로 판별하고 원본 fullPath 및 남은 표시 순서를 보존한다.
    /// - 사전 조건: 선택 목록에 descendant-first 부모-하위 항목 쌍과 조상이 아닌 raw-prefix peer를 구성한다.
    /// - 기대 결과: `.trash(.putBackFromTrash)`는 하위 항목을 제외한 peer와 부모 경로만 방출한다.
    func testPutBackSelectedItems_plansTopmostSelectedPaths() throws {
        let scenario = makeTopmostLifecycleSelectionScenario()
        let outputs = EntryOperationsCommandPlanner.plan(
            command: .mutation(.putBackSelectedItems),
            context: scenario.context,
        )

        XCTAssertEqual(outputs.count, 1)
        guard case let .entryOperations(.trash(.putBackFromTrash(paths))) = try XCTUnwrap(outputs.first) else {
            return XCTFail("되돌리기 명령은 putBackFromTrash payload를 계획해야 합니다.")
        }
        XCTAssertEqual(paths, scenario.expectedPaths)
    }

    /// EOP-003-empty_trash: Core loading 완료 전에는 Trash 비우기를 시작하지 않는다.
    /// 불완전한 Trash snapshot으로 삭제 범위를 확정하지 않도록 loading boundary를 검증한다.
    /// - 검증 내용: `.trash(.emptyTrash)`가 confirmation과 filesystem 삭제 effect를 만들지 않는다.
    /// - 사전 조건: `loadingContext.coreFinished`가 false인 초기 상태다.
    /// - 기대 결과: pending/completed count와 파일 삭제 기록이 변경되지 않는다.
    func testEmptyTrash_beforeCoreFinishedDoesNothing() async {
        let recorder = FileOpsRecorder()
        let store = EntryOperationsTestSupport.makeStore(initialState: .init()) {
            $0.entryFileOpsClient = makeRecordedFileOpsClient(recorder: recorder)
            $0.entryOperationsAlertClient.showEmptyTrashConfirmationAlert = { _ in
                XCTFail("Core loading 완료 전에는 confirmation을 요청하면 안 됩니다.")
                return true
            }
        }

        await store.send(.trash(.emptyTrash(paths: ["/tmp/.Trash/file.txt"])))

        XCTAssertEqual(store.state.pendingEmptyTrashItemCount, 0)
        XCTAssertEqual(store.state.emptyTrashCompletedCount, 0)
        XCTAssertTrue(recorder.deletedPaths.isEmpty)
    }

    private struct TopmostLifecycleSelectionScenario {
        let context: EntryOperationsCommandContext
        let expectedPaths: [String]
    }

    private func makeTopmostLifecycleSelectionScenario() -> TopmostLifecycleSelectionScenario {
        let parent = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder", isFolder: true)
        let descendant = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder/nested/file.txt")
        let rawPrefixPeer = EntryModelFixtures.makeEntry(path: "/tmp/Selected Folder Copy.txt")
        let displayItems = [descendant, rawPrefixPeer, parent]
        return TopmostLifecycleSelectionScenario(
            context: EntryOperationsCommandContext(
                selectedIds: Set(displayItems.map(\.id)),
                displayItems: displayItems,
                currentPath: "/tmp",
            ),
            expectedPaths: [rawPrefixPeer.fullPath, parent.fullPath],
        )
    }
}
