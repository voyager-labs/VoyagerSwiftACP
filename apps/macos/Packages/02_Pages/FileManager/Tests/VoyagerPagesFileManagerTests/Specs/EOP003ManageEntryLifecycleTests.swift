import AppKit
import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class EOP003ManageEntryLifecycleTests: XCTestCase {
    // MARK: - EOP-003-undo_entry_action

    /// EOP-003-undo_entry_action: W1/A, W1/B, W2/A는 서로 다른 native manager를 소유한다.
    /// 같은 탭 이름이 다른 window에 있어도 `(windowID, contentTabID)` scope가 manager identity를 완전히 격리하는지 검증한다.
    /// - 검증 내용: 세 explicit scope를 activate한 뒤 반환되는 UndoManager identity를 비교한다.
    /// - 사전 조건: 비어 있는 composition-scoped registry와 W1/A, W1/B, W2/A scope가 있다.
    /// - 기대 결과: 세 manager가 모두 존재하며 어느 둘도 같은 instance가 아니다.
    func testExplicitScopesIsolateManagersAcrossTabsAndWindows() throws {
        let client = makeClient()
        let windowOne = UUID()
        let windowTwo = UUID()
        let windowOneA = UndoManagerScope(windowID: windowOne, contentTabID: "A")
        let windowOneB = UndoManagerScope(windowID: windowOne, contentTabID: "B")
        let windowTwoA = UndoManagerScope(windowID: windowTwo, contentTabID: "A")

        let firstValue = client.activate(windowOneA)
        let secondValue = client.activate(windowOneB)
        let thirdValue = client.activate(windowTwoA)
        let first = try XCTUnwrap(firstValue)
        let second = try XCTUnwrap(secondValue)
        let third = try XCTUnwrap(thirdValue)

        XCTAssertNotIdentical(first, second)
        XCTAssertNotIdentical(first, third)
        XCTAssertNotIdentical(second, third)
    }

    /// EOP-003-undo_entry_action: initial window의 기존 모든 tab scope는 operation ingress 전에 활성화된다.
    /// coordinator가 window 표시와 child operation 수신보다 먼저 현재 tab inventory를 registry에 등록하는지 검증한다.
    /// - 검증 내용: W1/A와 W1/B를 가진 coordinator 생성 직후 manager lookup 및 A registerUndo 성공을 확인한다.
    /// - 사전 조건: composition-scoped registry/client와 두 existing tab을 가진 초기 FileManager state가 있다.
    /// - 기대 결과: coordinator init 반환 시 두 manager가 존재하고 첫 operation registration이 fail-closed되지 않는다.
    func testCoordinatorActivatesAllInitialTabScopesBeforeOperationIngress() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let state = makeTwoTabState(windowID: windowID, activeTabID: tabA)
        let store = makeCoordinatorStore(state: state, client: client)
        let coordinator = FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: registry,
            makeContentViewController: { _, _ in NSViewController() },
        )
        defer { coordinator.close() }
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: "A")
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: "B")

        XCTAssertNotNil(registry.undoManager(for: scopeA))
        XCTAssertNotNil(registry.undoManager(for: scopeB))
        let generationValue = client.generation(scopeA)
        let generation = try XCTUnwrap(generationValue)
        let didRegister = await client.registerUndo(
            scopeA,
            generation,
            makeRecord("initial"),
            { _ in },
            { _ in },
        )
        XCTAssertTrue(didRegister)
    }

    /// EOP-003-undo_entry_action: 새 tab은 state 삽입 직후 fresh empty scope를 활성화한다.
    /// open action이 새 ContentTabID를 확정한 뒤 사용자 operation ingress 전에 manager/history를 준비하는지 검증한다.
    /// - 검증 내용: `.contentTabs(.open(.homeDefault))` 후 새 active ID, 빈 logical history, 새 manager lookup을 확인한다.
    /// - 사전 조건: W1/A만 activate된 초기 window state와 composition-scoped registry/client가 있다.
    /// - 기대 결과: 새 tab은 A와 다른 ID를 가지며 undo/redo가 비고 해당 scope manager가 즉시 존재한다.
    func testOpeningNewTabActivatesFreshEmptyScopeAfterStateInsertion() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let store = makeStore(state: makeSingleTabState(windowID: windowID, tabID: tabA), client: client)
        // store.exhaustivity = .off: open의 navigation 부수 action보다 새 scope activation invariant를 검증한다.
        store.exhaustivity = .off
        _ = client.activate(UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue))
        await store.send(.contentTabs(.open(.homeDefault)))
        await store.skipReceivedActions()

        let newTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(newTabID, tabA)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.redoRecords.isEmpty)
        XCTAssertNotNil(registry.undoManager(for: UndoManagerScope(
            windowID: windowID,
            contentTabID: newTabID.rawValue,
        )))
    }

    /// EOP-003-undo_entry_action: active scope 요청은 같은 window의 inactive scope history를 소비하지 않는다.
    /// W1/A와 W1/B 모두 native history가 있을 때 active B 요청이 B callback만 실행하는지 검증한다.
    /// - 검증 내용: B scope requestUndo 후 A/B callback 횟수와 각 manager의 canUndo projection을 확인한다.
    /// - 사전 조건: W1/A와 W1/B가 activate되어 각각 undo record 한 건을 등록했고 B가 active request 대상이다.
    /// - 기대 결과: B callback만 한 번 실행되고 A history는 그대로 남는다.
    func testActiveScopeUndoDoesNotFallbackToInactiveHistory() async throws {
        let client = makeClient()
        let windowID = UUID()
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: "A")
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: "B")
        let callbacks = LockIsolated<[String]>([])
        let callback = expectation(description: "active B undo callback")
        _ = client.activate(scopeA)
        _ = client.activate(scopeB)

        let generationAValue = client.generation(scopeA)
        let generationBValue = client.generation(scopeB)
        let generationA = try XCTUnwrap(generationAValue)
        let generationB = try XCTUnwrap(generationBValue)
        let registeredA = await client.registerUndo(
            scopeA,
            generationA,
            makeRecord("A"),
            { _ in callbacks.withValue { $0.append("A") } },
            { _ in },
        )
        let registeredB = await client.registerUndo(
            scopeB,
            generationB,
            makeRecord("B"),
            { _ in
                callbacks.withValue { $0.append("B") }
                callback.fulfill()
            },
            { _ in },
        )
        XCTAssertTrue(registeredA)
        XCTAssertTrue(registeredB)

        let requestedUndo = await client.requestUndo(scopeB)
        XCTAssertTrue(requestedUndo)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(callbacks.value, ["B"])
        let inactiveManager = await client.undoManager(scopeA)
        XCTAssertEqual(inactiveManager?.canUndo, true)
    }

    /// EOP-003-undo_entry_action: A에서 시작한 completion은 B 전환 후 inactive A snapshot만 갱신한다.
    /// 비동기 file operation의 origin tab을 action에 고정해 active tab fallback을 금지하는 targeted child 경계를 검증한다.
    /// - 검증 내용: B로 setCurrent 후 `.tabContent(A, entryActionCompleted)`가 A의 undoRecords만 변경한다.
    /// - 사전 조건: W1에 A와 B가 있고 A가 active이며 두 tab history는 비어 있다.
    /// - 기대 결과: active B와 B snapshot은 비고 inactive A snapshot에만 record가 한 건 추가된다.
    func testOriginTabCompletionUpdatesInactiveSnapshotAfterSwitch() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let record = makeRecord("A-late")
        let store = makeStore(state: makeTwoTabState(windowID: windowID, activeTabID: tabA))
        // store.exhaustivity = .off: tab handoff의 부수 action보다 origin snapshot 격리만 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tabB)))
        await store.send(.tabContent(
            tabID: tabA,
            action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))),
        ))

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertEqual(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.undoRecords, [record])
        XCTAssertEqual(store.state.tabContentStates[tabB]?.entryViewLayout.entryOperations.undoRecords.isEmpty, true)
    }

    /// EOP-003-undo_entry_action: A→B→A rapid switch 후 captured origin-A completion은 정확히 한 번 A에 반영된다.
    /// callback 시점의 active tab을 재해석하지 않고 origin identity와 exactly-once record semantics를 유지하는지 검증한다.
    /// - 검증 내용: A→B→A 전환 후 하나의 `.tabContent(A, entryActionCompleted)`를 전송하고 양쪽 history를 비교한다.
    /// - 사전 조건: W1/A와 W1/B history가 비어 있고 operation은 최초 A에서 시작했다.
    /// - 기대 결과: active A에는 동일 record가 정확히 한 건 있고 B history는 비어 있다.
    func testRapidSwitchBackAppliesCapturedOriginCompletionExactlyOnce() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let record = makeRecord("rapid-A")
        let store = makeStore(state: makeTwoTabState(windowID: windowID, activeTabID: tabA))
        // store.exhaustivity = .off: handoff 부수 action보다 captured origin의 exactly-once 반영을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tabB)))
        await store.send(.contentTabs(.setCurrent(tabA)))
        await store.send(.tabContent(
            tabID: tabA,
            action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))),
        ))

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.undoRecords, [record])
        XCTAssertEqual(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.undoRecords, [record])
        XCTAssertEqual(store.state.tabContentStates[tabB]?.entryViewLayout.entryOperations.undoRecords.isEmpty, true)
    }

    /// EOP-003-undo_entry_action: 존재하지 않는 targeted tab action은 active tab으로 fallback하지 않는다.
    /// 닫혔거나 잘못된 ContentTabID의 completion이 현재 active history를 오염시키지 않는지 검증한다.
    /// - 검증 내용: missing ID의 `.tabContent` action 전후 active content와 모든 snapshot history를 비교한다.
    /// - 사전 조건: W1/A만 존재하고 A history는 비어 있으며 target은 존재하지 않는 Z이다.
    /// - 기대 결과: active A와 snapshot dictionary가 모두 변경되지 않고 추가 effect도 없다.
    func testMissingTargetedTabActionIsDiscardedWithoutActiveFallback() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let missing = ContentTabID(rawValue: "Z")
        let initialState = makeSingleTabState(windowID: windowID, tabID: tabA)
        let store = makeStore(state: initialState)

        await store.send(.tabContent(
            tabID: missing,
            action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(makeRecord("missing"))))),
        ))

        XCTAssertEqual(store.state, initialState)
        await store.finish()
    }

    /// EOP-003-undo_entry_action: A close 후 도착한 operation completion은 A를 부활시키거나 B를 갱신하지 않는다.
    /// filesystem completion은 끝나더라도 logical history owner가 사라진 뒤에는 record를 폐기하는 race를 검증한다.
    /// - 검증 내용: inactive A close 확정 후 captured `.tabContent(A, entryActionCompleted)`를 전달한다.
    /// - 사전 조건: W1의 active tab은 B이고 inactive A와 B history는 모두 비어 있다.
    /// - 기대 결과: A state는 다시 생기지 않고 B의 active/snapshot history도 비어 있다.
    func testClosedOriginTabDropsLateOperationCompletion() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let store = makeStore(state: makeTwoTabState(windowID: windowID, activeTabID: tabB))
        // store.exhaustivity = .off: close routing의 presentation effect보다 closed-origin discard를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(tabA)))
        await store.send(.tabContent(
            tabID: tabA,
            action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(makeRecord("late"))))),
        ))

        XCTAssertNil(store.state.contentTabs.tabs[id: tabA])
        XCTAssertNil(store.state.tabContentStates[tabA])
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertEqual(store.state.tabContentStates[tabB]?.entryViewLayout.entryOperations.undoRecords.isEmpty, true)
    }

    /// EOP-003-undo_entry_action: pinned tab close는 unpin으로 끝나며 같은 scope history를 유지한다.
    /// pinned close guard가 실제 tab 제거/deactivate보다 먼저 적용되어 manager와 logical history가 보존되는지 검증한다.
    /// - 검증 내용: pinned A close 전후 ContentTabID, undoRecords, UndoManager identity를 비교한다.
    /// - 사전 조건: W1/A가 pinned이고 undo record 한 건과 activate된 native manager를 가진다.
    /// - 기대 결과: A는 unpinned 상태로 남고 history와 manager instance가 동일하다.
    func testPinnedCloseUnpinsWithoutReplacingScopeOrHistory() async throws {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let record = makeRecord("pinned")
        var state = makeSingleTabState(windowID: windowID, tabID: tabA, isPinned: true)
        state.content.entryViewLayout.entryOperations.undoRecords = [record]
        state.tabContentStates[tabA] = state.content
        let client = makeClient()
        let scope = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let managerBeforeValue = client.activate(scope)
        let managerBefore = try XCTUnwrap(managerBeforeValue)
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: pinned close의 persistence effect보다 scope 보존 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(tabA)))
        await store.skipReceivedActions()
        let managerAfterValue = await client.undoManager(scope)
        let managerAfter = try XCTUnwrap(managerAfterValue)

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabA]?.isPinned, false)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.undoRecords, [record])
        XCTAssertIdentical(managerBefore, managerAfter)
    }

    /// EOP-003-undo_entry_action: last-tab close는 fresh Home으로 이어지고 window session을 유지한다.
    /// 닫힌 scope를 폐기하고 새 Home scope를 활성화하되 window close action을 방출하지 않는지 검증한다.
    /// - 검증 내용: 마지막 A close 후 Home ID/history, old/new manager lookup, closeWindow action 횟수를 확인한다.
    /// - 사전 조건: W1/A가 유일한 active tab이고 undo record 한 건과 활성화된 native manager를 가진다.
    /// - 기대 결과: 새 Home이 빈 history/manager로 활성화되고 old scope는 사라지며 window는 열린 상태를 유지한다.
    func testLastTabCloseCreatesFreshEmptyHomeAndKeepsWindowOpen() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let oldScope = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        var state = makeSingleTabState(windowID: windowID, tabID: tabA)
        state.content.entryViewLayout.entryOperations.undoRecords = [makeRecord("last")]
        state.tabContentStates[tabA] = state.content
        _ = client.activate(oldScope)
        let closeWindowActionCount = LockIsolated(0)
        let store = makeStore(
            state: state,
            client: client,
            closeWindowActionCount: closeWindowActionCount,
        )
        // store.exhaustivity = .off: tab handoff 내부 action보다 window 유지와 scope 교체 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(tabA)))
        await store.finish()

        let homeID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        let homeScope = UndoManagerScope(windowID: windowID, contentTabID: homeID.rawValue)
        XCTAssertNotEqual(homeID, tabA)
        XCTAssertEqual(store.state.contentTabs.tabs[id: homeID]?.anchor, .homeDefault)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.redoRecords.isEmpty)
        let oldManager = await client.undoManager(oldScope)
        let homeManager = await client.undoManager(homeScope)
        XCTAssertNil(oldManager)
        XCTAssertNotNil(homeManager)
        XCTAssertEqual(closeWindowActionCount.value, 0)
    }

    /// EOP-003-undo_entry_action: restore된 tab은 새 ID와 빈 history/native manager로 시작한다.
    /// 최근 닫힌 tab의 route만 복원하고 이전 logical/native undo session은 복원하지 않는지 검증한다.
    /// - 검증 내용: restore 전후 ID/history와 새 scope manager activation을 확인한다.
    /// - 사전 조건: W1/A가 active이고 recentlyClosed directory snapshot이 있으며 A에는 기존 undo history가 있다.
    /// - 기대 결과: restore tab은 A와 다른 ID, 빈 undo/redo stack, 새로 activate된 manager를 가진다.
    func testRestoredTabStartsWithFreshIdentityAndEmptyHistory() async throws {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        var state = makeSingleTabState(windowID: windowID, tabID: tabA)
        state.content.entryViewLayout.entryOperations.undoRecords = [makeRecord("existing")]
        state.tabContentStates[tabA] = state.content
        state.contentTabs.recentlyClosed = ClosedContentTabSnapshot(
            page: .directory,
            anchor: .directory(path: "/tmp/restored"),
            wasPinned: false,
            closedAt: Date(timeIntervalSince1970: 1_234_567_890),
        )
        let client = makeClient()
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: restore navigation effect보다 새 undo scope invariant를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.restore))
        await store.skipReceivedActions()

        let restoredID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(restoredID, tabA)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.redoRecords.isEmpty)
        let restoredManager = await client.undoManager(UndoManagerScope(
            windowID: windowID,
            contentTabID: restoredID.rawValue,
        ))
        XCTAssertNotNil(restoredManager)
    }

    /// EOP-003-undo_entry_action: duplicated window는 active/inactive 모든 tab의 transient operation state를 reset한다.
    /// route와 tab 구조를 복제하되 source window의 logical history, busy, selection, clipboard state를 공유하지 않는지 검증한다.
    /// - 검증 내용: `createInitialState(duplicateState:)` 결과의 모든 tab EntryViewLayout/EntryOperations state를 순회한다.
    /// - 사전 조건: source W1의 A와 B에 undo/redo, busy, selection, clipboard transient state가 채워져 있다.
    /// - 기대 결과: duplicate의 tab 구조는 같고 모든 active/inactive operation transient와 history는 비어 있다.
    func testDuplicateWindowResetsAllTabOperationHistoryAndTransientState() throws {
        let sourceWindowID = UUID()
        let duplicateWindowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        var source = makeTwoTabState(windowID: sourceWindowID, activeTabID: tabA)
        for tabID in source.contentTabs.tabs.ids {
            var content = source.tabContentStates[tabID] ?? source.content
            content.entryViewLayout.entryOperations.undoRecords = [makeRecord("undo-\(tabID.rawValue)")]
            content.entryViewLayout.entryOperations.redoRecords = [makeRecord("redo-\(tabID.rawValue)")]
            content.entryViewLayout.entryOperations.itemStates["/busy"] = ItemOperationState(isBusy: true)
            content.entryViewLayout.entryOperations.isLoading = true
            content.entryViewLayout.entryOperations.pendingEmptyTrashItemCount = 2
            let selectedID = "/selected-\(tabID.rawValue)"
            content.entryViewLayout.selectedIds = [selectedID]
            content.entryViewLayout.lastSelectedId = selectedID
            content.entryViewLayout.rangeAnchorId = selectedID
            content.entryViewLayout.shouldScrollToSelection = true
            content.entryViewLayout.entryOperations.selectedEntryIDs = [selectedID]
            content.entryViewLayout.entryOperations.clipboardItems = ["/clipboard"]
            source.tabContentStates[tabID] = content
            if tabID == source.contentTabs.activeTabID { source.content = content }
        }

        let sourceBeforeDuplicate = source
        let duplicate = FileManagerWindowCoordinator.createInitialState(
            windowID: duplicateWindowID,
            path: nil,
            duplicateState: source,
        )

        XCTAssertEqual(source, sourceBeforeDuplicate)
        XCTAssertEqual(duplicate.contentTabs.tabs.ids, source.contentTabs.tabs.ids)
        for tabID in duplicate.contentTabs.tabs.ids {
            let content = duplicate.tabContentStates[tabID]
            assertDuplicateSelectionReset(content)
            let operations = content?.entryViewLayout.entryOperations
            XCTAssertEqual(operations?.undoRecords.isEmpty, true)
            XCTAssertEqual(operations?.redoRecords.isEmpty, true)
            XCTAssertEqual(operations?.itemStates.isEmpty, true)
            XCTAssertEqual(operations?.isLoading, false)
            XCTAssertEqual(operations?.pendingEmptyTrashItemCount, 0)
            XCTAssertEqual(operations?.selectedEntryIDs.isEmpty, true)
            XCTAssertEqual(operations?.clipboardItems.isEmpty, true)
            XCTAssertEqual(operations?.windowID, duplicateWindowID)
        }
        let activeTabID = try XCTUnwrap(duplicate.contentTabs.activeTabID)
        XCTAssertEqual(duplicate.content, duplicate.tabContentStates[activeTabID])

        try assertDuplicateManagersAreIsolated(
            source: source,
            sourceWindowID: sourceWindowID,
            duplicate: duplicate,
            duplicateWindowID: duplicateWindowID,
        )
    }

    /// EOP-003-undo_entry_action: coordinator windowWillClose는 unregister callback 전에 W1 scope를 모두 제거한다.
    /// AppKit window teardown 경계가 reducer lifecycle이 아니라 composition-scoped registry를 동기 정리하는지 검증한다.
    /// - 검증 내용: `windowWillClose`의 `onWillClose` 안에서 W1/A·W1/B nil과 W2/A identity 보존을 확인한다.
    /// - 사전 조건: 같은 registry에 W1/A, W1/B, W2/A가 activate되어 있고 W1 coordinator가 등록되어 있다.
    /// - 기대 결과: callback이 관찰하는 시점에 W1 lookup은 모두 nil이며 W2/A는 기존 manager와 동일하다.
    func testWindowTeardownDeactivatesAllScopesBeforeUnregisterCallback() throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowOne = UUID()
        let windowTwo = UUID()
        let scopeA = UndoManagerScope(windowID: windowOne, contentTabID: "A")
        let scopeB = UndoManagerScope(windowID: windowOne, contentTabID: "B")
        let otherScope = UndoManagerScope(windowID: windowTwo, contentTabID: "A")
        _ = client.activate(scopeA)
        _ = client.activate(scopeB)
        let otherManagerValue = client.activate(otherScope)
        let otherManager = try XCTUnwrap(otherManagerValue)
        let state = makeTwoTabState(windowID: windowOne, activeTabID: ContentTabID(rawValue: "A"))
        let store = makeCoordinatorStore(state: state, client: client)
        var didObserveOrderedCleanup = false
        let coordinator = FileManagerWindowCoordinator(
            windowID: windowOne,
            store: store,
            fileOperationUndoManagerRegistry: registry,
            onWillClose: { closedWindowID in
                XCTAssertEqual(closedWindowID, windowOne)
                XCTAssertNil(registry.undoManager(for: scopeA))
                XCTAssertNil(registry.undoManager(for: scopeB))
                XCTAssertIdentical(registry.undoManager(for: otherScope), otherManager)
                didObserveOrderedCleanup = true
            },
            makeContentViewController: { _, _ in NSViewController() },
        )

        let window = try XCTUnwrap(coordinator.window)
        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertTrue(didObserveOrderedCleanup)
        XCTAssertNil(registry.undoManager(for: scopeA))
        XCTAssertNil(registry.undoManager(for: scopeB))
        XCTAssertIdentical(registry.undoManager(for: otherScope), otherManager)
    }

    /// EOP-003-undo_entry_action: operation completion은 origin scope에 native undo를 등록하고 captured tab으로 callback한다.
    /// active tab이 B로 바뀐 뒤 A manager undo가 A logical stack과 replay만 진행하는 native bridge를 검증한다.
    /// - 검증 내용: A completion 등록, B 전환, A manager undo 후 A/B history와 replay 호출을 확인한다.
    /// - 사전 조건: W1/A·W1/B scope가 활성화되고 operation origin은 A이며 두 tab history는 비어 있다.
    /// - 기대 결과: A manager만 undo 가능하고 callback은 `.tabContent(A, undoEntryAction)` 경로로 A만 변경한다.
    func testNativeUndoBridgeDispatchesCapturedOriginTabAfterActiveTabSwitch() async throws {
        let registry = FileOperationUndoManagerRegistry()
        var client = makeClient(registry: registry)
        let didRegisterNativeUndo = expectation(description: "native undo registered")
        let registerUndo = client.registerUndo
        client.registerUndo = { scope, generation, record, onUndo, onRedo in
            let result = await registerUndo(scope, generation, record, onUndo, onRedo)
            didRegisterNativeUndo.fulfill()
            return result
        }
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: tabB.rawValue)
        let replayCompleted = expectation(description: "captured A replay completed")
        var fileOpsClient = EntryFileOpsClient.previewValue
        fileOpsClient.renameFile = { _, _ in replayCompleted.fulfill() }
        _ = client.activate(scopeA)
        _ = client.activate(scopeB)
        let generationAValue = client.generation(scopeA)
        let generationA = try XCTUnwrap(generationAValue)
        let record = makeRecord("native-A")
        let store = makeStore(
            state: makeTwoTabState(windowID: windowID, activeTabID: tabA),
            client: client,
            entryFileOpsClient: fileOpsClient,
        )
        // store.exhaustivity = .off: native callback 이후 replay lifecycle보다 origin scope 격리를 검증한다.
        store.exhaustivity = .off

        await store.send(.internal(.entryActionCompleted(
            tabID: tabA,
            record: record,
            undoManagerGeneration: generationA,
        )))
        await fulfillment(of: [didRegisterNativeUndo], timeout: 1)
        let managerA = try XCTUnwrap(registry.undoManager(for: scopeA))
        let managerB = try XCTUnwrap(registry.undoManager(for: scopeB))
        XCTAssertTrue(managerA.canUndo)
        XCTAssertFalse(managerB.canUndo)

        await store.send(.contentTabs(.setCurrent(tabB)))
        managerA.undo()
        await fulfillment(of: [replayCompleted], timeout: 1)
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertEqual(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.redoRecords, [record])
        XCTAssertEqual(store.state.tabContentStates[tabB]?.entryViewLayout.entryOperations.undoRecords.isEmpty, true)
        await store.skipInFlightEffects()
    }

    /// EOP-003-undo_entry_action: requestUndo는 request 시점 active tab scope만 native client에 전달한다.
    /// inactive A history가 있어도 active B local history가 비면 fallback하지 않는 command routing을 검증한다.
    /// - 검증 내용: B history가 있을 때 한 번 요청한 뒤 B history가 빈 별도 store에서 추가 요청이 없는지 확인한다.
    /// - 사전 조건: W1/A·W1/B가 있고 B가 active이며 recorder client가 requested scope를 수집한다.
    /// - 기대 결과: recorder에는 W1/B scope 한 건만 있고 W1/A 요청은 없다.
    func testRequestUndoCapturesOnlyCurrentActiveTabScopeAndFailsClosedWhenEmpty() async {
        let registry = FileOperationUndoManagerRegistry()
        var client = makeClient(registry: registry)
        let requestedScopes = LockIsolated<[UndoManagerScope]>([])
        client.requestUndo = { scope in
            requestedScopes.withValue { $0.append(scope) }
            return false
        }
        let windowID = UUID()
        let tabB = ContentTabID(rawValue: "B")
        var state = makeTwoTabState(windowID: windowID, activeTabID: tabB)
        state.content.entryViewLayout.entryOperations.undoRecords = [makeRecord("B")]
        state.tabContentStates[tabB] = state.content
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: targeted request effect의 scope 기록만 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.requestUndo))
        await store.finish()

        let emptyStore = makeStore(
            state: makeTwoTabState(windowID: windowID, activeTabID: tabB),
            client: client,
        )
        await emptyStore.send(.request(.requestUndo))
        await emptyStore.finish()

        XCTAssertEqual(requestedScopes.value, [
            UndoManagerScope(
                windowID: windowID,
                contentTabID: tabB.rawValue,
            ),
        ])
    }

    /// EOP-003-undo_entry_action: window delegate는 호출 시점 active tab의 manager를 동적으로 반환한다.
    /// coordinator가 단일 manager를 저장하지 않고 A→B 전환을 즉시 projection하는지 검증한다.
    /// - 검증 내용: coordinator 생성 후 A manager, setCurrent(B) 후 B manager identity를 delegate에서 조회한다.
    /// - 사전 조건: W1/A·W1/B가 있는 store와 composition-scoped registry가 있다.
    /// - 기대 결과: 두 delegate 결과는 각 scope manager와 동일하고 서로 다른 instance다.
    func testWindowUndoManagerProjectionTracksCurrentActiveTabDynamically() throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let store = makeCoordinatorStore(
            state: makeTwoTabState(windowID: windowID, activeTabID: tabA),
            client: client,
        )
        let coordinator = FileManagerWindowCoordinator(
            windowID: windowID,
            store: store,
            fileOperationUndoManagerRegistry: registry,
            makeContentViewController: { _, _ in NSViewController() },
        )
        defer { coordinator.close() }
        let window = try XCTUnwrap(coordinator.window)
        let managerA = try XCTUnwrap(registry.undoManager(for: UndoManagerScope(
            windowID: windowID,
            contentTabID: tabA.rawValue,
        )))
        let managerB = try XCTUnwrap(registry.undoManager(for: UndoManagerScope(
            windowID: windowID,
            contentTabID: tabB.rawValue,
        )))

        XCTAssertIdentical(coordinator.windowWillReturnUndoManager(window), managerA)
        store.send(.contentTabs(.setCurrent(tabB)))
        XCTAssertIdentical(coordinator.windowWillReturnUndoManager(window), managerB)
        XCTAssertNotIdentical(managerA, managerB)
    }

    /// EOP-003-undo_entry_action: stale expected generation 등록은 재활성화된 manager를 오염시키지 않는다.
    /// generation read와 register 사이 deactivate/reactivate가 발생한 TOCTOU를 deterministic하게 재현한다.
    /// - 검증 내용: generation-1을 읽고 generation-2 manager를 만든 뒤 generation-1 registration 결과와 native history를 확인한다.
    /// - 사전 조건: 동일 W1/A scope가 deactivate 후 다시 activate되어 manager와 generation이 교체된다.
    /// - 기대 결과: stale registration은 false이고 callback은 실행되지 않으며 새 manager의 canUndo는 false다.
    func testStaleExpectedGenerationRegistrationCannotPolluteReactivatedManager() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let scope = UndoManagerScope(windowID: UUID(), contentTabID: "A")
        let staleCallback = expectation(description: "stale registration callback")
        staleCallback.isInverted = true
        _ = client.activate(scope)
        let staleGenerationValue = client.generation(scope)
        let staleGeneration = try XCTUnwrap(staleGenerationValue)

        client.deactivate(scope)
        let newManagerValue = client.activate(scope)
        let newManager = try XCTUnwrap(newManagerValue)
        let currentGenerationValue = client.generation(scope)
        let currentGeneration = try XCTUnwrap(currentGenerationValue)
        XCTAssertNotEqual(staleGeneration, currentGeneration)

        let didRegister = await client.registerUndo(
            scope,
            staleGeneration,
            makeRecord("stale-register"),
            { _ in staleCallback.fulfill() },
            { _ in },
        )
        newManager.undo()
        await fulfillment(of: [staleCallback], timeout: 0.1)

        XCTAssertFalse(didRegister)
        XCTAssertFalse(newManager.canUndo)
        let currentManager = await client.undoManager(scope)
        XCTAssertIdentical(currentManager, newManager)
    }

    /// EOP-003-undo_entry_action: deactivate/reactivate 뒤 이전 generation callback은 새 scope를 변경하지 않는다.
    /// 같은 key를 재사용해도 old manager handler가 generation-2 history를 소비하거나 scope를 부활시키지 않는지 검증한다.
    /// - 검증 내용: generation-1 manager를 보관한 뒤 deactivate, reactivate, old manager undo 순서로 실행한다.
    /// - 사전 조건: W1/A generation-1에 undo callback이 등록되어 있고 generation-2 manager는 빈 history로 활성화된다.
    /// - 기대 결과: old callback은 실행되지 않고 새 manager는 빈 상태이며 registry identity는 generation-2로 유지된다.
    func testDeactivatedGenerationCallbackCannotMutateReactivatedScope() async throws {
        let client = makeClient()
        let scope = UndoManagerScope(windowID: UUID(), contentTabID: "A")
        let staleCallback = expectation(description: "stale callback")
        staleCallback.isInverted = true
        let oldManagerValue = client.activate(scope)
        let oldManager = try XCTUnwrap(oldManagerValue)
        let generationValue = client.generation(scope)
        let generation = try XCTUnwrap(generationValue)
        let registered = await client.registerUndo(
            scope,
            generation,
            makeRecord("old"),
            { _ in staleCallback.fulfill() },
            { _ in },
        )
        XCTAssertTrue(registered)

        client.deactivate(scope)
        let newManagerValue = client.activate(scope)
        let newManager = try XCTUnwrap(newManagerValue)
        oldManager.undo()
        await fulfillment(of: [staleCallback], timeout: 0.1)

        XCTAssertNotIdentical(oldManager, newManager)
        XCTAssertFalse(oldManager.canUndo)
        XCTAssertFalse(newManager.canUndo)
        let currentManagerValue = await client.undoManager(scope)
        let currentManager = try XCTUnwrap(currentManagerValue)
        XCTAssertIdentical(currentManager, newManager)
    }

    /// EOP-003-undo_entry_action: pinned tab live-sync는 추가·제거 scope를 조정하고 생존 scope identity를 보존한다.
    /// FileManager owner가 바뀐 tab만 activate/deactivate하고 같은 tab·anchor의 native undo session은 유지하는지 검증한다.
    /// - 검증 내용: A·B에서 A·C inventory로 동기화한 뒤 A manager/generation/history와 B·C registry lookup을 확인한다.
    /// - 사전 조건: W1/A와 W1/B가 pinned이며 두 scope가 활성화되고 A에는 native undo history 한 건이 있다.
    /// - 기대 결과: A manager/generation/history는 동일하고 B scope는 제거되며 C scope는 새로 활성화된다.
    func testPinnedTabLiveSyncReconcilesScopesAndPreservesSurvivorIdentity() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let scopeA = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let scopeB = UndoManagerScope(windowID: windowID, contentTabID: tabB.rawValue)
        let scopeC = UndoManagerScope(windowID: windowID, contentTabID: tabC.rawValue)
        var state = makeTwoTabState(windowID: windowID, activeTabID: tabA)
        state.contentTabs.tabs[id: tabA]?.isPinned = true
        state.contentTabs.tabs[id: tabB]?.isPinned = true
        let managerBeforeValue = client.activate(scopeA)
        let managerBefore = try XCTUnwrap(managerBeforeValue)
        _ = client.activate(scopeB)
        let generationBeforeValue = client.generation(scopeA)
        let generationBefore = try XCTUnwrap(generationBeforeValue)
        let didRegister = await client.registerUndo(
            scopeA,
            generationBefore,
            makeRecord("survivor"),
            { _ in },
            { _ in },
        )
        XCTAssertTrue(didRegister)
        let survivor = try XCTUnwrap(state.contentTabs.tabs[id: tabA])
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: pinned inventory merge의 부수 action보다 scope lifecycle만 검증한다.
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(ContentTabState(
            tabs: [
                survivor,
                makeTab(id: tabC, isPinned: true),
            ],
            activeTabID: tabA,
        )))
        await store.finish()

        let managerAfterValue = await client.undoManager(scopeA)
        let managerAfter = try XCTUnwrap(managerAfterValue)
        let generationAfterValue = client.generation(scopeA)
        let generationAfter = try XCTUnwrap(generationAfterValue)
        let removedManager = await client.undoManager(scopeB)
        let addedManager = await client.undoManager(scopeC)
        XCTAssertIdentical(managerAfter, managerBefore)
        XCTAssertEqual(generationAfter, generationBefore)
        XCTAssertTrue(managerAfter.canUndo)
        XCTAssertNil(removedManager)
        XCTAssertNotNil(addedManager)
    }

    /// EOP-003-undo_entry_action: pinned inventory sync는 동일 ID의 현재 runtime anchor와 scope를 보존한다.
    /// persisted anchor가 달라도 열린 tab의 runtime navigation과 native undo session을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: A의 다른 persisted anchor 수신 전후 manager/generation identity와 native history를 확인한다.
    /// - 사전 조건: W1/A가 pinned이고 활성 scope의 native manager에 undo history 한 건이 등록되어 있다.
    /// - 기대 결과: 현재 runtime anchor, manager, generation, native undo history가 모두 유지된다.
    func testPinnedTabLiveSyncPreservesScopeWhenPersistedAnchorDiffers() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let scope = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let state = makeSingleTabState(windowID: windowID, tabID: tabA, isPinned: true)
        let managerBeforeValue = client.activate(scope)
        let managerBefore = try XCTUnwrap(managerBeforeValue)
        let generationBeforeValue = client.generation(scope)
        let generationBefore = try XCTUnwrap(generationBeforeValue)
        let didRegister = await client.registerUndo(
            scope,
            generationBefore,
            makeRecord("runtime-anchor"),
            { _ in },
            { _ in },
        )
        XCTAssertTrue(didRegister)
        XCTAssertTrue(managerBefore.canUndo)
        var persistedReplacement = makeTab(id: tabA, isPinned: true)
        persistedReplacement.anchor = .directory(path: "/tmp/A-persisted")
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: pinned inventory merge의 부수 action보다 runtime scope 보존만 검증한다.
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(ContentTabState(
            tabs: [persistedReplacement],
            activeTabID: tabA,
        )))

        let managerAfterValue = await client.undoManager(scope)
        let managerAfter = try XCTUnwrap(managerAfterValue)
        let generationAfterValue = client.generation(scope)
        let generationAfter = try XCTUnwrap(generationAfterValue)
        XCTAssertIdentical(managerAfter, managerBefore)
        XCTAssertEqual(generationAfter, generationBefore)
        XCTAssertTrue(managerAfter.canUndo)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabA]?.anchor, .directory(path: "/tmp/A"))
        await store.finish()
    }

    /// EOP-003-undo_entry_action: tab 제거 전에 시작한 실제 rename completion은 동일 ID 재도입 후 새 history에 진입하지 않는다.
    /// operation effect가 시작 generation을 Page envelope에 보존해 scope 재생성 뒤 stale 결과를 폐기하는지 검증한다.
    /// - 검증 내용: 실제 rename을 dependency에서 보류하고 A를 제거·재도입한 뒤 completion을 재개한다.
    /// - 사전 조건: W1/A scope가 활성화된 상태에서 rename effect 실행 중 pinned inventory에서 A가 제거된다.
    /// - 기대 결과: old-generation Page completion은 logical undo stack과 재생성된 native manager 모두에 등록되지 않는다.
    func testPinnedTabReintroductionDropsDelayedRenameCompletionFromPreviousGeneration() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let gate = EntryOperationSuspensionGate()
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let scope = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let oldPath = "/tmp/A/old-name"
        let newPath = "/tmp/A/new-name"
        let state = makeSingleTabState(windowID: windowID, tabID: tabA, isPinned: true)
        _ = client.activate(scope)
        let oldGenerationValue = client.generation(scope)
        let oldGeneration = try XCTUnwrap(oldGenerationValue)
        var fileOpsClient = EntryFileOpsClient.previewValue
        fileOpsClient.renameFile = { _, _ in await gate.wait() }
        let store = makeStore(state: state, client: client, entryFileOpsClient: fileOpsClient)
        // store.exhaustivity = .off: 실제 rename flow의 부수 lifecycle action보다 generation envelope와 history 격리를 검증한다.
        store.exhaustivity = .off
        let renameAction: FileManagerContentAction = .entryViewLayout(.entryOperations(.edit(.renameItem(
            oldPath: oldPath,
            newPath: newPath,
        ))))

        await store.send(.content(renameAction))
        await store.receive { action in
            guard case let .tabContent(receivedTabID, receivedAction) = action else { return false }
            return receivedTabID == tabA && Self.isRenameAction(
                receivedAction,
                oldPath: oldPath,
                newPath: newPath,
            )
        }
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .entryViewLayout(.entryOperations(.lifecycle(.operationStarted(path, kind)))),
            ) = action else { return false }
            return receivedTabID == tabA && path == oldPath && kind == .rename
        }
        await gate.waitUntilWaiting()

        await store.send(.applyPinnedContentTabs(ContentTabState()))
        let removedManager = await client.undoManager(scope)
        XCTAssertNil(removedManager)

        let reintroducedTab = makeTab(id: tabA, isPinned: true)
        await store.send(.applyPinnedContentTabs(ContentTabState(
            tabs: [reintroducedTab],
            activeTabID: tabA,
        )))
        let newGenerationValue = client.generation(scope)
        let newGeneration = try XCTUnwrap(newGenerationValue)
        XCTAssertNotEqual(newGeneration, oldGeneration)

        await gate.resume()
        await store.receive { action in
            guard case let .internal(.entryActionCompleted(
                receivedTabID,
                record,
                undoManagerGeneration,
            )) = action else { return false }
            return receivedTabID == tabA
                && record.operationKind == .rename
                && record.targets == [.init(beforePath: oldPath, afterPath: newPath)]
                && undoManagerGeneration == oldGeneration
        }
        await store.finish()

        let newManagerValue = await client.undoManager(scope)
        let newManager = try XCTUnwrap(newManagerValue)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.undoRecords.isEmpty ?? true)
        XCTAssertFalse(newManager.canUndo)
    }

    /// EOP-003-undo_entry_action: 마지막 pinned tab 제거는 old scope를 폐기하고 fresh Home scope를 활성화한다.
    /// 빈 pinned inventory가 만든 Home tab이 제거된 tab의 native undo session을 상속하지 않는지 검증한다.
    /// - 검증 내용: 마지막 A 제거 후 old scope lookup과 새 active Home scope manager/generation/history를 확인한다.
    /// - 사전 조건: W1/A가 유일한 pinned tab이고 활성 scope의 native manager에 undo history 한 건이 있다.
    /// - 기대 결과: A scope와 history는 제거되고 새로운 active tab scope가 빈 manager와 generation으로 활성화된다.
    func testRemovingLastPinnedTabActivatesFreshHomeScopeAndDeactivatesOldScope() async throws {
        let registry = FileOperationUndoManagerRegistry()
        let client = makeClient(registry: registry)
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let oldScope = UndoManagerScope(windowID: windowID, contentTabID: tabA.rawValue)
        let state = makeSingleTabState(windowID: windowID, tabID: tabA, isPinned: true)
        let oldManagerValue = client.activate(oldScope)
        let oldManager = try XCTUnwrap(oldManagerValue)
        let oldGenerationValue = client.generation(oldScope)
        let oldGeneration = try XCTUnwrap(oldGenerationValue)
        let didRegister = await client.registerUndo(
            oldScope,
            oldGeneration,
            makeRecord("removed-pinned"),
            { _ in },
            { _ in },
        )
        XCTAssertTrue(didRegister)
        let store = makeStore(state: state, client: client)
        // store.exhaustivity = .off: empty pinned inventory의 Home 생성 부수 action보다 scope lifecycle만 검증한다.
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(ContentTabState()))
        await store.finish()

        let homeID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        let homeScope = UndoManagerScope(windowID: windowID, contentTabID: homeID.rawValue)
        let removedManager = await client.undoManager(oldScope)
        let homeManager = await client.undoManager(homeScope)
        let homeGeneration = client.generation(homeScope)
        XCTAssertNotEqual(homeID, tabA)
        XCTAssertNil(removedManager)
        XCTAssertFalse(oldManager.canUndo)
        XCTAssertNotNil(homeManager)
        XCTAssertNotNil(homeGeneration)
        XCTAssertEqual(homeManager?.canUndo, false)
        XCTAssertEqual(homeManager?.canRedo, false)
    }

    // MARK: - EOP-003-redo_entry_action

    /// EOP-003-redo_entry_action: inactive origin tab의 redo completion도 active tab으로 fallback하지 않는다.
    /// Undo와 대칭으로 captured tab ID가 redo stack transition의 유일한 child route인지 검증한다.
    /// - 검증 내용: B가 active인 상태에서 `.tabContent(A, redoEntryAction)`을 전송한다.
    /// - 사전 조건: inactive A에는 redo record 한 건이 있고 active B history는 비어 있다.
    /// - 기대 결과: A의 redo stack만 소비되고 B active/snapshot history는 변하지 않는다.
    func testRedoTargetsInactiveOriginTabWithoutActiveFallback() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let record = makeRecord("redo-A")
        var state = makeTwoTabState(windowID: windowID, activeTabID: tabB)
        state.tabContentStates[tabA]?.entryViewLayout.entryOperations.redoRecords = [record]
        let store = makeStore(state: state)
        // store.exhaustivity = .off: replay filesystem effect보다 targeted stack transition을 검증한다.
        store.exhaustivity = .off

        await store.send(.tabContent(
            tabID: tabA,
            action: .entryViewLayout(.entryOperations(.undoRedo(.redoEntryAction(record)))),
        ))
        await store.skipReceivedActions()

        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.undoRecords.isEmpty)
        XCTAssertTrue(store.state.content.entryViewLayout.entryOperations.redoRecords.isEmpty)
        XCTAssertEqual(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.undoRecords, [record])
        XCTAssertEqual(store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.redoRecords.isEmpty, true)
        XCTAssertEqual(store.state.tabContentStates[tabB]?.entryViewLayout.entryOperations.undoRecords.isEmpty, true)
    }

    /// EOP-003-undo_entry_action: inactive A navigation apply는 active B가 아니라 origin A anchor만 대상으로 한다.
    /// targeted child effect를 parent navigation bridge가 active tab으로 재해석하지 않는지 검증한다.
    /// - 검증 내용: `.tabContent(A, applyNavigationState)`가 방출하는 tab anchor update의 ID와 active B state를 확인한다.
    /// - 사전 조건: W1/A는 inactive, W1/B는 active이고 A snapshot에는 새 directory route가 반영되어 있다.
    /// - 기대 결과: update target은 A이며 active B content/navigation은 변경되지 않는다.
    func testInactiveOriginNavigationApplyTargetsOnlyOriginTab() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let originPath = "/tmp/A-late"
        var state = makeTwoTabState(windowID: windowID, activeTabID: tabB)
        state.tabContentStates[tabA]?.navigation.seedInitialFolderPath(originPath)
        let activeContentBefore = state.content
        let store = TestStore(initialState: state) {
            FileManagerWindowNavigationReducer()
        }

        await store.send(.tabContent(
            tabID: tabA,
            action: .internal(.applyNavigationState(.folder(originPath))),
        ))
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .directory(path))) = action
            else { return false }
            return receivedTabID == tabA && path == originPath
        }

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(store.state.content, activeContentBefore)
    }

    /// EOP-003-undo_entry_action: inactive A의 Home delegate는 active B window/navigation을 재라우팅하지 않는다.
    /// user-facing Home selection은 active tab 소유이므로 stale inactive delegate를 fail-closed 처리하는지 검증한다.
    /// - 검증 내용: inactive A delegate 뒤 contentTabs/navigation 후속 action 수를 기록한다.
    /// - 사전 조건: A/B 모두 Home anchor이고 B가 active이다.
    /// - 기대 결과: 후속 window/navigation action은 0건이며 B anchor는 Home으로 유지된다.
    func testInactiveOriginHomeDelegateCannotRerouteActiveTab() async {
        let windowID = UUID()
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        var state = makeTwoTabState(windowID: windowID, activeTabID: tabB)
        state.contentTabs.tabs[id: tabA]?.anchor = .homeDefault
        state.contentTabs.tabs[id: tabA]?.page = .home
        state.contentTabs.tabs[id: tabB]?.anchor = .homeDefault
        state.contentTabs.tabs[id: tabB]?.page = .home
        let routedActions = LockIsolated(0)
        let store = TestStore(initialState: state) {
            CombineReducers {
                Reduce<FileManagerWindowState, FileManagerWindowAction> { _, action in
                    switch action {
                    case .contentTabs, .navigation:
                        routedActions.withValue { $0 += 1 }
                    default:
                        break
                    }
                    return .none
                }
                FileManagerWindowCommandRoutingReducer()
            }
        }
        await store.send(.tabContent(
            tabID: tabA,
            action: .delegate(.homePageAnchorSelected(.directory(path: "/tmp/A-late"))),
        ))
        await store.finish()

        XCTAssertEqual(routedActions.value, 0)
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabB]?.anchor, .homeDefault)
    }
}

