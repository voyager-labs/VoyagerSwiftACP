import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class EOP003GlobalUndoCommandTests: XCTestCase {
    /// EOP-003-undo_entry_action: 단일 duplicate는 새 tab의 첫 Entry completion 전에 Undo scope를 활성화한다.
    /// duplicate owner handoff와 canonical Undo lifecycle 사이의 누락을 검증한다.
    /// - 검증 내용: duplicate post-reduce 뒤 새 scope의 generation과 native manager를 확인한다.
    /// - 사전 조건: source tab scope가 활성화된 단일 Content Tab window가 있다.
    /// - 기대 결과: duplicate tab도 독립 generation과 native manager를 즉시 보유한다.
    func testSingleDuplicateActivatesUndoScopeBeforeEntryCompletion() async {
        let registry = FileOperationUndoManagerRegistry()
        let fileOperationClient = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let sourceID = ContentTabID(rawValue: "source")
        let duplicateID = ContentTabID(rawValue: "duplicate")
        let sourceScope = UndoManagerScope(windowID: windowID, contentTabID: sourceID.rawValue)
        let duplicateScope = UndoManagerScope(windowID: windowID, contentTabID: duplicateID.rawValue)
        _ = fileOperationClient.activate(sourceScope)
        let store = TestStore(
            initialState: makeState(windowID: windowID, tabIDs: [sourceID], activeTabID: sourceID),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileOperationUndoManagerClient = fileOperationClient
        }
        // store.exhaustivity = .off: duplicate handoff의 부수 action보다 새 canonical scope 생성을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicate(sourceID: sourceID, duplicateID: duplicateID)))
        await store.skipReceivedActions()

        XCTAssertNotNil(fileOperationClient.generation(duplicateScope))
        XCTAssertNotNil(registry.undoManager(for: duplicateScope))
    }

    /// EOP-003-undo_entry_action: bulk duplicate는 active 여부와 무관하게 생성된 모든 tab scope를 활성화한다.
    /// inactive duplicate의 지연 Entry completion도 canonical 등록 가능한지 검증한다.
    /// - 검증 내용: 두 duplicate scope의 generation과 native manager를 모두 확인한다.
    /// - 사전 조건: 두 source tab scope가 활성화되고 두 duplicate identity가 충돌 없이 요청된다.
    /// - 기대 결과: 생성된 active·inactive duplicate가 각각 독립 Undo scope를 보유한다.
    func testBulkDuplicateActivatesUndoScopesForEveryCreatedTab() async {
        let registry = FileOperationUndoManagerRegistry()
        let fileOperationClient = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let sourceA = ContentTabID(rawValue: "source-a")
        let sourceB = ContentTabID(rawValue: "source-b")
        let duplicateA = ContentTabID(rawValue: "duplicate-a")
        let duplicateB = ContentTabID(rawValue: "duplicate-b")
        for tabID in [sourceA, sourceB] {
            _ = fileOperationClient.activate(UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue))
        }
        let store = TestStore(
            initialState: makeState(windowID: windowID, tabIDs: [sourceA, sourceB], activeTabID: sourceA),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileOperationUndoManagerClient = fileOperationClient
        }
        // store.exhaustivity = .off: batch handoff 부수 action보다 모든 생성 scope의 lifecycle을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.duplicateSelected([
            ContentTabDuplicateRequest(sourceID: sourceA, duplicateID: duplicateA),
            ContentTabDuplicateRequest(sourceID: sourceB, duplicateID: duplicateB),
        ])))
        await store.skipReceivedActions()

        for tabID in [duplicateA, duplicateB] {
            let scope = UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
            XCTAssertNotNil(fileOperationClient.generation(scope))
            XCTAssertNotNil(registry.undoManager(for: scope))
        }
    }

    /// EOP-003-undo_entry_action: parent completion은 active B가 아니라 captured origin A scope에 compatibility metadata를
    /// 연결한다.
    /// canonical 등록 뒤 child effect가 active scope를 재해석해 다른 tab history를 만드는 race를 검증한다.
    /// - 검증 내용: A/B registry availability와 native manager history를 비교한다.
    /// - 사전 조건: W1/A와 W1/B가 활성화되어 있고 B가 active인 상태에서 A completion이 도착한다.
    /// - 기대 결과: A만 owner/record target과 native Undo를 보유하고 B history는 비어 있다.
    func testOriginTabCompletionBindsCompatibilityMetadataToCapturedScope() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let fileOperationClient = FileOperationUndoManagerClient.live(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: tabB.rawValue)
        let managerA = try XCTUnwrap(fileOperationClient.activate(scopeA))
        let managerB = try XCTUnwrap(fileOperationClient.activate(scopeB))
        let generationA = try XCTUnwrap(fileOperationClient.generation(scopeA))
        let state = makeState(windowID: windowID, tabIDs: [tabA, tabB], activeTabID: tabB)
        let ownerA = try XCTUnwrap(
            state.tabContentStates[tabA]?.entryViewLayout.entryOperations.undoOwnerID,
        )
        // 성공 target이 있는 record만 undo 등록 대상이다(전체 실패 배치 제외 계약).
        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/src/a.txt", afterPath: "/dest/a.txt")],
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileOperationUndoManagerClient = fileOperationClient
            $0.undoManagerClient = .live(registry: registry, resolveScope: { _ in scopeB })
        }
        // store.exhaustivity = .off: child availability action보다 captured origin scope의 native identity를 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.entryActionCompleted(
            tabID: tabA,
            record: record,
            undoManagerGeneration: generationA,
        )))
        await store.skipReceivedActions()

        let identity = UndoManagerRecordIdentity(ownerID: ownerA, recordID: record.id)
        XCTAssertEqual(registry.compatibilityAvailability(scopeA).undoTarget, identity)
        XCTAssertEqual(registry.compatibilityAvailability(scopeB), .init())
        XCTAssertTrue(managerA.canUndo)
        XCTAssertFalse(managerB.canUndo)
    }

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
            state: makeState(windowID: windowID, tabIDs: [tabID], activeTabID: tabID),
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

    private func makeState(
        windowID: UUID,
        tabIDs: [ContentTabID],
        activeTabID: ContentTabID,
    ) -> FileManagerWindowState {
        let contents = Dictionary(uniqueKeysWithValues: tabIDs.map { tabID in
            var content = FileManagerContentFeature.State()
            content.navigation.seedInitialFolderPath("/tmp/\(tabID.rawValue)")
            content.entryViewLayout.entryOperations.windowID = windowID
            return (tabID, content)
        })
        var state = FileManagerWindowState()
        state.windowID = windowID
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: tabIDs.map { tabID in
                ContentTabItem(
                    id: tabID,
                    page: .directory,
                    anchor: .directory(path: "/tmp/\(tabID.rawValue)"),
                    isPinned: false,
                    title: tabID.rawValue,
                    iconName: "folder",
                )
            }),
            activeTabID: activeTabID,
        )
        state.content = contents[activeTabID] ?? FileManagerContentFeature.State()
        state.tabContentStates = contents
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

    // MARK: - EOP-003-entry_command_teardown

    /// EOP-003-entry_command_teardown: pending content command는 observed aggregate와 함께 unavailable로 종료된다.
    /// non-undo/undo metadata 모두 window teardown에서 한 번만 기록되는지 검증한다.
    /// - 검증 내용: partial observed result, command identity, 반복 teardown dedupe
    /// - 사전 조건: copyPath와 pasteFileMove command가 수용되고 각각 하나의 path만 관측된다.
    /// - 기대 결과: 두 command가 unavailable metric으로 정확히 한 번 기록된다.
    func testPendingEntryCommandsSurviveWindowTeardown() async {
        let metrics = LockIsolated<[FileManagerProductMetric]>([])
        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.fileManagerProductMetricsClient = .init(record: { metric in
                metrics.withValue { $0.append(metric) }
            })
        }
        // store.exhaustivity = .off: teardown child cleanup은 건너뛰고 command metric만 확인한다.
        store.exhaustivity = .off

        let commandCases = [
            EntryCommandCase(
                metadata: .init(id: UUID(), interaction: .copyAbsolutePaths, source: .menuCommand),
                operationKind: .copyPath,
                path: "/tmp/copy",
            ),
            EntryCommandCase(
                metadata: .init(id: UUID(), interaction: .pasteEntries, source: .contextMenu),
                operationKind: .pasteFileMove,
                path: "/tmp/move",
            ),
        ]
        let sidebarCommand = EntryCommandCase(
            metadata: .init(id: UUID(), interaction: .copyEntries, source: .dragAndDrop),
            operationKind: .pasteFileCopy,
            path: "/tmp/sidebar-success",
        )
        for (index, commandCase) in commandCases.enumerated() {
            let metadata = commandCase.metadata
            let operationKind = commandCase.operationKind
            let path = commandCase.path
            await store.send(.content(.entryViewLayout(.entryOperations(.acceptedCommand(
                metadata: metadata,
                action: .lifecycle(.operationStarted(path, operationKind)),
            )))))
            if index == 0 {
                await store.send(.content(.entryViewLayout(.entryOperations(.acceptedCommand(
                    metadata: metadata,
                    action: .lifecycle(.operationFinished(path, operationKind, .success(()))),
                )))))
                await store.send(.content(.entryViewLayout(.entryOperations(.acceptedCommand(
                    metadata: metadata,
                    action: .lifecycle(.operationStarted("/tmp/copy-pending", operationKind)),
                )))))
            }
        }
        await store.send(.internal(.sidebarEntryDrop(.acceptedCommand(
            metadata: sidebarCommand.metadata,
            action: .lifecycle(.operationStarted(sidebarCommand.path, sidebarCommand.operationKind)),
        ))))
        await store.send(.internal(.sidebarEntryDrop(.acceptedCommand(
            metadata: sidebarCommand.metadata,
            action: .lifecycle(.operationFinished(sidebarCommand.path, sidebarCommand.operationKind, .success(()))),
        ))))
        await store.send(.internal(.sidebarEntryDrop(.acceptedCommand(
            metadata: sidebarCommand.metadata,
            action: .lifecycle(.operationStarted("/tmp/sidebar-pending", sidebarCommand.operationKind)),
        ))))
        await store.send(.onDisappear)
        await store.send(.onDisappear)

        let entryMetrics = metrics.value.compactMap(entryActionMetric)
        XCTAssertEqual(entryMetrics.map(\.result), [.unavailable, .unavailable, .unavailable])
        XCTAssertEqual(
            Set(entryMetrics.map(\.operationID)),
            Set(commandCases.map(\.metadata.id) + [sidebarCommand.metadata.id]),
        )
        XCTAssertEqual(entryMetrics.map(\.aggregate).sorted { $0.attempted < $1.attempted }, [
            .init(attempted: 1, succeeded: 0, failed: 0),
            .init(attempted: 2, succeeded: 1, failed: 0),
            .init(attempted: 2, succeeded: 1, failed: 0),
        ])
    }
}

private struct EntryCommandCase {
    let metadata: EntryCommandMetadata
    let operationKind: OperationKind
    let path: String
}

private func entryActionMetric(_ metric: FileManagerProductMetric) -> EntryActionProductMetric? {
    guard case let .entryAction(value) = metric else { return nil }
    return value
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
