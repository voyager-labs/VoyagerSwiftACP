import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class EOP003GlobalUndoCommandTests: XCTestCase {
    /// EOP-003-undo_entry_action: global Undo command는 canonical native stack의 record를 최신순으로 한 번씩 소비한다.
    /// 두 completion 뒤 연속 Cmd+Z가 duplicate native handler에 막히지 않고 각각 replay를 완료하는지 검증한다.
    /// - 검증 내용: B 다음 A replay, phase idle 복귀, logical/native stack projection을 비교한다.
    /// - 사전 조건: W1/A scope와 registry-backed legacy facade에 서로 다른 rename completion 두 건이 있다.
    /// - 기대 결과: 두 global Undo 뒤 undoRecords와 native Undo가 비고 두 record 모두 Redo 가능하다.
    func testGlobalUndoCommandsConsumeCanonicalHistorySequentially() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let fileOperationClient = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let tabID = ContentTabID(rawValue: "A")
        let scope = UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
        let manager = fileOperationClient.activate(scope)
        let generation = try XCTUnwrap(fileOperationClient.generation(scope))
        let firstFixture = try makeReplayFixture()
        let secondFixture = try makeReplayFixture()
        defer {
            firstFixture.sandbox.cleanup()
            secondFixture.sandbox.cleanup()
        }
        let replayCompleted = expectation(description: "두 global Undo replay 완료")
        replayCompleted.expectedFulfillmentCount = 2
        let store = makeStore(
            state: makeState(windowID: windowID, tabID: tabID),
            fileOperationClient: fileOperationClient,
            undoManagerClient: .live(
                registry: registry,
                resolveScope: { $0 == windowID ? scope : nil },
            ),
            replayCompleted: replayCompleted,
        )
        store.exhaustivity = .off

        await store.send(.internal(.undoManagerWindowIDChanged(windowID)))
        await sendCompletion(firstFixture.record, generation: generation, tabID: tabID, to: store)
        await sendCompletion(secondFixture.record, generation: generation, tabID: tabID, to: store)
        await store.skipReceivedActions()
        await store.send(.request(.requestUndo))
        await store.skipReceivedActions()
        await store.send(.request(.requestUndo))
        await fulfillment(of: [replayCompleted], timeout: 2)
        await store.skipReceivedActions()

        let operations = store.state.content.entryViewLayout.entryOperations
        XCTAssertTrue(operations.undoRecords.isEmpty)
        XCTAssertEqual(operations.redoRecords.map(\.id), [secondFixture.record.id, firstFixture.record.id])
        XCTAssertEqual(store.state.undoRedoPhase, .idle)
        XCTAssertEqual(manager?.canUndo, false)
        XCTAssertEqual(manager?.canRedo, true)
        firstFixture.assertUndoneState()
        secondFixture.assertUndoneState()
        await store.skipInFlightEffects()
    }

    private func sendCompletion(
        _ record: EntryActionRecord,
        generation: UInt64,
        tabID: ContentTabID,
        to store: TestStore<FileManagerWindowState, FileManagerWindowAction>,
    ) async {
        await store.send(.internal(.entryActionCompleted(
            tabID: tabID,
            record: record,
            undoManagerGeneration: generation,
        )))
    }

    private func makeStore(
        state: FileManagerWindowState,
        fileOperationClient: FileOperationUndoManagerClient,
        undoManagerClient: UndoManagerClient,
        replayCompleted: XCTestExpectation,
    ) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        var entryFileOpsClient = EntryFileOpsClient.previewValue
        entryFileOpsClient.renameFile = { sourcePath, destinationPath in
            try FileManager.default.moveItem(at: sourcePath, to: destinationPath)
            replayCompleted.fulfill()
        }
        return TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryFileOpsClient = entryFileOpsClient
            $0.fileOperationUndoManagerClient = fileOperationClient
            $0.undoManagerClient = undoManagerClient
            $0.uuid = .incrementing
        }
    }

    private func makeState(windowID: UUID, tabID: ContentTabID) -> FileManagerWindowState {
        var content = FileManagerContentFeature.State()
        content.navigation.seedInitialFolderPath("/tmp/\(tabID.rawValue)")
        content.entryViewLayout.entryOperations.windowID = windowID
        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .directory,
                    anchor: .directory(path: "/tmp/\(tabID.rawValue)"),
                    isPinned: false,
                    title: tabID.rawValue,
                    iconName: "folder",
                ),
            ],
            activeTabID: tabID,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeReplayFixture() throws -> ReplayFixture {
        let sandbox = try FileManagerFixtureSandbox.copyingFileWithDirectorySymlink(
            from: "fixtures/fixtures/texts/plain/11.txt",
        )
        let beforePath = sandbox.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("restored-\(sandbox.fileURL.lastPathComponent)")
            .path
        return ReplayFixture(
            sandbox: sandbox,
            record: EntryActionRecord(
                operationKind: .rename,
                targets: [.init(beforePath: beforePath, afterPath: sandbox.fileURL.path)],
            ),
            beforePath: beforePath,
            afterPath: sandbox.fileURL.path,
        )
    }
}

private struct ReplayFixture {
    let sandbox: FileManagerFixtureSandbox
    let record: EntryActionRecord
    let beforePath: String
    let afterPath: String

    func assertUndoneState() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: beforePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: afterPath))
    }
}