private extension EOP003ManageEntryLifecycleTests {
    func assertDuplicateSelectionReset(_ content: FileManagerContentState?) {
        XCTAssertEqual(content?.entryViewLayout.selectedIds.isEmpty, true)
        XCTAssertNil(content?.entryViewLayout.lastSelectedId)
        XCTAssertNil(content?.entryViewLayout.rangeAnchorId)
        XCTAssertEqual(content?.entryViewLayout.shouldScrollToSelection, false)
    }

    func assertDuplicateManagersAreIsolated(
        source: FileManagerWindowState,
        sourceWindowID: UUID,
        duplicate: FileManagerWindowState,
        duplicateWindowID: UUID,
    ) throws {
        let registry = FileOperationUndoManagerRegistry()
        let sourceStore = makeCoordinatorStore(state: source, client: makeClient(registry: registry))
        let duplicateStore = makeCoordinatorStore(state: duplicate, client: makeClient(registry: registry))
        let sourceCoordinator = FileManagerWindowCoordinator(
            windowID: sourceWindowID,
            store: sourceStore,
            fileOperationUndoManagerRegistry: registry,
            makeContentViewController: { _, _ in NSViewController() },
        )
        let duplicateCoordinator = FileManagerWindowCoordinator(
            windowID: duplicateWindowID,
            store: duplicateStore,
            fileOperationUndoManagerRegistry: registry,
            makeContentViewController: { _, _ in NSViewController() },
        )
        defer {
            sourceCoordinator.close()
            duplicateCoordinator.close()
        }

        for tabID in duplicate.contentTabs.tabs.ids {
            let sourceManager = try XCTUnwrap(registry.undoManager(for: UndoManagerScope(
                windowID: sourceWindowID,
                contentTabID: tabID.rawValue,
            )))
            let duplicateManager = try XCTUnwrap(registry.undoManager(for: UndoManagerScope(
                windowID: duplicateWindowID,
                contentTabID: tabID.rawValue,
            )))
            XCTAssertNotIdentical(sourceManager, duplicateManager)
        }
    }

    static func isRenameAction(
        _ action: FileManagerContentAction,
        oldPath: String,
        newPath: String,
    ) -> Bool {
        guard case let .entryViewLayout(.entryOperations(.edit(.renameItem(receivedOldPath, receivedNewPath)))) = action
        else { return false }
        return receivedOldPath == oldPath && receivedNewPath == newPath
    }

    func makeClient() -> FileOperationUndoManagerClient {
        makeClient(registry: FileOperationUndoManagerRegistry())
    }

    func makeClient(registry: FileOperationUndoManagerRegistry) -> FileOperationUndoManagerClient {
        FileOperationUndoManagerClient.live(registry: registry)
    }

    func makeCoordinatorStore(
        state: FileManagerWindowState,
        client: FileOperationUndoManagerClient,
    ) -> StoreOf<FileManagerFeature> {
        Store(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileOperationUndoManagerClient = client
        }
    }

    func makeStore(
        state: FileManagerWindowState,
        client: FileOperationUndoManagerClient? = nil,
        entryFileOpsClient: EntryFileOpsClient = .previewValue,
        closeWindowActionCount: LockIsolated<Int>? = nil,
    ) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        TestStore(initialState: state) {
            CombineReducers {
                Reduce<FileManagerWindowState, FileManagerWindowAction> { _, action in
                    if case .closeWindow = action {
                        closeWindowActionCount?.withValue { $0 += 1 }
                    }
                    return .none
                }
                FileManagerFeature()
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryFileOpsClient = entryFileOpsClient
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
            if let client {
                $0.fileOperationUndoManagerClient = client
            }
        }
    }

    func makeRecord(_ name: String) -> EntryActionRecord {
        EntryActionRecord(
            operationKind: .rename,
            targets: [.init(beforePath: "/tmp/\(name)-old", afterPath: "/tmp/\(name)-new")],
        )
    }

    func makeSingleTabState(
        windowID: UUID,
        tabID: ContentTabID,
        isPinned: Bool = false,
    ) -> FileManagerWindowState {
        let content = makeContent(windowID: windowID, path: "/tmp/\(tabID.rawValue)")
        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: [makeTab(id: tabID, isPinned: isPinned)],
            activeTabID: tabID,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()
        return state
    }

    func makeTwoTabState(windowID: UUID, activeTabID: ContentTabID) -> FileManagerWindowState {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let contentA = makeContent(windowID: windowID, path: "/tmp/A")
        let contentB = makeContent(windowID: windowID, path: "/tmp/B")
        var state = FileManagerWindowState()
        state.contentTabs = ContentTabState(
            tabs: [makeTab(id: tabA), makeTab(id: tabB)],
            activeTabID: activeTabID,
        )
        state.content = activeTabID == tabA ? contentA : contentB
        state.tabContentStates = [tabA: contentA, tabB: contentB]
        state.syncContentTabSidebarItems()
        return state
    }

    func makeContent(windowID: UUID, path: String) -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.navigation.seedInitialFolderPath(path)
        content.entryViewLayout.entryOperations.windowID = windowID
        return content
    }

    func makeTab(id: ContentTabID, isPinned: Bool = false) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: .directory(path: "/tmp/\(id.rawValue)"),
            isPinned: isPinned,
            title: id.rawValue,
            iconName: "folder",
        )
    }
}

private actor EntryOperationSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = self.waiters
            self.waiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilWaiting() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
