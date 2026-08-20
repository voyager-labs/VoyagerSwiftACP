import ComposableArchitecture
import CoreServices
import Foundation
import VoyagerEntitiesAi
@_spi(Testing)
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

private actor DirectoryLoadSuspensionGate {
    enum Completion {
        case entries([EntryModel])
        case failure
    }

    private var continuation: CheckedContinuation<Completion, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async throws -> [EntryModel] {
        let completion = await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = entryWaiters
            entryWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        switch completion {
        case let .entries(entries):
            return entries
        case .failure:
            throw Failure.expected
        }
    }

    func waitUntilWaiting() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func resume(with completion: Completion) {
        continuation?.resume(returning: completion)
        continuation = nil
    }

    private enum Failure: Error {
        case expected
    }
}

private actor ComposerCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var wasCancelled = false

    func wait() async throws -> SearchResponsePayload {
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let waiters = startWaiters
                startWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            throw CancellationError()
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func cancellationObserved() -> Bool {
        wasCancelled
    }

    private func cancel() {
        wasCancelled = true
        continuation?.resume()
        continuation = nil
    }
}

private func makeCloseTestDirectoryTab(
    id: ContentTabID,
    path: String,
    title: String,
) -> ContentTabItem {
    ContentTabItem(
        id: id,
        page: .directory,
        anchor: .directory(path: path),
        isPinned: false,
        title: title,
        iconName: "folder",
    )
}

private func makeCloseTestHomeTab(id: ContentTabID) -> ContentTabItem {
    ContentTabItem(
        id: id,
        page: .home,
        anchor: .homeDefault,
        isPinned: false,
        title: "Home",
        iconName: "house",
    )
}

private func makeCloseTestDirectoryContent(path: String) -> FileManagerContentFeature.State {
    var content = FileManagerContentFeature.State()
    content.navigation.seedInitialFolderPath(path)
    return content
}

private func makeCloseTestState(
    tabs: [ContentTabItem],
    activeTabID: ContentTabID,
    previousActiveTabID: ContentTabID? = nil,
    contentStates: [ContentTabID: FileManagerContentFeature.State],
) -> FileManagerFeature.State {
    guard let activeContent = contentStates[activeTabID] else {
        preconditionFailure("Close test requires active content state")
    }
    var state = FileManagerFeature.State()
    state.contentTabs = ContentTabState(
        tabs: .init(uniqueElements: tabs),
        activeTabID: activeTabID,
        previousActiveTabID: previousActiveTabID,
        recentlyClosed: nil,
    )
    state.content = activeContent
    state.tabContentStates = contentStates
    state.syncContentTabSidebarItems()
    return state
}

private struct DirectoryLoadFailureRetryFixture {
    let homeID: ContentTabID
    let directoryID: ContentTabID
    let directoryPath: String
    let staleEntry: EntryModel
    let gate: DirectoryLoadSuspensionGate
    let loadPaths: LockIsolated<[String]>
    let eventContinuation: LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>
}

private struct InactiveDirectoryRestoreFixture {
    let homeID: ContentTabID
    let directoryID: ContentTabID
    let directoryPath: String
    let staleEntry: EntryModel
    let freshEntry: EntryModel
    let restoreGate: DirectoryLoadSuspensionGate
    let backingEntries: LockIsolated<[EntryModel]>
    let loadPaths: LockIsolated<[String]>
    let watchedRoots: LockIsolated<[[String]]>
    let removedInterestIDs: LockIsolated<Set<String>>
    let eventContinuation: LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>

    @MainActor
    init(makeState: (ContentTabID, ContentTabID, String) -> FileManagerFeature.State) {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let path = "/Users/test/Desktop"
        let stale = EntryModel.temporaryFolder(id: "\(path)/Stale", name: "Stale")
        let fresh = EntryModel.temporaryFolder(id: "\(path)/Fresh", name: "Fresh")
        let gate = DirectoryLoadSuspensionGate()
        let backing = LockIsolated<[EntryModel]>([stale])
        let loads = LockIsolated<[String]>([])
        let roots = LockIsolated<[[String]]>([])
        let removedIDs = LockIsolated<Set<String>>([])
        let continuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        var state = makeState(homeID, directoryID, path)
        state.tabContentStates[directoryID]?.entryViewLayout.mode = .grid
        state.tabContentStates[directoryID]?.entryViewLayout.entries = [stale]
        state.tabContentStates[directoryID]?.entryViewLayout.entryOperations.items = [stale]
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                let index = loads.withValue { paths in paths.append(url.path)
                    return paths.count
                }
                return index == 1 ? backing.value : try await gate.wait()
            }
            $0.fileChangeGatewayClient.updateInterests = { interests in
                roots.withValue { $0.append(contentsOf: interests.map(\.roots)) }
            }
            $0.fileChangeGatewayClient.removeInterests = { ids in removedIDs.withValue { $0.formUnion(ids) } }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { continuation.setValue($0) } }
        }
        store.exhaustivity = .off
        self.homeID = homeID
        self.directoryID = directoryID
        directoryPath = path
        staleEntry = stale
        freshEntry = fresh
        restoreGate = gate
        backingEntries = backing
        loadPaths = loads
        watchedRoots = roots
        removedInterestIDs = removedIDs
        eventContinuation = continuation
        self.store = store
    }
}

private struct SupersededDirectoryLoadFixture {
    let secondID: ContentTabID
    let firstPath: String
    let secondPath: String
    let staleEntry: EntryModel
    let preservedEntry: EntryModel
    let freshEntry: EntryModel
    let firstGate: DirectoryLoadSuspensionGate
    let secondGate: DirectoryLoadSuspensionGate
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>

    @MainActor
    init(makeState: (ContentTabID, ContentTabID, ContentTabID, String, String) -> FileManagerFeature.State) throws {
        let homeID = ContentTabID()
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let firstPath = "/Users/test/First"
        let secondPath = "/Users/test/Second"
        let stale = EntryModel.temporaryFolder(id: "\(firstPath)/Stale", name: "Stale")
        let preserved = EntryModel.temporaryFolder(id: "\(secondPath)/Preserved", name: "Preserved")
        let fresh = EntryModel.temporaryFolder(id: "\(secondPath)/Fresh", name: "Fresh")
        let firstGate = DirectoryLoadSuspensionGate()
        let secondGate = DirectoryLoadSuspensionGate()
        var state = makeState(homeID, firstID, secondID, firstPath, secondPath)
        state.contentTabs.activeTabID = firstID
        state.content = try XCTUnwrap(state.tabContentStates[firstID])
        state.tabContentStates[secondID]?.entryViewLayout.mode = .grid
        state.tabContentStates[secondID]?.entryViewLayout.entries = [preserved]
        state.tabContentStates[secondID]?.entryViewLayout.entryOperations.items = [preserved]
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                if url.path == firstPath { return try await firstGate.wait() }
                if url.path == secondPath { return try await secondGate.wait() }
                XCTFail("unexpected directory load: \(url.path)")
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = { AsyncStream { $0.finish() } }
        }
        store.exhaustivity = .off
        self.secondID = secondID
        self.firstPath = firstPath
        self.secondPath = secondPath
        staleEntry = stale
        preservedEntry = preserved
        freshEntry = fresh
        self.firstGate = firstGate
        self.secondGate = secondGate
        self.store = store
    }
}

private struct PinnedCollectionRestoreFixture {
    let collectionID: ContentTabID
    let collectionURL: URL
    let directoryLoadPaths: LockIsolated<[String]>
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>

    @MainActor
    init() {
        let homeID = ContentTabID()
        let collectionID = ContentTabID()
        let url = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let loads = LockIsolated<[String]>([])
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home
        var state = FileManagerFeature.State()
        state.contentTabs = Self.makeContentTabs(
            homeID: homeID,
            collectionID: collectionID,
            url: url,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.entryLoadingClient.loadItems = { url, _ in loads.withValue { $0.append(url.path) }
                return []
            }
        }
        store.exhaustivity = .off
        self.collectionID = collectionID
        collectionURL = url
        directoryLoadPaths = loads
        self.store = store
    }

    private static func makeContentTabs(
        homeID: ContentTabID,
        collectionID: ContentTabID,
        url: URL,
    ) -> ContentTabState {
        let collectionTab = ContentTabItem(
            id: collectionID,
            page: .collection,
            anchor: .collectionFile(url: url),
            isPinned: true,
            title: "Saved",
            iconName: "rectangle.stack",
        )
        let homeTab = ContentTabItem(
            id: homeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        )
        let pinnedRecord = ContentTabPinnedRecord(
            id: collectionID.rawValue,
            page: .collection,
            anchor: .collectionFile(url: url),
            title: "Saved",
            iconName: "rectangle.stack",
            pinnedAt: Date(timeIntervalSince1970: 1234),
        )
        return ContentTabState(
            tabs: [collectionTab, homeTab],
            activeTabID: homeID,
            recentlyClosed: nil,
            pinnedRecords: [collectionID: pinnedRecord],
        )
    }
}

private struct AiChatRestoreFixture {
    let sessionID: String
    let homeID: ContentTabID
    let directoryLoadPaths: LockIsolated<[String]>
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>

    @MainActor
    init() {
        let sessionID = "test-session-123"
        let homeID = ContentTabID()
        let loads = LockIsolated<[String]>([])
        var currentContent = FileManagerContentFeature.State()
        currentContent.navigation.seedInitialFolderPath("/Users/test/Current")
        var state = FileManagerFeature.State()
        let homeTab = ContentTabItem(
            id: homeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        )
        state.contentTabs = ContentTabState(
            tabs: [homeTab],
            activeTabID: homeID,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID),
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            ),
        )
        state.content = currentContent
        state.tabContentStates = [homeID: currentContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in loads.withValue { $0.append(url.path) }
                return []
            }
        }
        store.exhaustivity = .off
        self.sessionID = sessionID
        self.homeID = homeID
        directoryLoadPaths = loads
        self.store = store
    }
}

@MainActor
final class CTM005IndependentContentTabSessionTests: XCTestCase {
    // MARK: - CTM-005-independent_content_tab_session

    /// CTM-005-independent_content_tab_session: background content status는 일치하는 실행 소유자만 갱신한다.
    /// 화면 밖 content 실행의 activity status가 visible/parked content와 durable 상태를 건드리지 않는지 검증한다.
    /// - 검증 내용: matching status 전달, session/request/run identity guard, non-terminal owner 유지, persistence 미호출
    /// - 사전 조건: visible/parked content와 별도의 processing background content owner가 존재함
    /// - 기대 결과: matching owner의 activity만 갱신되고 mismatch와 visible state, tab, transcript, draft, autoscroll은 불변임
    func testBackgroundContentStatusRoutesOnlyToMatchingOwnerWithoutTerminalSideEffects() async {
        let fixture = makeBackgroundContentStatusFixture()
        let store = fixture.store

        await store.send(.backgroundAiChat(.executionEvent(.status(
            context: fixture.ownerLock.context,
            signal: fixture.signal,
        ))))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[fixture.ownerSessionID]?.aiChat.executionPhase,
            .processing(fixture.ownerLock.recordingActivity(fixture.signal)),
        )
        XCTAssertEqual(store.state.content, fixture.visibleContent)
        XCTAssertEqual(store.state.tabContentStates[fixture.parkedTabID], fixture.parkedContent)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.visibleTabID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.visibleTabID]?.title, "Visible chat")
        XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.parkedTabID]?.title, "Parked chat")
        XCTAssertEqual(fixture.savedSnapshots.value.count, 0)

        let afterMatchingStatus = store.state
        for context in mismatchedStatusContexts(for: fixture.ownerLock) {
            await store.send(.backgroundAiChat(.executionEvent(.status(
                context: context,
                signal: fixture.signal,
            ))))
            XCTAssertEqual(store.state, afterMatchingStatus)
        }

        XCTAssertNotNil(store.state.backgroundAiChatStates[fixture.ownerSessionID])
        XCTAssertEqual(fixture.savedSnapshots.value.count, 0)
    }

    /// CTM-005-independent_content_tab_session: background inspector status는 inspector 소유 경로로 전달한다.
    /// 화면 밖 inspector 실행의 status가 active/parked inspector와 content state를 변경하지 않는지 검증한다.
    /// - 검증 내용: background inspector identity routing과 non-terminal owner 유지
    /// - 사전 조건: active/parked inspector와 별도의 processing background inspector owner가 존재함
    /// - 기대 결과: matching background inspector activity만 갱신되고 다른 inspector와 content는 불변임
    func testBackgroundInspectorStatusRoutesToMatchingOwnerWithoutPromotionOrRemoval() async {
        let fixture = makeBackgroundInspectorStatusFixture()
        let store = fixture.store

        await store.send(.inspector(.aiChat(.executionEvent(.status(
            context: fixture.ownerLock.context,
            signal: fixture.signal,
        )))))

        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[fixture.ownerSessionID]?.aiChat.executionPhase,
            .processing(fixture.ownerLock.recordingActivity(fixture.signal)),
        )
        XCTAssertEqual(store.state.inspector, fixture.activeInspector)
        XCTAssertEqual(
            store.state.tabInspectorStates[fixture.parkedTabID],
            fixture.parkedInspector.tabSnapshot(),
        )
        XCTAssertEqual(store.state.content, fixture.content)
        XCTAssertNotNil(store.state.backgroundInspectorAiChatStates[fixture.ownerSessionID])
        XCTAssertNil(store.state.backgroundAiChatStates[fixture.ownerSessionID])
    }

    /// CTM-005-independent_content_tab_session (VOY-578): inactive watcher gap 이후 Directory snapshot을 reload함
    /// Directory watcher가 중단된 동안 발생해 event로 전달되지 않은 backing mutation을 복원 시 재검증한다.
    /// - 검증 내용: 저장 presentation 즉시 복원, 정확히 한 번 loadItems 실행, fresh entries commit, watcher 재시작
    /// - 사전 조건: active Directory를 Home으로 전환해 watcher를 취소한 뒤 dependency backing entries만 변경함
    /// - 기대 결과: reload 대기 중 기존 entries/layout이 보이고 완료 후 fresh entries로 교체됨
    func testSwitchingTabsRestoresContentSessionAndRestartsFolderWatcher() async {
        let fixture = InactiveDirectoryRestoreFixture { homeID, directoryID, path in
            self.makeDirectoryHandoffState(
                homeID: homeID,
                tabs: [.init(id: directoryID, anchorPath: path, savedPath: path)],
            )
        }
        let store = fixture.store

        await store.send(.contentTabs(.setCurrent(fixture.directoryID)))
        await receiveDirectoryReload(tabID: fixture.directoryID, path: fixture.directoryPath, store: store)
        await receiveItemsLoaded(tabID: fixture.directoryID, store: store)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.staleEntry])
        XCTAssertEqual(fixture.watchedRoots.value, [[fixture.directoryPath]])

        await store.send(.contentTabs(.setCurrent(fixture.homeID)))
        await receiveHomeReload(tabID: fixture.homeID, store: store)
        XCTAssertEqual(fixture.removedInterestIDs.value.count, 1)

        fixture.backingEntries.setValue([fixture.freshEntry])
        let loadCountBeforeRestore = fixture.loadPaths.value.count
        await store.send(.contentTabs(.setCurrent(fixture.directoryID)))
        await receiveDirectoryReload(tabID: fixture.directoryID, path: fixture.directoryPath, store: store)
        await fixture.restoreGate.waitUntilWaiting()
        assertRestoredDirectoryPresentation(fixture, store: store)

        await fixture.restoreGate.resume(with: .entries(fixture.backingEntries.value))
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .entryViewLayout(.view(.applyContentProjection(projection))),
            ) = action else { return false }
            return receivedTabID == fixture.directoryID && projection.entries == [fixture.freshEntry]
        }
        assertFreshDirectoryReload(fixture, loadCountBeforeRestore: loadCountBeforeRestore, store: store)

        fixture.eventContinuation.value?.finish()
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session (VOY-578): same-path reload 실패 후 복원할 때 다시 load함
    /// 실패한 Directory reload가 이후 동일 snapshot 복원의 freshness를 보장한 것으로 간주되지 않는지 검증한다.
    /// - 검증 내용: 첫 reload 실패, 두 번째 빈 성공, 세 번째 복원에서도 loadItems 재실행
    /// - 사전 조건: 저장 entries가 있는 Directory snapshot과 continuation 기반 실패/성공 loader
    /// - 기대 결과: 모든 Directory 복원마다 load가 한 번 실행되고 실패 중에는 저장 presentation이 유지됨
    func testDirectoryReloadFailureRetriesAndSuccessfulEmptySnapshotReloadsAgain() async {
        await verifyDirectoryReloadFailureRetriesAndReloadsSuccessfulEmptySnapshot()
    }

    /// CTM-005-independent_content_tab_session (VOY-578): 저장 snapshot이 없으면 기존 Directory load 경로를 유지함
    /// 새로 복원할 content state가 없는 Directory tab도 기존 resync/load 경로를 사용하는지 검증한다.
    /// - 검증 내용: target tabContentStates 누락 시 applyNavigationState와 loadItems 실행
    /// - 사전 조건: target anchor는 Directory지만 target tab ID의 저장 content state가 없음
    /// - 기대 결과: target Directory 경로를 한 번 load하고 watcher를 시작함
    func testSwitchingToDirectoryWithoutSnapshotFallsBackToLoad() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/MissingSnapshot"
        let loadPaths = LockIsolated<[String]>([])
        let state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [.init(id: directoryID, anchorPath: directoryPath, savedPath: nil)],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: full resync의 child action 전체보다 VOY-578 fallback load 호출을 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)

        XCTAssertEqual(loadPaths.value, [directoryPath])
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session (VOY-578): anchor와 저장 route가 다르면 기존 Directory load 경로를 유지함
    /// 다른 폴더의 저장 snapshot을 target Directory에 재사용하지 않고 anchor 기준으로 다시 동기화하는 회귀를 검증한다.
    /// - 검증 내용: Directory anchor/folder route 표준화 경로 불일치 시 loadItems 실행
    /// - 사전 조건: target tabContentStates는 존재하지만 saved folder path가 target anchor와 다름
    /// - 기대 결과: 저장 entries 최적화를 사용하지 않고 target anchor 경로를 한 번 load함
    func testSwitchingToDirectoryWithMismatchedSnapshotFallsBackToLoad() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Target"
        let loadPaths = LockIsolated<[String]>([])
        let state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [.init(id: directoryID, anchorPath: directoryPath, savedPath: "/Users/test/Stale")],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return []
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: full resync의 child action 전체보다 VOY-578 mismatch fallback 호출을 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)

        XCTAssertEqual(loadPaths.value, [directoryPath])
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session (VOY-578): 빠른 Directory 전환은 취소된 stale 응답을 거부함
    /// A reload가 취소를 무시하고 늦게 반환해도 B의 저장 presentation과 최신 응답만 commit되는지 검증한다.
    /// - 검증 내용: A load 보류, B 전환/reload, A stale 완료, B fresh 완료 순서의 cancellation safety
    /// - 사전 조건: A/B별 checked continuation loader와 B에 저장된 grid snapshot
    /// - 기대 결과: B reload 대기 중 snapshot 유지, A 응답 미반영, B fresh entries만 최종 반영
    func testCancelledDirectoryLoadResponseDoesNotOverwriteRestoredSnapshot() async throws {
        let fixture = try SupersededDirectoryLoadFixture { homeID, firstID, secondID, firstPath, secondPath in
            self.makeDirectoryHandoffState(
                homeID: homeID,
                tabs: [
                    .init(id: firstID, anchorPath: firstPath, savedPath: firstPath),
                    .init(id: secondID, anchorPath: secondPath, savedPath: secondPath),
                ],
            )
        }
        let store = fixture.store

        await store.sendTabContent(.entryViewLayout(.entryOperations(.loading(
            .loadItems(path: fixture.firstPath, showHidden: false),
        ))))
        await fixture.firstGate.waitUntilWaiting()
        await store.send(.contentTabs(.setCurrent(fixture.secondID)))
        await receiveDirectoryReload(tabID: fixture.secondID, path: fixture.secondPath, store: store)
        await fixture.secondGate.waitUntilWaiting()
        XCTAssertEqual(store.state.content.entryViewLayout.mode, .grid)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.preservedEntry])

        await fixture.firstGate.resume(with: .entries([fixture.staleEntry]))
        await fixture.secondGate.resume(with: .entries([fixture.freshEntry]))
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .entryViewLayout(.view(.applyContentProjection(projection))),
            ) = action else { return false }
            return receivedTabID == fixture.secondID && projection.entries == [fixture.freshEntry]
        }
        await store.finish()
        assertFreshSupersededDirectoryLoad(fixture, store: store)
    }

    /// CTM-005-independent_content_tab_session (VOY-578): 진행 중 Directory snapshot은 재진입마다 reload함
    /// 경로 전환 load가 취소된 snapshot과 성공한 빈 snapshot 모두 다음 복원에서 다시 검증되는지 확인한다.
    /// - 검증 내용: B load 보류·이탈·재진입 성공·재이탈·재진입의 세 번 load
    /// - 사전 조건: A entries가 보이는 상태에서 B 첫 load가 checked continuation에서 대기함
    /// - 기대 결과: 취소 응답은 저장 snapshot을 덮지 않고 B 복원마다 loadItems가 실행됨
    func testInFlightDirectorySnapshotReloadsOnEveryRoundTrip() async throws {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let firstPath = "/Users/test/First"
        let secondPath = "/Users/test/Second"
        let firstEntry = EntryModel.temporaryFolder(id: "\(firstPath)/First", name: "First")
        let lateEntry = EntryModel.temporaryFolder(id: "\(secondPath)/Late", name: "Late")
        let gate = DirectoryLoadSuspensionGate()
        let loadPaths = LockIsolated<[String]>([])
        let store = try makeInFlightDirectoryLifecycleStore(
            homeID: homeID,
            directoryID: directoryID,
            firstPath: firstPath,
            gate: gate,
            loadPaths: loadPaths,
        )
        // store.exhaustivity = .off: 실제 navigation/tab handoff의 부수 action보다 VOY-578 reload lifecycle에 집중함
        store.exhaustivity = .off

        await store.send(.navigation(.view(.navigateToPath(secondPath))))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(secondPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await gate.waitUntilWaiting()
        XCTAssertEqual(store.state.contentTabs.tabs[id: directoryID]?.anchor, .directory(path: secondPath))
        XCTAssertEqual(store.state.content.entryViewLayout.entries.map(\.fullPath), [firstEntry.fullPath])

        await store.send(.contentTabs(.setCurrent(homeID)))
        let savedInFlightSnapshot = try XCTUnwrap(store.state.tabContentStates[directoryID])
        XCTAssertEqual(savedInFlightSnapshot.navigation.currentPath, secondPath)
        XCTAssertEqual(savedInFlightSnapshot.entryViewLayout.entries.map(\.fullPath), [firstEntry.fullPath])
        await gate.resume(with: .entries([lateEntry]))
        await store.skipReceivedActions()
        XCTAssertEqual(
            store.state.tabContentStates[directoryID]?.entryViewLayout.entries.map(\.fullPath),
            [firstEntry.fullPath],
        )

        await store.send(.contentTabs(.setCurrent(directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(secondPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContentCoreBatch()
        XCTAssertEqual(loadPaths.value, [secondPath, secondPath])
        XCTAssertTrue(store.state.content.entryViewLayout.entries.isEmpty)

        await store.send(.contentTabs(.setCurrent(homeID)))
        await store.skipReceivedActions()
        await store.send(.contentTabs(.setCurrent(directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(secondPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContentCoreBatch()
        XCTAssertEqual(loadPaths.value, [secondPath, secondPath, secondPath])
        XCTAssertTrue(store.state.content.entryViewLayout.entries.isEmpty)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session (VOY-578): matching Directory snapshot도 fresh entries로 reload함
    /// anchor와 저장 route가 같아도 inactive gap의 backing mutation을 놓치지 않도록 path만으로 freshness를 판단하지 않는다.
    /// - 검증 내용: 저장 stale entries를 동기 복원한 뒤 target path loadItems 실행
    /// - 사전 조건: target Directory와 같은 route를 가진 stale snapshot
    /// - 기대 결과: reload 대기 중 stale entries가 유지되고 완료 후 loaded entries로 교체됨
    func testIncompleteDirectorySnapshotFallsBackToLoad() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Target"
        let staleEntry = EntryModel.temporaryFolder(id: "\(directoryPath)/Stale", name: "Stale")
        let loadedEntry = EntryModel.temporaryFolder(id: "\(directoryPath)/Loaded", name: "Loaded")
        let gate = DirectoryLoadSuspensionGate()
        let loadPaths = LockIsolated<[String]>([])
        var state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [.init(id: directoryID, anchorPath: directoryPath, savedPath: directoryPath)],
        )
        state.tabContentStates[directoryID]?.entryViewLayout.entries = [staleEntry]
        state.tabContentStates[directoryID]?.entryViewLayout.entryOperations.items = [staleEntry]

        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return try await gate.wait()
            }
            dependencies.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        // store.exhaustivity = .off: handoff 부수 action보다 VOY-578 restored snapshot reload 계약에 집중함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await gate.waitUntilWaiting()
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [staleEntry])

        await gate.resume(with: .entries([loadedEntry]))
        await store.receiveTabContentCoreBatch()
        await store.finish()

        XCTAssertEqual(loadPaths.value, [directoryPath])
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [loadedEntry])
    }

    /// CTM-005-independent_content_tab_session (VOY-578): 빠른 Directory handoff는 매번 reload하고 이전 watcher를 취소함
    /// 연속 tab 전환에서도 cancel-old-before-resync 순서와 최신 watcher 소유권을 결정적으로 검증한다.
    /// - 검증 내용: A load/start, A watcher stop, B load/start 순서와 경로별 load 1회
    /// - 사전 조건: 서로 다른 두 Directory tab snapshot과 event를 방출하지 않는 gateway stream
    /// - 기대 결과: 각 경로를 한 번 reload하고 최종 watcher와 active content가 B를 가리킴
    func testRapidValidSnapshotHandoffSupersedesPreviousFolderWatcher() async {
        let homeID = ContentTabID()
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let firstPath = "/Users/test/First"
        let secondPath = "/Users/test/Second"
        let loadPaths = LockIsolated<[String]>([])
        let watcherEvents = LockIsolated<[String]>([])
        let removedInterestIDs = LockIsolated<Set<String>>([])
        let state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [
                .init(id: firstID, anchorPath: firstPath, savedPath: firstPath),
                .init(id: secondID, anchorPath: secondPath, savedPath: secondPath),
            ],
        )
        let store = makeSupersedingWatcherStore(
            state: state,
            loadPaths: loadPaths,
            watcherEvents: watcherEvents,
            removedInterestIDs: removedInterestIDs,
        )
        // store.exhaustivity = .off: 연속 handoff 부수 action보다 reload와 watcher 취소 순서에 집중함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(firstID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(firstPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)

        await store.send(.contentTabs(.setCurrent(secondID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(secondPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)

        XCTAssertEqual(loadPaths.value, [firstPath, secondPath])
        XCTAssertEqual(store.state.contentTabs.activeTabID, secondID)
        XCTAssertEqual(store.state.content.navigation.currentPath, secondPath)
        XCTAssertEqual(Array(watcherEvents.value.prefix(3)), ["start:\(firstPath)", "stop", "start:\(secondPath)"])
        await store.sendTabContent(.internal(.stopObservingSystemNotifications))
        XCTAssertEqual(watcherEvents.value, ["start:\(firstPath)", "stop", "start:\(secondPath)", "stop"])
        await store.finish()
    }

    /// CTM-005-preserve_independent_content_tab_sessions (VOY-578): Collection 복원은 Directory load를 호출하지 않음
    /// Directory snapshot revalidation 변경이 Collection file handoff를 침범하지 않는지 검증한다.
    /// - 검증 내용: pinned Collection 전환 시 openCollectionFile 전송과 Directory loadItems 0회
    /// - 사전 조건: Home active, pinned Collection file anchor, 저장 content state 없음
    /// - 기대 결과: collection URL open 경로만 사용하고 entryLoadingClient.loadItems를 호출하지 않음
    func testSwitchingToPinnedCollectionTabOpensCollectionFile() async {
        let fixture = PinnedCollectionRestoreFixture()
        await fixture.store.send(.contentTabs(.setCurrent(fixture.collectionID)))
        await fixture.store.receive(\.navigation.view.openCollectionFile, fixture.collectionURL)
        XCTAssertTrue(fixture.directoryLoadPaths.value.isEmpty)
    }

    func testSwitchingDirectoryTabsSyncsLegacySidebarSelectionFromRestoredSession() async {
        let projectsID = ContentTabID()
        let downloadsID = ContentTabID()
        let projectsPath = "/Users/test/Projects"
        let downloadsPath = "/Users/test/Downloads"
        var projectsContent = FileManagerContentFeature.State()
        projectsContent.navigation.seedInitialFolderPath(projectsPath)
        var downloadsContent = FileManagerContentFeature.State()
        downloadsContent.navigation.seedInitialFolderPath(downloadsPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: projectsID,
                    page: .directory,
                    anchor: .directory(path: projectsPath),
                    isPinned: false,
                    title: "Projects",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: downloadsID,
                    page: .directory,
                    anchor: .directory(path: downloadsPath),
                    isPinned: false,
                    title: "Downloads",
                    iconName: "arrow.down.circle",
                ),
            ],
            activeTabID: projectsID,
            recentlyClosed: nil,
        )
        state.content = projectsContent
        state.tabContentStates = [projectsID: projectsContent, downloadsID: downloadsContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(downloadsID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, downloadsID)
        XCTAssertEqual(
            store.state.sidebar.contentTabSidebarItems.first(where: { $0.id == downloadsID })?.isActive,
            true,
        )

        await store.send(.contentTabs(.setCurrent(projectsID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, projectsID)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first(where: { $0.id == projectsID })?.isActive, true)

        await store.finish()
    }

    func testSwitchingTabsClearsInFlightComposerStateBeforeSavingPreviousSession() async {
        let searchID = UUID()
        let filtersID = UUID()
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Documents"
        var homeContent = FileManagerContentFeature.State()
        homeContent.composer.isLoadingSearch = true
        homeContent.composer.isLoadingFilters = true
        homeContent.composer.isFilteringInFlight = true
        homeContent.composer.activeSearchRequestID = searchID
        homeContent.composer.activeFiltersRequestID = filtersID
        homeContent.composer.lastAcceptedSearchRequestID = searchID
        homeContent.composer.lastAcceptedFiltersRequestID = filtersID
        homeContent.composer.pendingSearchQuery = "tag:important"
        homeContent.composer.queryRenderPhase = .searching
        homeContent.composer.searchStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        homeContent.composer.filtersStartedAt = Date(timeIntervalSince1970: 1_700_000_001)
        homeContent.composer.transientFeedback = ComposerTransientFeedback(
            id: UUID(),
            kind: .error,
            message: "failure",
        )
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(directoryID)))

        guard let savedHomeComposer = store.state.tabContentStates[homeID]?.composer else {
            XCTFail("Expected previous tab content session to be saved")
            return
        }
        XCTAssertFalse(savedHomeComposer.isLoadingSearch)
        XCTAssertFalse(savedHomeComposer.isLoadingFilters)
        XCTAssertFalse(savedHomeComposer.isFilteringInFlight)
        XCTAssertNil(savedHomeComposer.activeSearchRequestID)
        XCTAssertNil(savedHomeComposer.activeFiltersRequestID)
        XCTAssertNil(savedHomeComposer.lastAcceptedSearchRequestID)
        XCTAssertNil(savedHomeComposer.lastAcceptedFiltersRequestID)
        XCTAssertNil(savedHomeComposer.pendingSearchQuery)
        XCTAssertNil(savedHomeComposer.searchStartedAt)
        XCTAssertNil(savedHomeComposer.filtersStartedAt)
        XCTAssertNil(savedHomeComposer.transientFeedback)
        XCTAssertEqual(savedHomeComposer.queryRenderPhase, .idle)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: dirty collection discard는 Composer feedback timer를 취소함
    /// discard 시 page-owned search/filter lifecycle을 보존하면서 Composer semantic action으로 feedback timer 정리를 위임하는지 검증한다.
    /// - 검증 내용: live feedback timer 취소, clearTransientFeedback action 전달 및 활성 search/filter 상태 보존
    /// - 사전 조건: dirty collection content에 search/filter process와 transient feedback이 남아 있음
    /// - 기대 결과: FileManager가 raw cancellation ID 없이 Composer clearTransientFeedback을 실행하고 process 상태를 유지함
    func testDiscardCollectionChangesRoutesComposerTransientFeedbackCleanup() async {
        var initialState = makeDirtyCollectionContent()
        let searchID = UUID()
        let filtersID = UUID()
        initialState.composer.isLoadingSearch = true
        initialState.composer.isLoadingFilters = true
        initialState.composer.isFilteringInFlight = true
        initialState.composer.activeSearchRequestID = searchID
        initialState.composer.activeFiltersRequestID = filtersID
        initialState.composer.lastAcceptedSearchRequestID = searchID
        initialState.composer.lastAcceptedFiltersRequestID = filtersID
        initialState.composer.pendingSearchQuery = "pending query"
        initialState.composer.searchStartedAt = Date(timeIntervalSince1970: 1_700_000_000)
        initialState.composer.filtersStartedAt = Date(timeIntervalSince1970: 1_700_000_001)
        let feedback = ComposerTransientFeedback(id: UUID(), kind: .error, message: "failure")
        let clock = TestClock()
        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = clock
        }
        // store.exhaustivity = .off: collection teardown의 Composer 경계 action만 검증한다.
        store.exhaustivity = .off

        await store.send(.composer(.internal(.presentTransientFeedback(feedback))))
        await store.send(.view(.discardCollectionChanges))
        await store.receive(\.composer.internal.clearTransientFeedback)
        await clock.advance(by: .seconds(4))
        await store.finish()

        XCTAssertNil(store.state.composer.transientFeedback)
        XCTAssertTrue(store.state.composer.isLoadingSearch)
        XCTAssertTrue(store.state.composer.isLoadingFilters)
        XCTAssertTrue(store.state.composer.isFilteringInFlight)
        XCTAssertEqual(store.state.composer.activeSearchRequestID, searchID)
        XCTAssertEqual(store.state.composer.activeFiltersRequestID, filtersID)
        XCTAssertEqual(store.state.composer.lastAcceptedSearchRequestID, searchID)
        XCTAssertEqual(store.state.composer.lastAcceptedFiltersRequestID, filtersID)
        XCTAssertEqual(store.state.composer.pendingSearchQuery, "pending query")
        XCTAssertEqual(store.state.composer.searchStartedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(store.state.composer.filtersStartedAt, Date(timeIntervalSince1970: 1_700_000_001))
    }

    /// CTM-005-independent_content_tab_session: pinned active anchor resync는 Composer 실행 작업을 정리함
    /// durable pinned anchor가 active runtime anchor를 대체할 때 outgoing Composer cleanup을 먼저 수행하는지 검증한다.
    /// - 검증 내용: search/filter effect 취소, process 상태 초기화, stale response 무시
    /// - 사전 조건: 동일 active tab ID가 directory에서 collection file anchor로 resync되고 search/filter가 실행 중임
    /// - 기대 결과: 복원된 content는 cleanup 상태를 유지하고 이전 request response에 의해 변경되지 않음
    func testApplyPinnedContentTabsResyncCleansOutgoingComposerWork() async throws {
        let tabID = ContentTabID(rawValue: "pinned-resync")
        let collectionURL = URL(fileURLWithPath: "/tmp/Resynced.voycoll")
        let searchGate = ComposerCancellationGate()
        let filtersGate = ComposerCancellationGate()
        let state = Self.makePinnedResyncSourceState(tabID: tabID)
        let restoredState = Self.makePinnedResyncTargetState(tabID: tabID, collectionURL: collectionURL)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.searchClient.search = { _ in try await searchGate.wait() }
            $0.searchClient.applyFilters = { _ in try await filtersGate.wait() }
        }
        // store.exhaustivity = .off: UUID 기반 request와 collection open 후속 action보다 lifecycle 경계를 검증한다.
        store.exhaustivity = .off

        await store.send(.tabContent(tabID: tabID, action: .composer(.submit)))
        await searchGate.waitUntilStarted()
        let searchID = try XCTUnwrap(store.state.content.composer.activeSearchRequestID)
        await store.send(.tabContent(tabID: tabID, action: .composer(.applyFilters)))
        await filtersGate.waitUntilStarted()
        let filtersID = try XCTUnwrap(store.state.content.composer.activeFiltersRequestID)

        await store.send(.applyPinnedContentTabs(restoredState))

        XCTAssertFalse(store.state.content.composer.isLoadingSearch)
        XCTAssertFalse(store.state.content.composer.isLoadingFilters)
        XCTAssertFalse(store.state.content.composer.isFilteringInFlight)
        XCTAssertNil(store.state.content.composer.activeSearchRequestID)
        XCTAssertNil(store.state.content.composer.activeFiltersRequestID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .collectionFile(url: collectionURL))
        let searchCancelled = await searchGate.cancellationObserved()
        let filtersCancelled = await filtersGate.cancellationObserved()
        XCTAssertTrue(searchCancelled)
        XCTAssertTrue(filtersCancelled)

        await store.send(.tabContent(tabID: tabID, action: .composer(.internal(.searchResponse(
            searchID,
            .success(SearchResponsePayload(itemCount: 99)),
        )))))
        await store.send(.tabContent(tabID: tabID, action: .composer(.internal(.filtersResponse(
            filtersID,
            .success(SearchResponsePayload(itemCount: 99)),
        )))))
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
    }

    private static func makePinnedResyncSourceState(tabID: ContentTabID) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.composer.text = "find invoices"
        state.content.composer.scopes = ["/Users/test/Documents"]
        state.content.composer.conditionEditors = [
            ConditionEditorState(
                id: UUID(),
                condition: Condition(
                    property: .init(
                        key: "kind",
                        label: "Kind",
                        type: .string,
                        unitContract: nil,
                        operatorOptions: [.init(code: "eq", label: "Equals")],
                    ),
                    operation: .init(
                        code: "eq",
                        label: "Equals",
                        valueContract: .init(shape: .single, count: .fixed(1), input: .singleText),
                    ),
                    values: ["pdf"],
                    availability: .available,
                    opaqueSource: nil,
                ),
            ),
        ]
        state.syncActiveTabContentState()
        return state
    }

    private static func makePinnedResyncTargetState(
        tabID: ContentTabID,
        collectionURL: URL,
    ) -> ContentTabState {
        ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: true,
                    title: "Resynced",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
    }

    func testSwitchingTagTabNamedRecentsPreservesTagRouteKind() async {
        let homeID = ContentTabID()
        let tagID = ContentTabID()
        let tagName = "Recents"
        var tagContent = FileManagerContentFeature.State()
        tagContent.navigation.navigationState = .tags(tagName)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: tagID,
                    page: .collection,
                    anchor: .virtualCollection(id: tagName),
                    isPinned: false,
                    title: tagName,
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.tabContentStates = [tagID: tagContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tagID)))
        await store.receiveTabContent(\.internal.applyNavigationState)

        XCTAssertEqual(store.state.content.navigation.navigationState, .tags(tagName))
        XCTAssertNotEqual(store.state.content.navigation.navigationState, .recents)
        await store.finish()
    }

    func testOpeningNewContentTabClearsEntryLoadingStateBeforeSavingPreviousSession() async {
        let homeID = ContentTabID()
        let existingPath = "/Users/test/Loading"
        var existingContent = FileManagerContentFeature.State()
        existingContent.navigation.seedInitialFolderPath(existingPath)
        existingContent.entryViewLayout.entryOperations.isLoading = true
        existingContent.entryViewLayout.entryOperations.isReloading = true
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .directory,
                anchor: .directory(path: existingPath),
                isPinned: false,
                title: "Loading",
                iconName: "folder",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = existingContent
        state.tabContentStates = [homeID: existingContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        let savedEntryOperations = store.state.tabContentStates[homeID]?.entryViewLayout.entryOperations
        XCTAssertFalse(savedEntryOperations?.isLoading ?? true)
        XCTAssertFalse(savedEntryOperations?.isReloading ?? true)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        await store.finish()
    }

    func testOpeningNewContentTabDuringPendingCloseReconcilesSelectionAfterRollback() async {
        let pendingTabID = ContentTabID(rawValue: "pending-close-tab")
        let staleSelectionID = ContentTabID(rawValue: "stale-selection")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pendingTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: pendingTabID,
        )
        state.pendingContentTabClose = PendingContentTabClose(tabID: pendingTabID)
        state.contentTabs.selectedTabIDs = [pendingTabID, staleSelectionID]
        state.contentTabs.selectionAnchorID = staleSelectionID
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        XCTAssertEqual(store.state.contentTabs.tabs.map(\.id), [pendingTabID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, pendingTabID)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [pendingTabID])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, pendingTabID)
        await store.finish()
    }

    func testOpeningNewContentTabAppliesWindowContextToFreshContent() async {
        let homeID = ContentTabID()
        let windowID = UUID()
        var existingContent = FileManagerContentFeature.State()
        existingContent.entryViewLayout.mode = .grid
        existingContent.entryViewLayout.showHiddenFiles = true
        existingContent.entryViewLayout.listIconSize = 18
        existingContent.entryViewLayout.gridIconSize = 96
        existingContent.entryViewLayout.entryOperations.windowID = windowID
        existingContent.composer.cancellationOwnerID = windowID
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = existingContent
        state.tabContentStates = [homeID: existingContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.entryViewLayout.entryOperations.windowID, windowID)
        XCTAssertEqual(store.state.content.composer.cancellationOwnerID, windowID)
        XCTAssertEqual(store.state.content.entryViewLayout.mode, .grid)
        XCTAssertTrue(store.state.content.entryViewLayout.showHiddenFiles)
        XCTAssertEqual(store.state.content.entryViewLayout.listIconSize, 18)
        XCTAssertEqual(store.state.content.entryViewLayout.gridIconSize, 96)
        await store.finish()
    }

    func testOpeningNewContentTabSavesPreviousSessionAndCreatesFreshHomeSession() async {
        let homeID = ContentTabID()
        let existingPath = "/Users/test/Existing"
        var existingContent = FileManagerContentFeature.State()
        existingContent.navigation.seedInitialFolderPath(existingPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = existingContent
        state.tabContentStates = [homeID: existingContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 새 ContentTabID는 reducer 내부에서 생성되므로 결과 invariant를 직접 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.open(.homeDefault)))

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, existingPath)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        await store.finish()
    }

    func testRestoringDirectoryTabInitializesContentSessionFromRestoredAnchor() async {
        let homeID = ContentTabID()
        let currentPath = "/Users/test/Current"
        let restoredPath = "/Users/test/Restored"
        var currentContent = FileManagerContentFeature.State()
        currentContent.navigation.seedInitialFolderPath(currentPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: ClosedContentTabSnapshot(
                page: .directory,
                anchor: .directory(path: restoredPath),
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 1_234_567_890),
            ),
        )
        state.content = currentContent
        state.tabContentStates = [homeID: currentContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // restore는 reducer 내부에서 새 ContentTabID를 생성하므로 결과 invariant를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.restore))

        guard let activeTabID = store.state.contentTabs.activeTabID else {
            XCTFail("restore should activate a restored tab")
            return
        }
        XCTAssertNotEqual(activeTabID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .directory(path: restoredPath))
        XCTAssertEqual(store.state.content.navigation.currentPath, restoredPath)
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, currentPath)
        XCTAssertEqual(store.state.tabContentStates[activeTabID]?.navigation.currentPath, restoredPath)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: active tab close 시 닫힌 session의 load 취소
    /// 탭 state 제거 전에 닫힌 active tab의 loading cancellation owner를 사용해 effect를 종료하는지 검증한다.
    /// - 검증 내용: active tab load cancellation 1회와 fallback tab session 보존
    /// - 사전 조건: active Directory load가 대기 중이고 fallback Home tab이 존재함
    /// - 기대 결과: 닫힌 tab load만 취소되고 fallback tab이 active로 복원됨
    func testActiveCloseCancelsClosedTabLoad() async {
        let fallbackID = ContentTabID(rawValue: "fallback")
        let activeID = ContentTabID(rawValue: "active")
        let activePath = "/Users/test/Active"
        let loadStarted = expectation(description: "active tab load started")
        let loadCancelled = expectation(description: "active tab load cancelled")
        let loadGate = AsyncStream<Void>.makeStream()
        let cancellationCount = LockIsolated(0)
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestHomeTab(id: fallbackID),
                makeCloseTestDirectoryTab(id: activeID, path: activePath, title: "Active"),
            ],
            activeTabID: activeID,
            previousActiveTabID: fallbackID,
            contentStates: [
                fallbackID: FileManagerContentFeature.State(),
                activeID: makeCloseTestDirectoryContent(path: activePath),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in
                loadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in loadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    loadGate.continuation.finish()
                    loadCancelled.fulfill()
                }
            }
        }
        // store.exhaustivity = .off: close 부수 action보다 닫힌 tab loading cancellation을 검증한다.
        store.exhaustivity = .off

        await store.sendTabContent(.entryViewLayout(.entryOperations(.loading(
            .loadItems(path: activePath, showHidden: false),
        ))))
        await fulfillment(of: [loadStarted], timeout: 1)
        await store.send(.contentTabs(.close(activeID)))
        await fulfillment(of: [loadCancelled], timeout: 1)
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fallbackID)
        XCTAssertNil(store.state.tabContentStates[activeID])
    }

    /// CTM-005-independent_content_tab_session: inactive tab close 시 닫힌 load 취소
    /// 비활성 session 제거 전에 해당 loading owner의 effect를 종료하는지 검증한다.
    /// - 검증 내용: inactive tab load cancellation 1회와 active session 보존
    /// - 사전 조건: inactive Directory load가 대기 중이고 다른 Directory tab이 active임
    /// - 기대 결과: 닫힌 inactive tab의 load와 state만 제거됨
    func testInactiveCloseCancelsClosedTabLoad() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        let inactivePath = "/Users/test/Inactive"
        let loadStarted = expectation(description: "inactive tab load started")
        let loadCancelled = expectation(description: "inactive tab load cancelled")
        let loadGate = AsyncStream<Void>.makeStream()
        let cancellationCount = LockIsolated(0)
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestDirectoryTab(id: activeID, path: "/Users/test/Active", title: "Active"),
                makeCloseTestDirectoryTab(id: inactiveID, path: inactivePath, title: "Inactive"),
            ],
            activeTabID: activeID,
            contentStates: [
                activeID: makeCloseTestDirectoryContent(path: "/Users/test/Active"),
                inactiveID: makeCloseTestDirectoryContent(path: inactivePath),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in
                loadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in loadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    loadGate.continuation.finish()
                    loadCancelled.fulfill()
                }
            }
        }
        // store.exhaustivity = .off: inactive close 부수 action보다 닫힌 tab loading cancellation을 검증한다.
        store.exhaustivity = .off

        await store.send(.tabContent(
            tabID: inactiveID,
            action: .entryViewLayout(.entryOperations(.loading(
                .loadItems(path: inactivePath, showHidden: false),
            ))),
        ))
        await fulfillment(of: [loadStarted], timeout: 1)
        await store.send(.contentTabs(.close(inactiveID)))
        await fulfillment(of: [loadCancelled], timeout: 1)
        await store.finish()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
    }

    /// CTM-005-independent_content_tab_session: active tab 전환 시 nested folder stream 취소
    /// 탭별 loading owner 경계가 root load뿐 아니라 확장 폴더의 staged stream도 종료하는지 검증한다.
    /// - 검증 내용: previous A로 cancelAllFolderItems 전달과 A folder loading context 정리
    /// - 사전 조건: A에 nested folder loading context가 있고 B Directory tab이 존재함
    /// - 기대 결과: A의 context가 제거되고 B가 active로 복원됨
    func testTabSwitchCancelsPreviousTabFolderLoad() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/A/folder",
            folderGeneration: 1,
            path: "/tmp/A/folder",
            showHidden: false,
            priority: .none,
        )
        var contentA = makeCloseTestDirectoryContent(path: "/tmp/A")
        contentA.entryViewLayout.entryOperations.folderLoadingContexts[request.id] = .init(request: request)
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestDirectoryTab(id: tabA, path: "/tmp/A", title: "A"),
                makeCloseTestDirectoryTab(id: tabB, path: "/tmp/B", title: "B"),
            ],
            activeTabID: tabA,
            contentStates: [
                tabA: contentA,
                tabB: makeCloseTestDirectoryContent(path: "/tmp/B"),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: handoff 부수 action보다 previous tab cancellation routing을 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tabB)))
        await store.receive { action in
            guard case .tabContent(
                tabID: tabA,
                action: .entryViewLayout(.entryOperations(.loading(.cancelAllFolderItems))),
            ) = action else { return false }
            return true
        }
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(
            store.state.tabContentStates[tabA]?.entryViewLayout.entryOperations.folderLoadingContexts.isEmpty,
            true,
        )
    }

    /// CTM-005-independent_content_tab_session: active tab 전환 시 collection materialization 취소
    /// 이전 탭의 replace·append I/O owner를 종료하고 partial collection snapshot만 보존하는지 검증한다.
    /// - 검증 내용: previous A로 cancelCollectionMaterialization 전달과 transient loading state 정리
    /// - 사전 조건: A에 진행 중인 collection replace와 append가 있고 B tab이 존재함
    /// - 기대 결과: A의 collection mode/items는 유지되고 replace·append lifecycle만 초기화됨
    func testTabSwitchCancelsPreviousTabCollectionMaterialization() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let collectionItem = EntryModel.temporaryFolder(id: "/tmp/A/item.txt", name: "item.txt")
        var contentA = makeCloseTestDirectoryContent(path: "/tmp/A")
        contentA.entryViewLayout.isCollectionMode = true
        contentA.entryViewLayout.collectionItems = [collectionItem]
        contentA.entryViewLayout.isCollectionContentLoading = true
        contentA.entryViewLayout.activeCollectionReplacePaths = ["/tmp/A/pending.txt"]
        contentA.entryViewLayout.expectedCollectionReplaceBatchIndex = 1
        contentA.entryViewLayout.activeAppendExpectedBatchIndices = [7: 1]
        contentA.entryViewLayout.activeCollectionAppendPaths = [7: ["/tmp/A/appending.txt"]]
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestDirectoryTab(id: tabA, path: "/tmp/A", title: "A"),
                makeCloseTestDirectoryTab(id: tabB, path: "/tmp/B", title: "B"),
            ],
            activeTabID: tabA,
            contentStates: [
                tabA: contentA,
                tabB: makeCloseTestDirectoryContent(path: "/tmp/B"),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: handoff 부수 action보다 previous collection owner 정리에 집중한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(tabB)))
        await store.receive { action in
            guard case .tabContent(
                tabID: tabA,
                action: .entryViewLayout(.internal(.cancelCollectionMaterialization)),
            ) = action else { return false }
            return true
        }
        await store.skipReceivedActions()
        await store.finish()

        let previousLayout = store.state.tabContentStates[tabA]?.entryViewLayout
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(previousLayout?.isCollectionMode, true)
        XCTAssertEqual(Array(previousLayout?.collectionItems ?? []), [collectionItem])
        XCTAssertEqual(previousLayout?.isCollectionContentLoading, false)
        XCTAssertEqual(previousLayout?.activeCollectionReplacePaths, [])
        XCTAssertEqual(previousLayout?.activeAppendExpectedBatchIndices, [:])
        XCTAssertEqual(previousLayout?.activeCollectionAppendPaths, [:])
    }

    /// CTM-005-independent_content_tab_session: 현재 탭 재선택은 진행 중 load를 유지함
    /// 실제 tab 전환이 없는 setCurrent가 현재 folder·collection owner를 취소하지 않는지 검증한다.
    /// - 검증 내용: same-tab setCurrent 이후 folder context와 collection transient state 보존
    /// - 사전 조건: active A에 진행 중인 folder load와 collection replace·append가 있음
    /// - 기대 결과: 취소 action 없이 모든 in-flight state가 그대로 유지됨
    func testSameTabSelectionPreservesInFlightContentLoads() async {
        let tabA = ContentTabID(rawValue: "A")
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/A/folder",
            folderGeneration: 1,
            path: "/tmp/A/folder",
            showHidden: false,
            priority: .none,
        )
        var contentA = makeCloseTestDirectoryContent(path: "/tmp/A")
        contentA.entryViewLayout.entryOperations.folderLoadingContexts[request.id] = .init(request: request)
        contentA.entryViewLayout.isCollectionMode = true
        contentA.entryViewLayout.isCollectionContentLoading = true
        contentA.entryViewLayout.activeCollectionReplacePaths = ["/tmp/A/pending.txt"]
        contentA.entryViewLayout.activeAppendExpectedBatchIndices = [7: 1]
        contentA.entryViewLayout.activeCollectionAppendPaths = [7: ["/tmp/A/appending.txt"]]
        let state = makeCloseTestState(
            tabs: [makeCloseTestDirectoryTab(id: tabA, path: "/tmp/A", title: "A")],
            activeTabID: tabA,
            contentStates: [tabA: contentA],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.contentTabs(.setCurrent(tabA)))
        await store.finish()

        XCTAssertNotNil(store.state.content.entryViewLayout.entryOperations.folderLoadingContexts[request.id])
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionContentLoading)
        XCTAssertEqual(store.state.content.entryViewLayout.activeCollectionReplacePaths, ["/tmp/A/pending.txt"])
        XCTAssertEqual(store.state.content.entryViewLayout.activeAppendExpectedBatchIndices, [7: 1])
    }

    /// CTM-005-independent_content_tab_session: 존재하지 않는 tab 선택은 진행 중 load를 유지함
    /// 실제 전환이 불가능한 setCurrent가 현재 folder·collection owner를 취소하지 않는지 검증한다.
    /// - 검증 내용: invalid-tab setCurrent 이후 folder context와 collection transient state 보존
    /// - 사전 조건: active A에 진행 중인 folder load와 collection replace·append가 있고 target은 존재하지 않음
    /// - 기대 결과: 취소 action 없이 active A와 모든 in-flight state가 그대로 유지됨
    func testInvalidTabSelectionPreservesInFlightContentLoads() async {
        let tabA = ContentTabID(rawValue: "A")
        let invalidTabID = ContentTabID(rawValue: "missing")
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/A/folder",
            folderGeneration: 1,
            path: "/tmp/A/folder",
            showHidden: false,
            priority: .none,
        )
        var contentA = makeCloseTestDirectoryContent(path: "/tmp/A")
        contentA.entryViewLayout.entryOperations.folderLoadingContexts[request.id] = .init(request: request)
        contentA.entryViewLayout.isCollectionMode = true
        contentA.entryViewLayout.isCollectionContentLoading = true
        contentA.entryViewLayout.activeCollectionReplacePaths = ["/tmp/A/pending.txt"]
        contentA.entryViewLayout.activeAppendExpectedBatchIndices = [7: 1]
        contentA.entryViewLayout.activeCollectionAppendPaths = [7: ["/tmp/A/appending.txt"]]
        let state = makeCloseTestState(
            tabs: [makeCloseTestDirectoryTab(id: tabA, path: "/tmp/A", title: "A")],
            activeTabID: tabA,
            contentStates: [tabA: contentA],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.contentTabs(.setCurrent(invalidTabID)))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
        XCTAssertNotNil(store.state.content.entryViewLayout.entryOperations.folderLoadingContexts[request.id])
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionContentLoading)
        XCTAssertEqual(store.state.content.entryViewLayout.activeCollectionReplacePaths, ["/tmp/A/pending.txt"])
        XCTAssertEqual(store.state.content.entryViewLayout.activeAppendExpectedBatchIndices, [7: 1])
    }

    /// CTM-005-independent_content_tab_session: inactive tab close 시 nested folder stream 취소
    /// 제거되는 snapshot의 loading owner를 사용해 해당 탭의 확장 폴더 I/O까지 종료하는지 검증한다.
    /// - 검증 내용: inactive B의 folder stream cancellation 1회와 active A session 보존
    /// - 사전 조건: B의 nested folder stream이 대기 중이고 A Directory tab이 active임
    /// - 기대 결과: B folder stream과 state만 제거되고 A는 active로 유지됨
    func testInactiveCloseCancelsClosedTabFolderLoad() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let loadStarted = expectation(description: "folder load started")
        let loadCancelled = expectation(description: "folder load cancelled")
        let cancellationCount = LockIsolated(0)
        let loadGate = AsyncStream<Void>.makeStream()
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestDirectoryTab(id: tabA, path: "/tmp/A", title: "A"),
                makeCloseTestDirectoryTab(id: tabB, path: "/tmp/B", title: "B"),
            ],
            activeTabID: tabA,
            contentStates: [
                tabA: makeCloseTestDirectoryContent(path: "/tmp/A"),
                tabB: makeCloseTestDirectoryContent(path: "/tmp/B"),
            ],
        )
        let request = EntryFolderLoadRequest(
            rootContextGeneration: 1,
            folderID: "/tmp/B/folder",
            folderGeneration: 1,
            path: "/tmp/B/folder",
            showHidden: false,
            priority: .none,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.stagedLoadItems = nil
            $0.entryLoadingClient.loadItems = { _, _ in
                loadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in loadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    loadGate.continuation.finish()
                    loadCancelled.fulfill()
                }
            }
        }
        // store.exhaustivity = .off: inactive close 부수 action보다 closed tab folder stream cancellation을 검증한다.
        store.exhaustivity = .off

        await store.send(.tabContent(
            tabID: tabB,
            action: .entryViewLayout(.entryOperations(.loading(.loadFolderItems(request)))),
        ))
        await fulfillment(of: [loadStarted], timeout: 1)
        await store.send(.contentTabs(.close(tabB)))
        await fulfillment(of: [loadCancelled], timeout: 1)
        await store.finish()

        XCTAssertEqual(cancellationCount.value, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabA)
        XCTAssertNil(store.state.tabContentStates[tabB])
    }

    /// CTM-005-independent_content_tab_session: inactive tab close 시 active load 보존
    /// 닫힌 tab owner의 cancel effect가 같은 window의 active loading owner에 전파되지 않는지 검증한다.
    /// - 검증 내용: inactive close 후 active cancellation 0회와 active load 정상 완료
    /// - 사전 조건: active Directory load가 대기 중이고 별도 inactive tab이 존재함
    /// - 기대 결과: active load와 session이 유지되고 inactive state만 제거됨
    func testInactiveClosePreservesActiveTabLoad() async {
        let activeID = ContentTabID(rawValue: "active")
        let inactiveID = ContentTabID(rawValue: "inactive")
        let activePath = "/Users/test/Active"
        let loadStarted = expectation(description: "active tab load started")
        let loadGate = AsyncStream<Void>.makeStream()
        let cancellationCount = LockIsolated(0)
        let state = makeCloseTestState(
            tabs: [
                makeCloseTestDirectoryTab(id: activeID, path: activePath, title: "Active"),
                makeCloseTestDirectoryTab(
                    id: inactiveID, path: "/Users/test/Inactive", title: "Inactive",
                ),
            ],
            activeTabID: activeID,
            contentStates: [
                activeID: makeCloseTestDirectoryContent(path: activePath),
                inactiveID: makeCloseTestDirectoryContent(path: "/Users/test/Inactive"),
            ],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { _, _ in
                loadStarted.fulfill()
                return await withTaskCancellationHandler {
                    for await _ in loadGate.stream {}
                    return []
                } onCancel: {
                    cancellationCount.withValue { $0 += 1 }
                    loadGate.continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: inactive close 후 active loading effect 생존을 검증한다.
        store.exhaustivity = .off

        await store.sendTabContent(.entryViewLayout(.entryOperations(.loading(
            .loadItems(path: activePath, showHidden: false),
        ))))
        await fulfillment(of: [loadStarted], timeout: 1)
        await store.send(.contentTabs(.close(inactiveID)))
        XCTAssertEqual(cancellationCount.value, 0)

        loadGate.continuation.finish()
        await store.skipReceivedActions()
        await store.finish()
        XCTAssertEqual(cancellationCount.value, 0)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
    }

    /// CTM-005-independent_content_tab_session (VOY-578): active Directory close fallback은 snapshot 복원 후 reload함
    /// 활성 탭 닫기 handoff도 저장 presentation을 먼저 보이고 기존 Directory load 경로로 backing을 재검증한다.
    /// - 검증 내용: fallback entries/layout 즉시 복원, loadItems 정확히 1회, fresh entries commit, watcher 시작
    /// - 사전 조건: active/fallback Directory 탭과 fallback의 grid snapshot 및 보류 loader
    /// - 기대 결과: reload 대기 중 snapshot이 유지되고 완료 후 fresh entries가 표시됨
    func testActiveCloseRestoresFallbackTabSession() async {
        let fallbackID = ContentTabID()
        let activeID = ContentTabID()
        let fallbackPath = "/Users/test/Fallback"
        let activePath = "/Users/test/Active"
        let preservedEntry = EntryModel.temporaryFolder(id: "\(fallbackPath)/Preserved", name: "Preserved")
        let freshEntry = EntryModel.temporaryFolder(id: "\(fallbackPath)/Fresh", name: "Fresh")
        let gate = DirectoryLoadSuspensionGate()
        let loadPaths = LockIsolated<[String]>([])
        let watchedRoots = LockIsolated<[[String]]>([])
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        var fallbackContent = FileManagerContentFeature.State()
        fallbackContent.navigation.seedInitialFolderPath(fallbackPath)
        fallbackContent.entryViewLayout.mode = .grid
        fallbackContent.entryViewLayout.entries = [preservedEntry]
        fallbackContent.entryViewLayout.entryOperations.items = [preservedEntry]
        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.seedInitialFolderPath(activePath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: fallbackID,
                    page: .directory,
                    anchor: .directory(path: fallbackPath),
                    isPinned: false,
                    title: "Fallback",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: activeID,
                    page: .directory,
                    anchor: .directory(path: activePath),
                    isPinned: false,
                    title: "Active",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeID,
            previousActiveTabID: fallbackID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [fallbackID: fallbackContent, activeID: activeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return try await gate.wait()
            }
            $0.fileChangeGatewayClient.updateInterests = { interests in
                watchedRoots.withValue { $0.append(contentsOf: interests.map(\.roots)) }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in eventContinuation.setValue(continuation) }
            }
        }
        // store.exhaustivity = .off: close handoff 부수 action보다 VOY-578 fallback reload 계약에 집중함
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(activeID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(fallbackPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await gate.waitUntilWaiting()

        XCTAssertEqual(store.state.contentTabs.activeTabID, fallbackID)
        XCTAssertEqual(store.state.content.navigation.currentPath, fallbackPath)
        XCTAssertEqual(store.state.content.entryViewLayout.mode, .grid)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [preservedEntry])
        XCTAssertEqual(Array(store.state.content.entryViewLayout.entryOperations.items), [preservedEntry])
        XCTAssertNil(store.state.tabContentStates[activeID])

        await gate.resume(with: .entries([freshEntry]))
        await store.receiveTabContentCoreBatch()

        XCTAssertEqual(loadPaths.value, [fallbackPath])
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [freshEntry])
        XCTAssertEqual(watchedRoots.value, [[fallbackPath]])
        XCTAssertEqual(store.state.tabContentStates[fallbackID]?.entryViewLayout.mode, .grid)

        eventContinuation.value?.finish()
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: inactive tab close 시 active tab session에 영향 없음
    /// inactive tab을 닫을 때 active tab의 content session이 보존되는지 검증한다.
    /// - 검증 내용: activeTabID 불변, content 불변, tabContentStates에서 closed tab session만 제거됨
    /// - 사전 조건: 두 content tab이 있고 active tab이 A(home)
    /// - 기대 결과: activeTabID == A, content.currentPath == A session 경로, tabContentStates[B] == nil
    func testActiveCloseRestoresAiChatTabAndRemovesPromotedBackgroundOwner() async {
        let aiChatID = ContentTabID()
        let directoryID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID).recordingFinalSnapshot(finalSnapshot)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Desktop")

        var backgroundContent = aiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Desktop"),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: directoryID,
            previousActiveTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [aiChatID: aiChatContent, directoryID: directoryContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        XCTAssertNil(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            "restoring the AI Chat tab on close should remove the duplicated background owner",
        )
        XCTAssertNil(store.state.tabContentStates[directoryID])
        await store.finish()
    }

    func testInactiveCloseRemovesOnlyClosedTabSession() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let homePath = "/Users/test/HomeSession"
        let directoryPath = "/Users/test/Desktop"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // KCF: FileManagerFeature의 routing reducer가 non-exhaustive side effect를 수행함
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[directoryID])
        XCTAssertEqual(store.state.tabContentStates[homeID]?.navigation.currentPath, homePath)
        await store.finish()
    }

    private struct MixedBatchAiCloseStateContext {
        let pinnedID: ContentTabID
        let ordinaryID: ContentTabID
        let homeID: ContentTabID
        let aiChatID: ContentTabID
        let aiSessionID: AiChatSessionID
        let requestLock: AiChatRequestLock
    }

    private struct MixedBatchAiCloseFixture {
        let pinnedID: ContentTabID
        let ordinaryID: ContentTabID
        let homeID: ContentTabID
        let aiChatID: ContentTabID
        let aiSessionID: AiChatSessionID
        let requestLock: AiChatRequestLock
        let operationID: UUID
        let state: FileManagerFeature.State
    }

    private func makeMixedBatchContentTabItem(
        id: ContentTabID,
        page: ContentTabPage,
        anchor: ContentTabPageAnchor,
        isPinned: Bool,
        title: String,
    ) -> ContentTabItem {
        let iconName = switch page {
        case .home: "house"
        case .aiChat: "message"
        default: "folder"
        }
        return ContentTabItem(
            id: id,
            page: page,
            anchor: anchor,
            isPinned: isPinned,
            title: title,
            iconName: iconName,
        )
    }

    private func makeMixedBatchAiCloseState(
        context: MixedBatchAiCloseStateContext,
    ) -> FileManagerFeature.State {
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/HomeSession")
        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(context.aiSessionID.rawValue.uuidString)
        aiChatContent.aiChat.sessionID = context.aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(context.requestLock)

        let tabs = [
            makeMixedBatchContentTabItem(
                id: context.pinnedID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Pinned"),
                isPinned: true,
                title: "Pinned",
            ),
            makeMixedBatchContentTabItem(
                id: context.ordinaryID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Ordinary"),
                isPinned: false,
                title: "Ordinary",
            ),
            makeMixedBatchContentTabItem(
                id: context.homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
            ),
            makeMixedBatchContentTabItem(
                id: context.aiChatID,
                page: .aiChat,
                anchor: .aiChat(sessionID: context.aiSessionID.rawValue.uuidString),
                isPinned: false,
                title: "Chat",
            ),
        ]
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: .init(uniqueElements: tabs), activeTabID: context.homeID)
        state.content = homeContent
        state.tabContentStates = [context.homeID: homeContent, context.aiChatID: aiChatContent]
        state.contentTabs.selectedTabIDs = [context.pinnedID, context.ordinaryID, context.aiChatID]
        state.contentTabs.selectionAnchorID = context.aiChatID
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeMixedBatchAiCloseFixture() throws -> MixedBatchAiCloseFixture {
        let pinnedID = ContentTabID(rawValue: "mixed-pinned")
        let ordinaryID = ContentTabID(rawValue: "mixed-ordinary")
        let homeID = ContentTabID(rawValue: "mixed-home")
        let aiChatID = ContentTabID(rawValue: "mixed-ai")
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let providerMessage = AiChatMessage(role: .user, content: "latest provider prompt")
        let preservedMessage = AiChatMessage(role: .user, content: "older preserved prompt")
        let requestLock = makeRequestLock(
            sessionID: aiSessionID,
            requestMessages: [providerMessage],
            persistenceTranscriptHistory: [preservedMessage, providerMessage],
        )
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))

        let stateContext = MixedBatchAiCloseStateContext(
            pinnedID: pinnedID,
            ordinaryID: ordinaryID,
            homeID: homeID,
            aiChatID: aiChatID,
            aiSessionID: aiSessionID,
            requestLock: requestLock,
        )
        let state = makeMixedBatchAiCloseState(context: stateContext)
        return MixedBatchAiCloseFixture(
            pinnedID: pinnedID,
            ordinaryID: ordinaryID,
            homeID: homeID,
            aiChatID: aiChatID,
            aiSessionID: aiSessionID,
            requestLock: requestLock,
            operationID: operationID,
            state: state,
        )
    }

    private func makeMixedBatchAiCloseStore(
        fixture: MixedBatchAiCloseFixture,
        cancelActionCount: LockIsolated<Int>,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        var state = fixture.state
        state.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: fixture.operationID,
            orderedTargetIDs: [fixture.pinnedID, fixture.ordinaryID, fixture.aiChatID],
            cursor: 2,
            currentTabID: fixture.aiChatID,
            originalActiveTabID: fixture.homeID,
            preferredFallbackIDs: [fixture.homeID],
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: fixture.aiChatID,
            batchOperationID: fixture.operationID,
        )
        return TestStore(initialState: state) {
            CombineReducers {
                FileManagerFeature()
                Reduce { _, action in
                    switch action {
                    case .content(.aiChat(.cancelTapped)),
                         .inspector(.aiChat(.cancelTapped)),
                         .backgroundAiChat(.cancelTapped),
                         .backgroundInspectorAiChat(.cancelTapped):
                        cancelActionCount.withValue { $0 += 1 }
                    default:
                        break
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.uuid = .constant(fixture.operationID)
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in }
        }
    }

    /// CTM-005-independent_content_tab_session: mixed batch는 AI processing owner를 background로 넘기고 취소하지 않음
    /// interaction settlement는 CTM001 owner에 맡기고 CTM005는 AI lifecycle 소유권만 검증한다.
    /// - 검증 내용: AI processing owner background 이동과 모든 cancelTapped action 0회
    /// - 사전 조건: pinned, ordinary, processing AI tab이 선택되고 Home은 active non-target임
    /// - 기대 결과: AI processing은 background owner에서 유지되고 generation cancel action은 발생하지 않음
    func testInactiveAiChatTabCloseMovesLifecycleOwnerToBackground() async throws {
        let fixture = try makeMixedBatchAiCloseFixture()
        let cancelActionCount = LockIsolated(0)
        let store = makeMixedBatchAiCloseStore(
            fixture: fixture,
            cancelActionCount: cancelActionCount,
        )
        // store.exhaustivity = .off: 모든 Task 3 lifecycle terminal은 receive하고
        // AI 내부 background projection diff만 최종 state로 검증한다.
        store.exhaustivity = .off

        await store.send(.performSelectedContentTabCloseMutation(
            operationID: fixture.operationID,
            tabID: fixture.aiChatID,
            action: .commitClose(fixture.aiChatID),
        ))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[fixture.aiSessionID]?.aiChat.executionPhase,
            .processing(fixture.requestLock),
        )
        XCTAssertEqual(cancelActionCount.value, 0)
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: 마지막 content tab close 시 fresh Home으로 window를 유지함
    /// 단일 active tab을 닫으면 새 Home tab session으로 교체하고 window close 요청을 발생시키지 않는다.
    /// - 검증 내용: 새 Home ID/anchor와 `.closeWindow` action 미방출
    /// - 사전 조건: 단일 Directory tab이 active 상태
    /// - 기대 결과: 새 Home tab이 active이고 window session이 계속 유지됨
    func testLastTabCloseKeepsWindowOpenWithFreshHome() async throws {
        let directoryID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: directoryID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Desktop"),
                isPinned: false,
                title: "Desktop",
                iconName: "folder",
            )],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()
        let closeWindowActionCount = LockIsolated(0)

        let store = TestStore(initialState: state) {
            CombineReducers {
                Reduce<FileManagerWindowState, FileManagerWindowAction> { _, action in
                    if case .delegate(.closeWindow) = action {
                        closeWindowActionCount.withValue { $0 += 1 }
                    }
                    return .none
                }
                FileManagerFeature()
            }
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: tab handoff 내부 action보다 continuing window session 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryID)))
        await store.finish()

        let homeID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(homeID, directoryID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: homeID]?.anchor, .homeDefault)
        XCTAssertEqual(closeWindowActionCount.value, 0)
    }

    /// CTM-005-independent_content_tab_session: batch의 마지막 actual tab은 기존 window-close handoff를 정확히 한 번 사용함
    /// 실제 survivor가 없는 fallback 경계에서 별도 fallback tab을 만들지 않고 Phase 1 last-tab 정책을 재사용하는지 검증한다.
    /// - 검증 내용: 두 ordinary item의 request/commit/removed와 closeWindow delegate 1회
    /// - 사전 조건: A/C 두 tab 모두 선택되고 C가 active-last target임
    /// - 기대 결과: C는 Home reset 상태로 남고 selection/coordinator는 clear되며 closeWindow가 정확히 한 번 발생한다.
    func testSelectedBatchLastActualTabRequestsWindowCloseExactlyOnce() async throws {
        let firstID = ContentTabID(rawValue: "batch-last-first")
        let activeID = ContentTabID(rawValue: "batch-last-active")
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453"))
        let closeWindowCount = LockIsolated(0)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: firstID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/First"),
                    isPinned: false,
                    title: "First",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: activeID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Active"),
                    isPinned: false,
                    title: "Active",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeID,
        )
        state.contentTabs.selectedTabIDs = [firstID, activeID]
        state.contentTabs.selectionAnchorID = activeID
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            CombineReducers {
                FileManagerFeature()
                Reduce { _, action in
                    if case .delegate(.closeWindow) = action {
                        closeWindowCount.withValue { $0 += 1 }
                    }
                    return .none
                }
            }
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Date(timeIntervalSince1970: 453))
        }
        // store.exhaustivity = .off: 두 item lifecycle과 closeWindow는 모두 receive하고
        // Home handoff projection은 최종 state로 검증한다.
        store.exhaustivity = .off

        await store.send(.requestCloseSelectedContentTabs)
        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .requestClose(requestedID)) = action
            else { return false }
            return tabID == firstID && requestedID == firstID
        }
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .commitClose(committedID)) = action
            else { return false }
            return tabID == firstID && committedID == firstID
        }
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == firstID && outcome == .removed
        }

        await store.receive(\.processNextSelectedContentTabClose, operationID)
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .requestClose(requestedID)) = action
            else { return false }
            return tabID == activeID && requestedID == activeID
        }
        await store.receive { action in
            guard case let .performSelectedContentTabCloseMutation(_, tabID, .commitClose(committedID)) = action
            else { return false }
            return tabID == activeID && committedID == activeID
        }
        await store.receive(\.delegate.closeWindow)
        await store.receive { action in
            guard case let .selectedContentTabCloseItemCompleted(_, tabID, outcome) = action else { return false }
            return tabID == activeID && outcome == .removed
        }
        await store.receive(\.processNextSelectedContentTabClose, operationID)

        XCTAssertNil(store.state.pendingSelectedContentTabClose)
        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeID]?.anchor, .homeDefault)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [])
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, activeID)
        XCTAssertEqual(closeWindowCount.value, 1)
        await store.finish()
        XCTAssertEqual(closeWindowCount.value, 1)
    }

    func testRestoringCollectionTabReappliesClosedNavigationRoute() async {
        let homeID = ContentTabID()
        let collectionID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/restored.voycoll")
        let collectionContext = CollectionContext(query: "kind:document", scopes: [], conditions: [])
        let collectionRoute = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "restored"),
            context: collectionContext,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var collectionContent = FileManagerContentFeature.State()
        collectionContent.navigation.navigationState = collectionRoute
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: collectionID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: false,
                    title: "restored",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: collectionID,
            recentlyClosed: nil,
        )
        state.content = collectionContent
        state.tabContentStates = [
            homeID: homeContent,
            collectionID: collectionContent,
        ]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(collectionID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.content.navigation.navigationState, .home)

        await store.send(.contentTabs(.restore))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.receive(\.navigation.internal.navigateToCollection)
        await store.receiveTabContent(\.collection.navigationStateApplied)

        guard let restoredID = store.state.contentTabs.activeTabID else {
            XCTFail("restore should activate the restored collection tab")
            return
        }
        XCTAssertNotEqual(restoredID, homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: restoredID]?.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(store.state.content.navigation.navigationState, collectionRoute)
        XCTAssertEqual(store.state.content.collection.collectionSession.document?.url, collectionURL)
        XCTAssertEqual(store.state.content.collection.collectionContext, collectionContext)
        XCTAssertEqual(store.state.tabContentStates[restoredID]?.navigation.navigationState, collectionRoute)
        XCTAssertNil(store.state.recentlyClosedNavigationRoute)
        await store.finish()
    }

    func testHomeRouteNewFolderCommandDoesNotRunPathDependentOperation() async {
        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .home
        state.contentTabs.tabs[id: state.contentTabs.activeTabID ?? ContentTabID()]?.anchor = .homeDefault
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.request(.newFolder))

        XCTAssertEqual(store.state.content.navigation.navigationState, .home)
        if case .folder = store.state.content.navigation.navigationState {
            XCTFail("Home route should not expose a filesystem directory for path-dependent commands")
        }
        await store.finish()
    }

    func testInternalApplyCollectionNavigationSyncsActiveContentTabAnchor() async {
        let tabID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/spec.voycoll")
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "spec"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                isPinned: false,
                title: "Documents",
                iconName: "folder",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.setNavigationState(navigationState)))) {
            $0.content.navigation.navigationState = navigationState
        }
        await store.sendTabContent(.internal(.applyNavigationState(navigationState)))
        await store.receive(\.contentTabs) {
            $0.contentTabs.tabs[id: tabID]?.anchor = .collectionFile(url: collectionURL)
            $0.contentTabs.tabs[id: tabID]?.page = .collection
            $0.contentTabs.tabs[id: tabID]?.title = "spec"
            $0.contentTabs.tabs[id: tabID]?.iconName = "rectangle.stack"
            $0.sidebar.contentTabSidebarItems = ContentTabProjection.sidebarItems(from: $0.contentTabs)
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, navigationState)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .collectionFile(url: collectionURL))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.page, .collection)
        await store.finish()
    }

    // MARK: - CTM-444-collection_dirty_close

    /// CTM-444-collection_dirty_close: dirty active collection close가 unsaved alert를 표시하고 pendingContentTabClose를 설정
    /// isCollectionMode와 canSaveCollection이 true인 active collection tab에서 close 요청 시 alert가 발생하고 pending 상태가 설정되는지
    /// 검증한다.
    /// - 검증 내용: pendingContentTabClose 설정, contentTabCloseAlertResponse 수신
    /// - 사전 조건: active tab이 dirty collection mode
    /// - 기대 결과: pendingContentTabClose가 tabID로 설정되고, cancel 응답 후 pending 해제
    func testDirtyActiveCollectionCloseShowsAlert() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(tabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.receive(\.contentTabCloseAlertResponse)
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: Collection open loading 중 dirty tab close도 unsaved alert를 표시함
    /// Save UI 비활성화와 tab close의 미저장 보호가 독립적으로 유지되는지 검증한다.
    /// - 검증 내용: loading 중 close 요청의 pendingContentTabClose 설정과 cancel 처리
    /// - 사전 조건: active tab이 dirty Collection이며 다른 Collection open loading이 진행 중
    /// - 기대 결과: tab과 draft를 유지하고 pending close를 alert cancel 후 해제
    func testDirtyActiveCollectionCloseWhileLoadingShowsAlert() async {
        let tabID = ContentTabID()
        var content = makeDirtyCollectionContent()
        content.entryViewLayout.isCollectionContentLoading = true

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/loading.voycoll")),
                    isPinned: false,
                    title: "Loading Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingCollectionOpenRequest = ContentPageCollectionOpenRequest(
            id: UUID(608),
            url: URL(fileURLWithPath: "/tmp/target.voycoll"),
            sourceRoute: content.navigation.navigationState,
            prePrepareBackHistory: content.navigation.backHistory,
            prePrepareForwardHistory: content.navigation.forwardHistory,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)
        XCTAssertFalse(store.state.content.canSaveCollection)

        await store.send(.closeContentTabRequested(tabID))
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        XCTAssertNil(store.state.pendingCollectionOpenRequest)
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .entryViewLayout(.internal(.setCollectionContentLoading(isLoading))),
            ) = action else { return false }
            return receivedTabID == tabID && !isLoading
        }
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionContentLoading)
        await store.receive(\.contentTabCloseAlertResponse)
        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: save 성공 후 dirty collection tab이 정상 닫힘
    /// pending 상태에서 saveCompleted(.success) 수신 시 pending 해제와 함께 tab이 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 해제, tab tabContentStates에서 제거
    /// - 사전 조건: pendingContentTabClose가 설정된 dirty collection tab (2 tabs, non-last)
    /// - 기대 결과: pending이 nil, tab 제거, active tab이 otherID로 전환
    func testDirtyActiveCollectionSaveSuccessClosesTab() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        let completion = CollectionSaveCompletion(
            url: URL(fileURLWithPath: "/tmp/test.voycoll"),
            file: VoyagerCollectionFile(
                id: "test-id",
                name: "test",
                createdAt: Date(timeIntervalSince1970: 1_234_567_890),
                updatedAt: Date(timeIntervalSince1970: 1_234_567_890),
                query: "",
                scopes: [],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
            savedContext: nil,
        )

        await store.sendTabContent(.collection(.saveCompleted(.success(completion))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: save 실패 시 tab이 유지됨
    /// pending 상태에서 save failure feedback과 write-back failure를 모두 수신한 뒤 pending이 해제되고 tab은 유지되는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 해제, tab 유지
    /// - 사전 조건: pendingContentTabClose가 설정된 dirty collection tab
    /// - 기대 결과: pending이 nil이지만 tab은 contentTabs에 그대로 존재
    func testDirtyActiveCollectionSaveFailurePreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        let error = NSError(domain: "test", code: 0, userInfo: nil)
        await store.sendTabContent(.collection(.saveCompleted(.failure(error))))

        XCTAssertNotNil(store.state.pendingContentTabClose)

        let feedback = CollectionSaveFeedback(
            stage: .saveFailed,
            category: .saveFailed,
            title: "Save Failed",
            message: "Unable to save collection.",
            isRetryable: true,
        )
        await store.sendTabContent(.collection(.delegate(.saveFeedback(feedback))))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        await store.sendTabContent(.collection(.writeBackFailed))
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .composer(.internal(.presentTransientFeedback(receivedFeedback))),
            ) = action else { return false }
            return receivedTabID == tabID && receivedFeedback.category == .saveFailed
        }

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.content.composer.transientFeedback?.category, .saveFailed)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: discard 선택 시 dirty collection tab이 닫힘
    /// alert에서 discard 선택 시 tab이 정상 닫히는지 검증한다.
    /// - 검증 내용: contentTabCloseAlertResponse(.discard) 수신 후 tab 제거
    /// - 사전 조건: active tab이 dirty collection mode (2 tabs, non-last)
    /// - 기대 결과: tab이 tabContentStates에서 제거됨
    func testDirtyActiveCollectionDiscardClosesTab() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .discard)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: cancel 선택 시 tab이 유지됨
    /// alert에서 cancel 선택 시 tab이 닫히지 않고 그대로 유지되는지 검증한다.
    /// - 검증 내용: contentTabCloseAlertResponse(.cancel) 수신 후 tab 유지
    /// - 사전 조건: active tab이 dirty collection mode
    /// - 기대 결과: tab이 contentTabs에 그대로 존재, recentlyClosed nil
    func testDirtyActiveCollectionCancelPreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: clean collection tab은 alert 없이 바로 닫힘
    /// isCollectionMode는 true지만 canSaveCollection이 false인 tab에서 close 요청 시 alert를 건너뛰고 바로 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 설정되지 않고 tab이 바로 닫힘
    /// - 사전 조건: collection mode이지만 clean 상태 (canSaveCollection == false), 2 tabs
    /// - 기대 결과: pending 미설정, tab 제거
    func testCleanCollectionBypassesAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()

        // collection mode지만 collectionContext == nil → canSaveCollection == false
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(tabID))

        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: non-collection tab은 alert 없이 바로 닫힘
    /// isCollectionMode가 false인 일반 tab에서 close 요청 시 alert 없이 바로 닫히는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 설정되지 않고 tab이 바로 닫힘
    /// - 사전 조건: non-collection tab, 2 tabs
    /// - 기대 결과: pending 미설정, tab 제거
    func testNonCollectionBypassesAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Other"),
                    isPinned: false,
                    title: "Other",
                    iconName: "folder",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(tabID))

        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[tabID])
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection tab close도 alert를 표시
    /// active tab이 아닌 inactive tab이 dirty collection 상태일 때도 close 요청이 alert를 발생시키는지 검증한다.
    /// - 검증 내용: pendingContentTabClose가 inactive tabID로 설정, active tab은 영향 없음
    /// - 사전 조건: active tab(home) + inactive tab(dirty collection)
    /// - 기대 결과: pending이 inactive tabID로 설정, active tab session 보존
    func testInactiveDirtyCollectionCloseShowsAlert() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .cancel)

        await store.send(.closeContentTabRequested(inactiveID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, inactiveID)

        // active tab은 영향 없음
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.tabContentStates[activeID]?.navigation.currentPath, homePath)
        await store.receive(\.contentTabCloseAlertResponse)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save 성공은 대상 탭을 저장한 뒤 닫음
    /// inactive tab의 dirty state를 기준으로 alert를 띄운 뒤 Save continuation이 active content가 아니라 target tab content를 대상으로
    /// 수행되는지 검증한다.
    func testInactiveDirtyCollectionSaveSuccessClosesTargetTab() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: inactiveID,
            recentlyClosed: nil,
        )
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        let completion = makeSaveCompletion()
        await store.sendTabContent(.collection(.saveCompleted(.success(completion))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive target 저장 중 tab switch는 target ownership을 오염시키지 않음
    func testInactiveDirtyCollectionSaveInProgressIgnoresTabSwitchUntilCompletion() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: inactiveID,
            recentlyClosed: nil,
        )
        state.contentTabs.previousActiveTabID = activeID
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        XCTAssertEqual(store.state.contentTabs.activeTabID, inactiveID)
        XCTAssertTrue(store.state.content.isCollectionMode)

        await store.send(.contentTabs(.setCurrent(activeID)))

        XCTAssertEqual(store.state.contentTabs.activeTabID, inactiveID)
        XCTAssertTrue(store.state.content.isCollectionMode)
        XCTAssertEqual(store.state.tabContentStates[activeID]?.navigation.currentPath, homePath)

        let completion = makeSaveCompletion()
        await store.sendTabContent(.collection(.saveCompleted(.success(completion))))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: active dirty collection Save가 시작 불가하면 pending을 해제하고 tab을 보존
    func testDirtyActiveCollectionSaveBlockedPreservesTabAndClearsPending() async {
        let tabID = ContentTabID()
        var content = makeDirtyCollectionContent()
        content.collection.isSaving = true

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(tabID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertTrue(store.state.content.collection.isSaving)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save가 시작 불가하면 active content를 복구하고 대상 tab을 보존
    func testInactiveDirtyCollectionSaveBlockedPreservesTargetTabAndRestoresActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        var dirtyContent = makeDirtyCollectionContent()
        dirtyContent.composer.isLoadingSearch = true

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertNotNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: active dirty collection Save panel 취소는 pending을 해제하고 tab을 보존
    func testDirtyActiveCollectionSavePanelCancelClearsPendingAndPreservesTab() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.sendTabContent(.collection(.savePanelResponse(nil)))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Save panel 취소는 active content를 복구하고 대상 탭을 보존
    func testInactiveDirtyCollectionSavePanelCancelRestoresActiveContentAndPreservesTargetTab() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: inactiveID,
            recentlyClosed: nil,
        )
        state.content = dirtyContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: inactiveID,
            previousActiveTabID: activeID,
            previousActiveContent: homeContent,
            targetContent: dirtyContent,
        )
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.sendTabContent(.collection(.savePanelResponse(nil)))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertNotNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    func testInactiveDirtyCollectionSaveFailurePreservesTargetTabAndRestoresActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)
        await store.sendTabContent(.collection(.saveCompleted(.failure(NSError(domain: "test", code: 0)))))

        XCTAssertNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: inactiveID])
        guard let inactiveContent = store.state.tabContentStates[inactiveID] else {
            XCTFail("inactive tab content should remain after save failure")
            return
        }
        XCTAssertEqual(inactiveContent.composer.transientFeedback?.stage, .save)
        XCTAssertNotNil(inactiveContent.composer.transientFeedback?.category)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: inactive dirty collection Discard는 active content를 건드리지 않고 대상 탭만 닫음
    func testInactiveDirtyCollectionDiscardClosesTargetTabWithoutMutatingActiveContent() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()
        let homePath = "/Users/test/Home"
        let dirtyContent = makeDirtyCollectionContent()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent, inactiveID: dirtyContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state, alertChoice: .discard)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabCloseAlertResponse)

        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, homePath)
        await store.receive(\.contentTabs)
        XCTAssertNil(store.state.tabContentStates[inactiveID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 복원된 비활성 tab에 content snapshot이 없어도 clean close는 진행
    func testRestoredInactiveTabWithoutContentStateCanClose() async {
        let activeID = ContentTabID()
        let inactiveID = ContentTabID()

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Restored"),
                    isPinned: false,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [activeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.closeContentTabRequested(inactiveID))
        await store.receive(\.contentTabs)

        XCTAssertNil(store.state.contentTabs.tabs[id: inactiveID])
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        XCTAssertEqual(store.state.content.navigation.currentPath, "/Users/test/Home")
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 중복 close 요청은 무시됨
    /// pendingContentTabClose가 설정된 상태에서 closeContentTabRequested가 duplicate guard에 의해 무시되는지 검증한다.
    /// - 검증 내용: pending 상태에서 요청은 no-op, pending 유지
    /// - 사전 조건: dirty collection tab, pendingContentTabClose 직접 설정 (alert effect 없음)
    /// - 기대 결과: 요청 후에도 pending 유지, tab 그대로 존재
    func testDuplicateCloseWhilePendingIsNoOp() async {
        let tabID = ContentTabID()
        let otherTabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherTabID: otherContent]
        // pending을 직접 설정 → alert 없이 duplicate guard만 검증
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        // 같은 tabID로 중복 요청 → guard가 .none 반환 (pending 유지)
        await store.send(.closeContentTabRequested(tabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)

        // 다른 tabID로 요청해도 guard가 막음
        await store.send(.closeContentTabRequested(otherTabID))
        XCTAssertNotNil(store.state.pendingContentTabClose)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)

        // tab은 그대로 유지
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: pending A는 unrelated B writeback completion을 무시함
    /// staged close completion은 pending target tab identity와 일치할 때만 close readiness를 변경한다.
    /// - 검증 내용: pending A 상태에서 B composer sync action 후 writeback flag를 확인한다.
    /// - 사전 조건: A가 pending close target이고 B가 active이다.
    /// - 기대 결과: A의 composer sync flag는 false로 유지되고 close finalize effect가 없다.
    func testPendingCloseIgnoresUnrelatedTabWriteBackCompletion() async {
        let pendingTabID = ContentTabID()
        let activeTabID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pendingTabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/pending.voycoll")),
                    isPinned: false,
                    title: "Pending",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: activeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.pendingContentTabClose = PendingContentTabClose(
            tabID: pendingTabID,
            didReceiveWriteBackNavigationState: true,
        )
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.tabContent(
            tabID: activeTabID,
            action: .composer(.internal(.syncCollectionState(
                context: nil,
                url: nil,
                compatibility: nil,
                isCollectionMode: false,
            ))),
        ))

        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, pendingTabID)
        XCTAssertEqual(store.state.pendingContentTabClose?.didReceiveWriteBackComposerSync, false)
        XCTAssertEqual(store.state.contentTabs.activeTabID, activeTabID)
    }

    /// CTM-444-collection_dirty_close: pending close 중 직접 navigation 요청은 무시됨
    /// 저장 완료 전 외부 coordinator/toolbar가 navigation view action을 보내도 target content를 변경하지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresDirectNavigationUntilCompletion() async {
        let tabID = ContentTabID()
        let closingPath = "/Users/test/Closing"
        var content = makeDirtyCollectionContent()
        content.navigation.seedInitialFolderPath(closingPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.navigation(.view(.navigateToPath("/Users/test/Other"))))

        XCTAssertEqual(store.state.content.navigation.currentPath, closingPath)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 toolbar history command는 무시됨
    /// Back/Forward 계열 command가 저장 중인 closing target에 pending navigation을 만들지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresToolbarNavigationCommandUntilCompletion() async {
        let tabID = ContentTabID()
        let closingPath = "/Users/test/Closing"
        var content = makeDirtyCollectionContent()
        content.navigation.seedInitialFolderPath(closingPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }

        await store.send(.request(.goBack))

        XCTAssertEqual(store.state.content.navigation.currentPath, closingPath)
        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 Cmd+P pin toggle은 무시됨
    /// 저장 완료 전 active closing target이 pinned로 바뀌어 close-as-unpin 정책과 충돌하지 않도록 검증한다.
    func testPendingDirtyCollectionCloseIgnoresPinToggleCommandUntilCompletion() async {
        let tabID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                isPinned: false,
                title: "Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: tabID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, tabID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: pending close 중 Sidebar pin/unpin delegate는 무시됨
    /// Sidebar context menu 경로도 저장 중 closing target의 pin 상태를 변경하지 않는지 검증한다.
    func testPendingDirtyCollectionCloseIgnoresSidebarPinActionsUntilCompletion() async {
        let pinnedID = ContentTabID()
        let unpinnedID = ContentTabID()
        let pinnedAnchor: ContentTabPageAnchor = .collectionFile(url: URL(fileURLWithPath: "/tmp/pinned.voycoll"))
        let unpinnedAnchor: ContentTabPageAnchor = .collectionFile(url: URL(fileURLWithPath: "/tmp/unpinned.voycoll"))
        let pinnedRecord = ContentTabPinnedRecord(
            id: pinnedID.rawValue,
            page: .collection,
            anchor: pinnedAnchor,
            title: "Pinned",
            iconName: "rectangle.stack",
            pinnedAt: Date(timeIntervalSince1970: 1_234_567_890),
        )
        let content = makeDirtyCollectionContent()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .collection,
                    anchor: pinnedAnchor,
                    isPinned: true,
                    title: "Pinned",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: unpinnedID,
                    page: .collection,
                    anchor: unpinnedAnchor,
                    isPinned: false,
                    title: "Unpinned",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: pinnedID,
            recentlyClosed: nil,
            pinnedRecords: [pinnedID: pinnedRecord],
        )
        state.content = content
        state.tabContentStates = [pinnedID: content]
        state.pendingContentTabClose = PendingContentTabClose(tabID: pinnedID)
        state.syncContentTabSidebarItems()

        let store = makeTestStore(state: state)

        await store.send(.sidebar(.delegate(.unpinContentTab(pinnedID))))
        await store.send(.sidebar(.delegate(.pinContentTab(unpinnedID))))

        XCTAssertEqual(store.state.pendingContentTabClose?.tabID, pinnedID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: pinnedID]?.isPinned, true)
        XCTAssertEqual(store.state.contentTabs.tabs[id: unpinnedID]?.isPinned, false)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[pinnedID], pinnedRecord)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[unpinnedID])
        await store.finish()
    }

    /// CTM-444-collection_dirty_close: 단일 dirty collection tab close 시 Cancel/Discard 전환
    /// 마지막 tab이 dirty collection인 경우 Cancel/Discard 각각의 결과를 검증한다.
    /// Cancel: collection 유지. Discard: close.
    /// - 검증 내용: Cancel → tab 유지, Discard → close
    /// - 사전 조건: 단일 dirty collection tab
    /// - 기대 결과: Cancel은 tab 유지, Discard는 tab 제거 or home reset
    func testLastDirtyCollectionTabPromptBeforeReset() async {
        // Cancel flow: alert cancel → tab preserved
        do {
            let tabID = ContentTabID()
            let content = makeDirtyCollectionContent()

            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                )],
                activeTabID: tabID,
                recentlyClosed: nil,
            )
            state.content = content
            state.tabContentStates = [tabID: content]
            state.syncContentTabSidebarItems()

            let store = makeTestStore(state: state, alertChoice: .cancel)

            await store.send(.closeContentTabRequested(tabID))
            await store.receive(\.contentTabCloseAlertResponse)

            XCTAssertNil(store.state.pendingContentTabClose)
            XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
            await store.finish()
        }

        // Discard flow: alert discard → tab closed (last tab)
        do {
            let tabID = ContentTabID()
            let content = makeDirtyCollectionContent()

            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                )],
                activeTabID: tabID,
                recentlyClosed: nil,
            )
            state.content = content
            state.tabContentStates = [tabID: content]
            state.syncContentTabSidebarItems()

            let store = makeTestStore(state: state, alertChoice: .discard)

            await store.send(.closeContentTabRequested(tabID))
            await store.receive(\.contentTabCloseAlertResponse)

            XCTAssertNil(store.state.pendingContentTabClose)
            await store.finish()
        }
    }

    /// CTM-444-collection_dirty_close: pinned dirty collection tab은 alert 없이 바로 close
    /// isPinned == true인 dirty collection tab은 dirty check를 건너뛰고 바로 close action을 보내는지 검증한다.
    /// - 검증 내용: pendingContentTabClose 미설정, alert 미발생
    /// - 사전 조건: pinned + dirty collection tab (2 tabs, non-last)
    /// - 기대 결과: pending이 nil, tab 제거
    func testPinnedDirtyCollectionTabUnpinsWithoutAlert() async {
        let tabID = ContentTabID()
        let otherID = ContentTabID()
        let content = makeDirtyCollectionContent()

        var otherContent = FileManagerContentFeature.State()
        otherContent.navigation.seedInitialFolderPath("/Users/test/Other")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: .collectionFile(url: URL(fileURLWithPath: "/tmp/test.voycoll")),
                    isPinned: true,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
                ContentTabItem(
                    id: otherID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [tabID: content, otherID: otherContent]
        state.syncContentTabSidebarItems()

        // alertChoice는 중요하지 않음 → pinned bypass이므로 alert client가 호출되지 않음
        let store = makeTestStore(state: state, alertChoice: .save)

        await store.send(.closeContentTabRequested(tabID))

        // pinned tab의 close는 unpin 처리 → tab은 유지되지만 isPinned = false
        XCTAssertNil(store.state.pendingContentTabClose)
        await store.receive(\.contentTabs)
        // tab은 유지 (unpin만 됨)
        XCTAssertNotNil(store.state.contentTabs.tabs[id: tabID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_provider_forwarding

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// CTM-005-ai_chat_provider_forwarding: Active AI Chat tab이 providerConnectionsUpdated를 ContentPane으로 수신함
    /// .aiChat(sessionID:) anchor를 가진 active tab에서 aiConnectionsFileUpdated action이
    /// content.aiChat.providerConnectionsUpdated로 전달되는지 검증한다.
    /// Inspector가 보이지 않을 때는 Inspector로 전달되지 않는다.
    func testActiveAIChatTabReceivesProviderConnectionsUpdated() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let connectionsFile = AIConnectionsFile.empty()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(connectionsFile))

        // ContentPane AI Chat으로 providerConnectionsUpdated가 전달됨
        await store.receive { action in
            guard case .tabContent(_, .aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        // Inspector는 보이지 않으므로 Inspector로 전달되지 않음
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat tab switch away/back 시 session이 보존됨
    /// .aiChat tab에서 Home tab으로 전환 후 다시 AI Chat tab으로 돌아왔을 때
    /// tab anchor와 content session이 유지되는지 검증한다.
    /// resyncNavigationStateForActiveContentTab가 .aiChat을 .home으로 매핑하지 않음을 간접 검증한다.
    func testAIChatTabSwitchAwayAndBackPreservesSession() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        let aiChatContent = FileManagerContentFeature.State()
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [aiChatID: aiChatContent, homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        // AI Chat → Home으로 전환
        await store.send(.contentTabs(.setCurrent(homeID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)

        // AI Chat tab metadata가 tabContentStates에 보존됨
        XCTAssertNotNil(store.state.tabContentStates[aiChatID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)

        // Home → AI Chat으로 재전환
        await store.send(.contentTabs(.setCurrent(aiChatID)))

        // AI Chat tab이 active로 복원되고 anchor가 유지됨 (resync가 .home을 overwrite하지 않음)
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)
        XCTAssertNotNil(store.state.tabContentStates[aiChatID])
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat History 탭 복귀 시 sessions route를 보존함
    /// AI Chat tab anchor는 `.aiChat(sessionID:)`만 저장하므로 탭 handoff resync가 복원된 History route를 chat route로 낮추면 안 된다.
    /// - 검증 내용: Home tab에서 AI Chat History tab으로 복귀할 때 `.aiChatSessions(sessionID)` route와 sessions mode가 유지됨
    /// - 사전 조건: AI Chat tab의 저장된 content state가 `.aiChatSessions(sessionID)`이고 현재 active tab은 Home인 상태
    /// - 기대 결과: resync가 `.aiChat(sessionID)`가 아니라 `.aiChatSessions(sessionID)`를 apply하고 AiChat state는 sessions mode를
    /// 유지함
    func testAiChatHistoryTabSwitchAwayAndBackPreservesSessionsRoute() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChatSessions(sessionID)
        aiChatContent.aiChat.mode = .sessions
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [aiChatID: aiChatContent, homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 sidebar/observer 효과를 함께 방출하므로 복원 route와 AiChat mode 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)

        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.showSessionsForChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == aiSessionID
        }
        await store.receive { action in
            guard case .tabContent(_, .aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat 탭을 떠날 때 이전 탭의 in-flight restore 표시를 저장하지 않음
    /// AI Chat 탭 전환 중 효과는 취소되므로 저장되는 이전 탭 state도 restoring/model loading UI 상태를 제거해야 한다.
    /// - 검증 내용: AI Chat tab에서 Home tab으로 전환할 때 저장된 AI Chat state의 restore/draft/model loading 상태 정리
    /// - 사전 조건: active AI Chat tab이 `.restoring` status, streaming draft, pending restore, model loading tracking을 가진
    /// 상태
    /// - 기대 결과: tabContentStates에 저장된 이전 AI Chat state가 idle/active 상태로 정리되고 pending restore/model loading 필드를 비움
    func testAiChatTabSwitchAwayClearsSavedInFlightRestoreState() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let restoringUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let restoringSessionID = AiChatSessionID(rawValue: restoringUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .restoring
        aiChatContent.aiChat.restoreSessionID = restoringSessionID
        aiChatContent.aiChat.streamingAssistantDraft = "partial response"
        aiChatContent.aiChat.modelListState = .loading
        aiChatContent.aiChat.modelListRequestID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        aiChatContent.aiChat.modelListProvider = .openai
        aiChatContent.aiChat.modelListProviderOrder = [.openai, .anthropic]
        aiChatContent.aiChat.modelListPendingProviders = [.openai, .anthropic]
        aiChatContent.aiChat.modelListLoadedModelsByProvider = [.openai: []]
        aiChatContent.aiChat.modelListFailedProviders = [
            .anthropic: AiModelListFailure(message: "loading"),
        ]

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 저장된 이전 AI Chat state 정리에 집중함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))
        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.executionPhase, .idle)
        XCTAssertNil(savedAiChatState.streamingAssistantDraft)
        XCTAssertNil(savedAiChatState.restoreSessionID)
        XCTAssertNil(savedAiChatState.restoreOutcome)
        XCTAssertNil(savedAiChatState.restoreFailure)
        XCTAssertEqual(savedAiChatState.modelListState, .idle)
        XCTAssertNil(savedAiChatState.modelListRequestID)
        XCTAssertNil(savedAiChatState.modelListProvider)
        XCTAssertTrue(savedAiChatState.modelListProviderOrder.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListPendingProviders.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListLoadedModelsByProvider.isEmpty)
        XCTAssertTrue(savedAiChatState.modelListFailedProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertEqual(savedAiChatState.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat 탭을 떠날 때 로드 완료된 model catalog를 보존함
    /// AI Chat 탭 전환 중 in-flight loading만 정리하고 이미 로드된 model catalog는 저장된 tab state에 유지해야 한다.
    /// - 검증 내용: loaded modelListState와 catalog tracking이 tabContentStates에 그대로 저장됨
    /// - 사전 조건: active AI Chat tab이 `.loaded` model list와 loaded provider catalog를 가진 상태
    /// - 기대 결과: tab handoff 후 저장된 AI Chat state가 loaded model catalog와 provider metadata를 보존함
    func testAiChatTabSwitchAwayPreservesLoadedModelCatalogState() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let requestUUID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"
        let model = AiProviderModel(
            id: AiModelHandle(provider: .openai, rawValue: "gpt-test"),
            provider: .openai,
            rawModelID: "gpt-test",
            displayName: "GPT Test",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.modelListState = .loaded([model])
        aiChatContent.aiChat.modelListRequestID = requestUUID
        aiChatContent.aiChat.modelListProvider = .openai
        aiChatContent.aiChat.modelListProviderOrder = [.openai]
        aiChatContent.aiChat.modelListPendingProviders = []
        aiChatContent.aiChat.modelListLoadedModelsByProvider = [.openai: [model]]
        aiChatContent.aiChat.modelListFailedProviders = [:]

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 저장된 loaded model catalog 보존만 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))
        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.modelListState, .loaded([model]))
        XCTAssertEqual(savedAiChatState.modelListRequestID, requestUUID)
        XCTAssertEqual(savedAiChatState.modelListProvider, .openai)
        XCTAssertEqual(savedAiChatState.modelListProviderOrder, [.openai])
        XCTAssertTrue(savedAiChatState.modelListPendingProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.modelListLoadedModelsByProvider, [.openai: [model]])
        XCTAssertTrue(savedAiChatState.modelListFailedProviders.isEmpty)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertEqual(savedAiChatState.sessionID, aiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_content_pane_inspector_isolation: Inspector Chat이 열려 있으면 ContentPane cancel을 보내지 않음
    /// ContentPane tab handoff state cleanup은 저장 state에만 적용하고 shared AiChat cancel ID로 Inspector Chat 요청을 끊으면 안 된다.
    /// - 검증 내용: Inspector Chat이 열린 상태에서 AI Chat tab을 떠날 때 저장된 ContentPane state는 정리되지만 cancelInFlightWork를 수신하지 않음
    /// - 사전 조건: active AI Chat tab과 열린 Inspector Chat이 동시에 존재하는 상태
    /// - 기대 결과: 이전 AI Chat tabContentStates의 in-flight restore 표시는 정리되고 Inspector Chat은 계속 표시됨
    func testAiChatTabSwitchAwayDoesNotCancelWhenInspectorChatOpen() async throws {
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let restoringUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let restoringSessionID = AiChatSessionID(rawValue: restoringUUID)
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let homePath = "/Users/test/Home"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .restoring
        aiChatContent.aiChat.restoreSessionID = restoringSessionID
        aiChatContent.aiChat.streamingAssistantDraft = "partial response"

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath(homePath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeID: homeContent]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        // store.exhaustivity = .off: tab handoff는 watcher/navigation 효과를 함께 방출하므로 Inspector가 열린 상태의 저장 state cleanup만
        // 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))

        let savedAiChatState = try XCTUnwrap(store.state.tabContentStates[aiChatID]?.aiChat)
        XCTAssertEqual(savedAiChatState.executionPhase, .idle)
        XCTAssertNil(savedAiChatState.streamingAssistantDraft)
        XCTAssertNil(savedAiChatState.restoreSessionID)
        XCTAssertEqual(savedAiChatState.sessionStatus, .active)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[homeID])
        await store.finish()
    }

    /// Home tab은 Inspector를 지원하지 않고, 디렉토리 tab의 Inspector 상태는 해당 tab으로 돌아올 때 복원된다.
    func testHomeTabHidesInspectorAndDirectoryTabRestoresOwnInspectorState() async {
        let directoryID = ContentTabID()
        let homeID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryID: directoryContent,
            homeID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeID)))

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[homeID])
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.inspectorVisible, true)
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.inspectorPaneExists, false)
        XCTAssertEqual(store.state.tabInspectorStates[directoryID]?.aiChat.sessionID, inspectorSessionID)

        await store.send(.contentTabs(.setCurrent(directoryID)))

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertFalse(store.state.inspector.inspectorPaneExists)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, inspectorSessionID)
        await store.finish()
    }

    /// Fresh Inspector contextual chat은 nil session setup이어도 provider/model refresh를 반드시 실행한다.
    func testFreshInspectorOpenWithNilSessionLoadsProviderModelsAndEnablesSubmitAfterSelection() async throws {
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let model = AiProviderModel(
            id: modelHandle,
            provider: .openai,
            rawModelID: "gpt-test",
            displayName: "GPT Test",
            providerDisplayName: "OpenAI",
            thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
        )
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))
        let connectionsFile = AIConnectionsFile(
            updatedAtMs: 1,
            lastUsedProviderId: .openai,
            providers: [
                AiProvider.openai.rawValue: ProviderRecordFile(
                    providerId: .openai,
                    authMethod: .apiKey,
                    credential: credential,
                    snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                ),
            ],
        )
        let modelListRequestID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: directoryID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let setup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: directoryContent)
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, receivedCredential in
                XCTAssertEqual(provider, .openai)
                XCTAssertEqual(receivedCredential, credential)
                return [model]
            })
        }
        store.exhaustivity = .off

        await store.send(.inspector(.openChat(setup, connectionsFile))) { state in
            state.inspector.inspectorVisible = true
            state.inspector.activeMode = .chat
        }
        await store.receive(\.inspector.aiChat.setup)
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoading(requestID, provider, receivedCredential))) = action
            else {
                return false
            }
            return requestID == modelListRequestID
                && provider == .openai
                && receivedCredential == credential
        }
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoaded(requestID, provider, models))) = action else {
                return false
            }
            return requestID == modelListRequestID
                && provider == .openai
                && models == [model]
        }

        await store.send(.inspector(.aiChat(.selectedModelChanged(modelHandle)))) { state in
            state.inspector.aiChat.selectedModelHandle = modelHandle
        }
        await store.send(.inspector(.aiChat(.draftTextChanged("Question from fresh inspector")))) { state in
            state.inspector.aiChat.draftText = "Question from fresh inspector"
        }

        XCTAssertEqual(store.state.inspector.aiChat.modelListState, .loaded([model]))
        XCTAssertEqual(store.state.inspector.aiChat.chatInputDisplayModel.modelLabel, "GPT Test")
        XCTAssertTrue(store.state.inspector.aiChat.canSubmit)
        XCTAssertTrue(store.state.inspector.aiChat.chatInputDisplayModel.canSubmit)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: pending dormant owner만 최신 provider authority를 수신한다.
    /// 비활성 owner의 lifecycle 안전성을 보존하면서 unrelated dormant owner의 catalog를 시작하지 않는지 검증한다.
    /// - 검증 내용: 네 owner collection의 pending snapshot 갱신과 pending 없는 snapshot의 보존
    /// - 사전 조건: active tab은 Home이고 Inspector는 닫혀 있으며 각 dormant collection에 pending owner가 있음
    /// - 기대 결과: pending owner는 provider 제거를 반영하고 unrelated dormant owner는 기존 snapshot을 유지함
    func testPendingDormantOwnersRefreshProviderAuthorityWithoutFullForwarding() async throws {
        let pendingTabID = ContentTabID()
        let dormantContentTabID = ContentTabID()
        let dormantInspectorTabID = ContentTabID()
        let dormantContentSessionID = AiChatSessionID(rawValue: UUID())
        let dormantInspectorSessionID = AiChatSessionID(rawValue: UUID())
        let fixture = try makePendingProviderAuthorityFixture()
        var dormantContent = FileManagerContentFeature.State()
        dormantContent.aiChat.providerConnectionSnapshot = .known([.openai])
        var dormantInspector = FileManagerInspectorFeature.State()
        dormantInspector.aiChat.providerConnectionSnapshot = .known([.openai])

        var state = FileManagerFeature.State()
        state.inspector.inspectorVisible = false
        state.tabContentStates[pendingTabID] = fixture.content
        state.tabContentStates[dormantContentTabID] = dormantContent
        state.tabInspectorStates[pendingTabID] = fixture.inspector
        state.tabInspectorStates[dormantInspectorTabID] = dormantInspector
        state.backgroundAiChatStates[fixture.sessionID] = fixture.content
        state.backgroundAiChatStates[dormantContentSessionID] = dormantContent
        state.backgroundInspectorAiChatStates[fixture.sessionID] = fixture.inspector
        state.backgroundInspectorAiChatStates[dormantInspectorSessionID] = dormantInspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // Window warm-up fire-and-forget effect는 dormant owner authority 계약의 검증 대상이 아니다.
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(.empty()))

        XCTAssertEqual(
            store.state.tabContentStates[pendingTabID]?.aiChat.providerConnectionSnapshot,
            AiChatProviderConnectionSnapshot.known([]),
        )
        XCTAssertEqual(
            store.state.tabInspectorStates[pendingTabID]?.aiChat.providerConnectionSnapshot,
            AiChatProviderConnectionSnapshot.known([]),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[fixture.sessionID]?.aiChat.providerConnectionSnapshot,
            AiChatProviderConnectionSnapshot.known([]),
        )
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[fixture.sessionID]?.aiChat.providerConnectionSnapshot,
            AiChatProviderConnectionSnapshot.known([]),
        )
        assertDormantProviderAuthorityUnchanged(
            state: store.state,
            contentTabID: dormantContentTabID,
            inspectorTabID: dormantInspectorTabID,
            contentSessionID: dormantContentSessionID,
            inspectorSessionID: dormantInspectorSessionID,
        )
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: AI Chat tab active + Inspector visible + chat mode인 경우
    /// ContentPane과 Inspector 모두 providerConnectionsUpdated를 수신함
    func testBothContentAndInspectorReceiveWhenAiChatActiveAndInspectorOpen() async {
        let sessionID = "test-session"
        let aiChatID = ContentTabID()
        let connectionsFile = AIConnectionsFile.empty()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatID,
            recentlyClosed: nil,
        )
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(connectionsFile))

        // ContentPane AI Chat으로 전달
        await store.receive { action in
            guard case .tabContent(_, .aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        // Inspector AI Chat으로 전달
        await store.receive { action in
            guard case .inspector(.aiChat(.providerConnectionsUpdated)) = action else { return false }
            return true
        }

        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_content_pane_inspector_isolation

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// ContentPane AI Chat과 Inspector AI Chat의 state는 독립적으로 동작함
    /// 같은 AiChatFeature.State 타입이지만 content.aiChat과 inspector.aiChat이 완전히 분리되어
    /// 서로의 action이 상대방 state에 영향을 주지 않음을 검증한다.
    /// - 검증 내용: content.aiChat.mode 변경이 inspector.aiChat.mode에 영향을 주지 않음
    /// - 사전 조건: content.aiChat.mode == .chat, inspector.aiChat.mode == .sessions (기본값)
    /// - 기대 결과: content.aiChat.backToSessionsTapped 후 content mode는 .sessions, inspector mode는 .sessions (영향 없음)
    func testContentPaneAiChatAndInspectorAreIsolated() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        // KCF: FileManagerFeature의 routing reducer가 non-exhaustive side effect를 수행함
        store.exhaustivity = .off

        let inspectorModeBefore = state.inspector.aiChat.mode

        // When: ContentPane AI Chat에 backToSessionsTapped 전송
        await store.sendTabContent(.aiChat(.backToSessionsTapped))

        // Then: ContentPane AI Chat mode가 .sessions로 변경됨
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        // Then: Inspector AI Chat mode는 영향을 받지 않음 (기본값 .sessions 유지)
        XCTAssertEqual(store.state.inspector.aiChat.mode, inspectorModeBefore)
        await store.finish()
    }

    /// ContentPane AI Chat의 늦은 .sessionsAppeared가 현재 chat mode를 덮어쓰지 않음
    /// Inspector AI Chat과 session 목록 persistence에도 아무 영향이 없음을 함께 검증한다.
    /// - 검증 내용: content.aiChat.sessionsAppeared 후 content.aiChat.mode == .chat,
    ///   inspector.aiChat.mode와 persistence 호출은 변경되지 않음
    /// - 사전 조건: content.aiChat.mode == .chat, inspector.aiChat.mode == .sessions
    /// - 기대 결과: 늦게 도착한 lifecycle action이 navigation state를 변경하지 않음
    func testContentPaneStaleSessionsAppearedDoesNotChangeMode() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()
        let listCallCount = LockIsolated(0)

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.listSessions = { _, _ in
                listCallCount.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off

        let inspectorModeBefore = state.inspector.aiChat.mode

        await store.sendTabContent(.aiChat(.sessionsAppeared))

        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.mode, inspectorModeBefore)
        XCTAssertEqual(listCallCount.value, 0)
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_mode_switching

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// ContentPane AI Chat History 버튼이 mode를 .sessions로 전환함
    /// AiChatPageHeaderView에서 .chat mode일 때 History 버튼이 .backToSessionsTapped를 전송하고
    /// mode가 .sessions로 변경됨을 검증한다.
    /// - 검증 내용: .content(.aiChat(.backToSessionsTapped)) 전송 후 content.aiChat.mode == .sessions
    /// - 사전 조건: ContentPane AI Chat mode == .chat
    /// - 기대 결과: mode가 .sessions로 변경됨
    func testAiChatHistoryButtonSwitchesToSessionsMode() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.backToSessionsTapped))

        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }

    /// ContentPane AI Chat History 화면 Back 버튼이 현재 채팅으로 복귀함
    /// AiChatPageHeaderView에서 .sessions mode일 때 Back 버튼이 .returnToChatTapped를 전송하고
    /// 새 session을 만들지 않은 채 기존 sessionID를 유지하며 .chat으로 돌아감을 검증한다.
    /// - 검증 내용: .content(.aiChat(.returnToChatTapped)) 전송 후 content.aiChat.mode == .chat,
    ///   기존 sessionID가 유지되고 restore 상태가 정리됨
    /// - 사전 조건: ContentPane AI Chat mode == .sessions, 기존 sessionID 존재
    /// - 기대 결과: mode가 .chat으로 변경되고 현재 chat session이 유지됨
    func testAiChatBackButtonReturnsToCurrentChatMode() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = sessionID
        state.content.aiChat.restoreSessionID = sessionID
        state.content.aiChat.sessionStatus = .active
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.returnToChatTapped))

        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, sessionID)
        XCTAssertNil(store.state.content.aiChat.restoreOutcome)
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History route가 composite navigation history에 기록됨
    /// ContentPane AI Chat 내부 History/Chat 전환은 FileManager navigation stack과 분리되지 않아야 한다.
    /// - 검증 내용: `.aiChat` ↔ `.aiChatSessions` route가 같은 Back/Forward stack에 기록되고 재생됨
    /// - 사전 조건: AI Chat tab이 `.aiChat(sessionID)` route로 활성화되어 있고 Home route가 backHistory에 있음
    /// - 기대 결과: History 진입, Back, Forward가 각각 route와 AiChat mode를 시간순으로 복원함
    func testAiChatSessionsRouteParticipatesInCompositeNavigationHistory() async throws {
        let tabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChat(sessionID)
        state.content.navigation.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        state.content.aiChat.mode = .chat
        state.content.aiChat.sessionID = aiSessionID
        state.content.aiChat.sessionStatus = .active
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: navigation delegate와 content bridge 효과가 함께 방출되므로 route/mode 불변식만 검증함
        store.exhaustivity = .off

        await store.send(.navigation(.view(.showAiChatSessions(sessionID))))
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChatSessions(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receiveTabContent(\.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home, .aiChat(sessionID)])
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == aiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChatSessions(sessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)

        await store.send(.navigation(.view(.goForward)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == sessionID
        }
        await store.receiveTabContent(\.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(sessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home, .aiChat(sessionID)])
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History route 복원 중 늦은 selected session restore를 무시함
    /// AI Chat History로 돌아온 뒤 이전 selected session restore가 늦게 도착해도 화면이 selected chat으로 되돌아가지 않아야 한다.
    /// - 검증 내용: stale restoreOutcome 처리 후 mode/sessionID/transcript 불변
    /// - 사전 조건: `.aiChatSessions(current)` route와 selected session restore가 pending인 상태
    /// - 기대 결과: `.sessions` mode와 current sessionID를 유지하고 selected session transcript를 적용하지 않음
    func testAiChatSessionsRouteCancelsPendingSelectedSessionRestore() async throws {
        let currentSessionID = try AiChatSessionID(
            rawValue: XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
        )
        let selectedSessionID = try AiChatSessionID(
            rawValue: XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
        )
        let selectedSnapshot = AiChatSessionSnapshot(
            sessionID: selectedSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "selected session")],
            updatedAtMs: 2,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentSessionID
        state.content.aiChat.restoreSessionID = selectedSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedSessionID
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: selectedSessionID,
                title: "Selected session",
                messageCount: 1,
                provider: nil,
                model: nil,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.content.navigation.navigationState = .aiChatSessions(
            currentSessionID.rawValue.uuidString,
        )

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: FileManagerFeature는 navigation/content delegate 효과를 함께 방출하므로 AiChat 상태 불변식만 검증함
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.showSessionsTapped)) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.restoreSessionID = nil
            state.content.aiChat.restoreOutcome = nil
            state.content.aiChat.restoreFailure = nil
        }

        await store.sendTabContent(.aiChat(.restoreOutcome(
            requestedSessionID: selectedSessionID,
            .restored(snapshot: selectedSnapshot),
            restoreFailure: nil,
        )))

        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentSessionID)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, selectedSessionID)
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: History route 복원 후 Return to chat이 route session으로 돌아감
    /// `.aiChatSessions(current)` route replay는 stale selected session이 아니라 route의 current session을 AiChat 상태에 반영해야 한다.
    /// - 검증 내용: route replay 후 Return to chat navigation이 current sessionID로 `.aiChat` route를 생성함
    /// - 사전 조건: AiChat state에는 selected sessionID가 남아 있고 navigation route는 `.aiChatSessions(current)`인 상태
    /// - 기대 결과: AiChat state/session route가 selected session이 아닌 current session으로 복원됨
    func testAiChatSessionsRouteReplayReturnToChatUsesRouteSession() async throws {
        let currentUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)

        var state = FileManagerFeature.State()
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = selectedAiSessionID
        state.content.aiChat.restoreSessionID = selectedAiSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: navigation bridge는 parent delegate 경로를 함께 방출하므로 route replay 후 AiChat route
        // anchor만 검증함
        store.exhaustivity = .off

        await store.sendTabContent(.internal(.applyNavigationState(.aiChatSessions(currentSessionID))))
        await store.receiveTabContent(\.aiChat.showSessionsForChat) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.sessionID = currentAiSessionID
            state.content.aiChat.restoreSessionID = nil
            state.content.aiChat.restoreOutcome = nil
            state.content.aiChat.restoreFailure = nil
            state.content.aiChat.sessionList.selectedSessionID = currentAiSessionID
        }

        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, selectedAiSessionID)

        await store.send(.navigation(.view(.showAiChat(currentSessionID))))
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receiveTabContent(\.aiChat.routeToChatSession) { state in
            state.content.aiChat.mode = .chat
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: History 화면 New Chat 성공 후 active tab anchor를 새 session으로 갱신함
    /// History 화면에서 New Chat 생성이 완료되면 parent navigation과 ContentTab anchor가 새 session route를 기준으로 갱신되어야 한다.
    /// - 검증 내용: `.newChatCreated` 후 `.showAiChat(newSessionID)`와 active tab `.aiChat(newSessionID)` anchor 갱신
    /// - 사전 조건: active AI Chat tab이 `.aiChatSessions(oldSessionID)` route와 old tab anchor를 가진 상태
    /// - 기대 결과: 새 session route가 Back/Forward 및 tab handoff의 기준 anchor가 됨
    func testAiChatHistoryNewChatCreatedUpdatesRouteAndActiveTabAnchor() async throws {
        let oldUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let newUUID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let oldSessionID = oldUUID.uuidString
        let newSessionID = newUUID.uuidString
        let oldAiSessionID = AiChatSessionID(rawValue: oldUUID)
        let newAiSessionID = AiChatSessionID(rawValue: newUUID)
        let tabID = ContentTabID()
        let snapshot = AiChatSessionSnapshot(
            sessionID: newAiSessionID,
            status: .idle,
            provider: nil,
            model: nil,
            transcriptHistory: [],
            updatedAtMs: 2,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: oldSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(oldSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = oldAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.emptyDraftSessionID = newAiSessionID
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // store.exhaustivity = .off: newChatCreated는 parent delegate와 navigation bridge 효과를 연쇄 방출하므로 route/anchor 결과만
        // 검증함
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.newChatCreated(snapshot))) { state in
            state.content.aiChat.mode = .chat
            state.content.aiChat.sessionID = newAiSessionID
            state.content.aiChat.emptyDraftSessionID = newAiSessionID
            state.content.aiChat.restoreSessionID = newAiSessionID
            state.content.aiChat.sessionList.selectedSessionID = newAiSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .delegate(.aiChatSessionCreated(receivedSessionID))) = action
            else { return false }
            return receivedSessionID == newAiSessionID
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else {
                return false
            }
            return receivedTabID == tabID && receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == newSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == newAiSessionID
        }

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: newSessionID))
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(newSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "New Chat")
        XCTAssertEqual(store.state.content.aiChat.sessionID, newAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: selected session restore 실패 시 History route를 유지함
    /// History row 선택 후 restore가 실패하면 실패한 session을 ContentPageNavigation `.aiChat(sessionID)` route로 확정하지 않아야 한다.
    /// - 검증 내용: restore failure 처리 후 navigation route와 active tab anchor가 기존 History 기준으로 유지됨
    /// - 사전 조건: `.aiChatSessions(current)` route에서 selected session restore가 pending인 상태
    /// - 기대 결과: `.sessions` mode와 `.aiChatSessions(current)` route를 유지하고 session list error만 표시함
    func testAiChatSelectedSessionRestoreFailureKeepsSessionsRoute() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .restoring
        state.content.aiChat.restoreSessionID = selectedAiSessionID
        state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: 실패 restore는 parent navigation delegate를 방출하지 않는 불변식만 검증함
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.restoreOutcome(
            requestedSessionID: selectedAiSessionID,
            .failed(reason: .missingRecord),
            restoreFailure: .missingRecord,
        ))) { state in
            state.content.aiChat.sessionList.selectedSessionID = nil
            state.content.aiChat.sessionList.errorMessage = "That chat is no longer available."
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: currentSessionID))
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: AI Chat History에서 selected session restore 성공 후 route가 기록됨
    /// session row 선택은 restore를 먼저 완료하고 성공한 session만 ContentPageNavigation `.aiChat(sessionID)` route로 확정해야 한다.
    /// - 검증 내용: selected session restore 성공 후 Back/Back이 selected chat → History → 이전 chat 순서로 복원됨
    /// - 사전 조건: `.aiChatSessions(current)` route와 이전 `.aiChat(current)` history가 있는 상태
    /// - 기대 결과: restore 성공 전에는 sessions route를 유지하고, 성공 후 selected session route와 sessions route가 history에 시간순으로 남음
    func testAiChatRestoreUsesPromotedOwnerTitleInsteadOfStalePersistedTitle() async throws {
        let tabID = ContentTabID()
        let sessionID = try AiChatSessionID(rawValue: XCTUnwrap(UUID(
            uuidString: "ABABABAB-CDCD-EFEF-0101-232323232323",
        )))
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Stale persisted title",
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "Stale persisted title")],
            updatedAtMs: 1,
        )
        let promotedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .completed,
            customTitle: "Current owner title",
            provider: .openai,
            model: AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini"),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Current owner title"),
                AiChatMessage(role: .assistant, content: "Current answer"),
            ],
            updatedAtMs: 2,
        )
        let promotedSummary = AiChatSessionSummary(snapshot: promotedSnapshot)
        let promotedLock = makeRequestLock(sessionID: sessionID).recordingFinalSnapshot(promotedSnapshot)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(sessionID.rawValue.uuidString)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.restoreSessionID = sessionID
        state.content.aiChat.sessionStatus = .restoring
        state.content.aiChat.sessionList.replaceRow(promotedSummary)
        state.content.aiChat.sessionList.selectedSessionID = sessionID
        state.content.aiChat.backgroundExecutionPhases[promotedLock.requestID] = .completed(promotedLock)
        state.syncContentTabSidebarItems()
        let store = makeTestStore(state: state)
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.restoreOutcome(
            requestedSessionID: sessionID,
            .restored(snapshot: staleSnapshot),
            restoreFailure: nil,
        )))
        await store.receive { action in
            guard case let .tabContent(_, .delegate(.aiChatSessionRestored(receivedSessionID, title))) = action else {
                return false
            }
            return receivedSessionID == sessionID && title == promotedSummary.title
        }

        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, promotedSnapshot.customTitle)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, promotedSnapshot.transcriptHistory)
        XCTAssertEqual(store.state.content.aiChat.executionPhase.lock?.finalSnapshot, promotedSnapshot)
        XCTAssertNil(store.state.content.aiChat.backgroundExecutionPhases[promotedLock.requestID])
    }

    func testAiChatSelectedSessionRouteParticipatesInCompositeNavigationHistory() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let selectedUUID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let currentSessionID = currentUUID.uuidString
        let selectedSessionID = selectedUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let selectedAiSessionID = AiChatSessionID(rawValue: selectedUUID)
        let selectedSnapshot = AiChatSessionSnapshot(
            sessionID: selectedAiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "selected")],
            updatedAtMs: 2,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.navigation.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .home),
            ContentPageNavigationHistorySnapshot(navigationState: .aiChat(currentSessionID)),
        ]
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: selectedAiSessionID,
                title: "Selected session",
                messageCount: 1,
                provider: nil,
                model: nil,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { sessionID in
                sessionID == selectedAiSessionID ? selectedSnapshot : nil
            }
        }
        // store.exhaustivity = .off: selected session restore 성공 delegate와 navigation delegate가 함께 방출되므로 composite
        // route 순서만 검증함
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionRowTapped(selectedAiSessionID))) { state in
            state.content.aiChat.mode = .sessions
            state.content.aiChat.restoreSessionID = selectedAiSessionID
            state.content.aiChat.sessionList.selectedSessionID = selectedAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))

        await store.receiveTabContent(\.aiChat.restoreOutcome)
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, selectedAiSessionID)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .active)
        XCTAssertEqual(store.state.content.aiChat.restoreSessionID, selectedAiSessionID)
        XCTAssertEqual(store.state.content.aiChat.restoreOutcome, .restored(snapshot: selectedSnapshot))
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, selectedSnapshot.transcriptHistory)
        XCTAssertNil(store.state.content.aiChat.emptyDraftSessionID)
        XCTAssertNil(store.state.content.aiChat.sessionList.errorMessage)
        await store.receive { action in
            guard case let .tabContent(_, .delegate(.aiChatSessionRestored(receivedSessionID, title))) = action else {
                return false
            }
            return receivedSessionID == selectedAiSessionID && title == "Selected session"
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else {
                return false
            }
            return receivedTabID == tabID && receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == selectedSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == selectedAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(selectedSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "Selected session")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "Selected session")
        XCTAssertEqual(
            store.state.content.navigation.backHistory.map(\.navigationState),
            [.home, .aiChat(currentSessionID), .aiChatSessions(currentSessionID)],
        )
        XCTAssertEqual(store.state.content.navigation.forwardHistory.map(\.navigationState), [])

        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChatSessions(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChatSessions(receivedSessionID)))) = action
            else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receiveTabContent(\.aiChat.showSessionsForChat)

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChatSessions(currentSessionID))
        XCTAssertEqual(
            store.state.content.navigation.backHistory.map(\.navigationState),
            [.home, .aiChat(currentSessionID)],
        )
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChat(selectedSessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)

        // 기존 세션에서 목록으로 돌아온 뒤 다시 Back하면 route에 저장된 직전 새 채팅으로 복귀해야 한다.
        await store.send(.navigation(.view(.goBack)))
        await store.receive(\.navigation.internal.performNavigation)
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.routeToChatSession(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == currentAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.content.navigation.backHistory.map(\.navigationState), [.home])
        XCTAssertEqual(
            store.state.content.navigation.forwardHistory.map(\.navigationState),
            [.aiChat(selectedSessionID), .aiChatSessions(currentSessionID)],
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.sessionID, currentAiSessionID)
        await store.finish()
    }

    /// CTM-005-ai_chat_mode_switching: 진행 중인 현재 세션 row 선택 시 Chat route로 승격됨
    /// History에서 현재 실행 중인 세션을 다시 선택하는 shortcut도 parent navigation anchor를 `.aiChat`으로 확정해야 한다.
    /// - 검증 내용: current processing session tap이 restore 성공과 동일한 route/anchor 갱신 체인을 방출함
    /// - 사전 조건: `.aiChatSessions(current)` route와 processing 상태의 현재 AI Chat 세션
    /// - 기대 결과: Chat mode 전환 후 active tab anchor와 navigation state가 `.aiChat(current)`로 승격
    func testAiChatProcessingSessionTapPromotesRouteFromSessionsToChat() async throws {
        let tabID = ContentTabID()
        let currentUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let currentSessionID = currentUUID.uuidString
        let currentAiSessionID = AiChatSessionID(rawValue: currentUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID =
            try AiChatRequestID(rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")))
        let runID = try AiChatRunID(rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")))
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: currentAiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "continue",
            submittedAtMs: 1234,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "continue")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: currentSessionID),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .aiChatSessions(currentSessionID)
        state.content.aiChat.mode = .sessions
        state.content.aiChat.sessionID = currentAiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.executionPhase = .processing(requestLock)
        state.content.aiChat.sessionList.allRows = [
            AiChatSessionSummary(
                sessionID: currentAiSessionID,
                title: "Current session",
                messageCount: 1,
                provider: .openai,
                model: modelHandle,
                createdAtMs: 1,
                updatedAtMs: 2,
                status: .active,
            ),
        ]
        state.content.aiChat.sessionList.rows = state.content.aiChat.sessionList.allRows
        state.tabContentStates = [tabID: state.content]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionRowTapped(currentAiSessionID))) { state in
            state.content.aiChat.mode = .chat
        }
        await store.receive { action in
            guard case let .tabContent(_, .delegate(.aiChatSessionRestored(receivedSessionID, title))) = action else {
                return false
            }
            return receivedSessionID == currentAiSessionID && title == "Current session"
        }
        await store.receive { action in
            guard case let .navigation(.view(.showAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else { return false }
            return receivedTabID == tabID && receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.internal(.performShowAiChat(receivedSessionID))) = action else { return false }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action else {
                return false
            }
            return receivedSessionID == currentSessionID
        }
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.internal.applyClearSelection)
        await store.receive { action in
            guard case let .tabContent(_, .aiChat(.routeToChatSession(receivedSessionID))) = action
            else { return false }
            return receivedSessionID == currentAiSessionID
        }

        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(currentSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .aiChat(sessionID: currentSessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "Current session")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "Current session")
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        await store.finish()
    }

    /// ContentPane AI Chat Settings 버튼 delegate가 Window delegate까지 전달됨
    /// provider 미연결 empty state의 Open Settings 버튼은 AiChatFeature delegate를 거쳐
    /// FileManagerContentFeature와 WindowCommandRoutingReducer를 통과해야 실제 Settings를 연다.
    /// - 검증 내용: .content(.aiChat(.openSettingsTapped)) 전송 후 .delegate(.openAISettings) 수신
    /// - 기대 결과: ContentPane AI Chat에서도 Inspector Chat과 동일하게 Settings 열기 delegate가 전파됨
    func testContentPaneAiChatOpenSettingsRoutesToWindowDelegate() async {
        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .chat
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.openSettingsTapped))
        await store.receive { action in
            guard case .tabContent(_, .delegate(.openAISettings)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .delegate(.openAISettings) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// 저장된 content state가 없는 AI Chat tab은 첫 렌더 전에 .chat mode로 초기화된다.
    /// 기본 AiChatState(.sessions)가 먼저 렌더링되면 History/No Sessions 화면이 순간 노출되므로,
    /// missing tab state 복원 경로에서 ContentPane AI Chat을 즉시 채팅 화면으로 맞춘다.
    func testSwitchingToNewAiChatTabInitializesChatModeBeforeRender() async {
        let homeID = ContentTabID()
        let aiChatID = ContentTabID()
        let sessionID = "new-ai-chat-tab-session"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))

        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        XCTAssertEqual(
            store.state.tabContentStates[aiChatID]?.navigation.navigationState,
            .aiChat(sessionID),
            "AI Chat tab restore must expose an AI Chat navigation route before render",
        )
        XCTAssertEqual(store.state.tabContentStates[aiChatID]?.aiChat.mode, .chat)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        await store.finish()
    }

    /// AI Chat tab은 Inspector를 지원하지 않으므로 active Inspector projection을 숨긴다.
    func testSwitchingToAiChatTabHidesOpenInspectorChat() async {
        let homeID = ContentTabID()
        let aiChatID = ContentTabID()
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: "inspector-close-session"),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent]
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(aiChatID)))

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.tabInspectorStates[aiChatID])
        XCTAssertEqual(store.state.content.aiChat.mode, .chat)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: navigation replay로 AI Chat route가 복원될 때 Inspector Chat을 닫음
    /// Back/Forward replay는 tab handoff를 거치지 않고 active tab anchor만 갱신하므로 Inspector Chat close를 anchor sync 경로에서 보장해야
    /// 한다.
    /// - 검증 내용: `.aiChat` navigation delegate가 active tab anchor를 갱신하기 전에 Inspector Chat close를 방출함
    /// - 사전 조건: Home tab에서 Inspector Chat이 열린 상태로 `.aiChat(sessionID)` route replay가 들어옴
    /// - 기대 결과: Inspector Chat이 닫히고 active tab anchor가 AI Chat session으로 갱신됨
    func testAiChatNavigationReplayClosesOpenInspectorChat() async {
        let homeID = ContentTabID()
        let sessionID = "inspector-replay-session"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.navigation(.delegate(.navigateToState(.aiChat(sessionID)))))
        await store.receive { action in
            guard case .inspector(.closeChat) = action else { return false }
            return true
        } assert: { state in
            state.inspector.inspectorVisible = false
        }
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else { return false }
            return receivedTabID == homeID && receivedSessionID == sessionID
        }
        await store.receive { action in
            guard case let .tabContent(_, .internal(.applyNavigationState(.aiChat(receivedSessionID)))) = action
            else { return false }
            return receivedSessionID == sessionID
        }
        XCTAssertEqual(store.state.contentTabs.tabs[id: homeID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        await store.finish()
    }

    /// .aiChat route로 전환된 tab은 navigation/entry chrome을 표시하지 않음
    /// FileManagerContentPaneView에서 .aiChat anchor는 homeDefault나 directory/collection과 달리
    /// ToolbarView/ContentPageView/BreadcrumbBarView를 렌더링하지 않고 AiChatPageView만 렌더링한다.
    /// resyncNavigationStateForActiveContentTab가 .aiChat을 .home으로 매핑하지 않음을 간접 검증한다.
    /// - 검증 내용: .aiChat tab 전환 후 content.navigation.navigationState가 .home으로 reset되지 않고
    ///   tab anchor가 .aiChat을 유지함
    /// - 사전 조건: Directory anchor tab에서 .aiChat tab으로 전환
    /// - 기대 결과: AI Chat tab anchor 유지, navigation state가 .home으로 overwrite되지 않음
    func testAiChatRouteHidesFolderChrome() async {
        let aiChatID = ContentTabID()
        let homeID = ContentTabID()
        let sessionID = "chrome-test-session"

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        aiChatContent.aiChat.sessionStatus = .active

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, aiChatID: aiChatContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        // Home → AI Chat tab으로 전환
        await store.send(.contentTabs(.setCurrent(aiChatID)))

        // .aiChat tab anchor 유지 (resync가 .home으로 overwrite하지 않음)
        XCTAssertEqual(store.state.contentTabs.activeTabID, aiChatID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: aiChatID]?.page, .aiChat)

        // resyncNavigationStateForActiveContentTab가 .aiChat에 대해 nil을 반환하므로
        // navigation state가 directory/home path로 overwrite되지 않음
        guard let restoredAiChatContent = store.state.tabContentStates[aiChatID] else {
            XCTFail("AI Chat tab content should be preserved in tabContentStates")
            return
        }
        XCTAssertEqual(restoredAiChatContent.aiChat.mode, .chat)
        XCTAssertEqual(restoredAiChatContent.aiChat.sessionStatus, .active)
        XCTAssertNotNil(restoredAiChatContent.aiChat.sessionID)
        await store.finish()
    }

    func testActiveAiChatPageCloseDoesNotCancelGeneration() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = try AiChatRequestID(
            rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        )
        let runID = try AiChatRunID(
            rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")),
        )
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: aiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "test")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))

        await store.receiveTabContent(\.internal.applyNavigationState)

        await store.skipReceivedActions()
        await store.finish()

        let savedBackgroundState = store.state.backgroundAiChatStates[aiSessionID]
        XCTAssertNotNil(savedBackgroundState, "processing AI Chat state should be saved to background")
        XCTAssertEqual(savedBackgroundState?.aiChat.executionPhase, .processing(requestLock))
    }
}

@MainActor
extension CTM005IndependentContentTabSessionTests {
    func testInspectorClosePreservesInspectorGenerationWhileContentAiChatIsProcessing() async {
        let contentSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let contentLock = makeRequestLock(sessionID: contentSessionID)
        let inspectorLock = makeRequestLock(sessionID: inspectorSessionID)

        var contentState = FileManagerContentFeature.State()
        contentState.aiChat.sessionID = contentSessionID
        contentState.aiChat.sessionStatus = .active
        contentState.aiChat.executionPhase = .processing(contentLock)

        var state = FileManagerFeature.State()
        state.content = contentState
        state.inspector.inspectorVisible = true
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
        state.inspector.aiChat.executionPhase = .processing(inspectorLock)
        state.inspector.aiChat.lockedModelHandle = inspectorLock.selectedModelHandle

        let homeID = ContentTabID()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.inspector(.closeChat)) { state in
            state.inspector.inspectorVisible = false
        }

        XCTAssertTrue(store.state.content.aiChat.executionPhase.isProcessing)
        XCTAssertEqual(store.state.content.aiChat.sessionID, contentSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .processing(inspectorLock))
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, inspectorSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, inspectorLock.selectedModelHandle)

        await store.finish()
    }

    func testExplicitCancelTappedCancelsContentAiChatGeneration() async {
        let contentSessionID = AiChatSessionID(rawValue: UUID())
        let contentLock = makeRequestLock(sessionID: contentSessionID)

        var contentState = FileManagerContentFeature.State()
        contentState.aiChat.sessionID = contentSessionID
        contentState.aiChat.sessionStatus = .active
        contentState.aiChat.executionPhase = .processing(contentLock)
        contentState.aiChat.lockedModelHandle = contentLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.content = contentState

        let homeID = ContentTabID()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            )],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.cancelTapped))

        guard case .cancelled = store.state.content.aiChat.executionPhase else {
            XCTFail(
                "Expected cancelled execution phase after cancelTapped, got \(store.state.content.aiChat.executionPhase)",
            )
            return
        }
        XCTAssertNil(store.state.content.aiChat.lockedModelHandle)
        XCTAssertNil(store.state.content.aiChat.streamingAssistantDraft)

        await store.finish()
    }

    func testContentPaneCancelDoesNotRemoveBackgroundAiChatState() async {
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .processing(requestLock)
        backgroundContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeTabID: homeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.cancelInFlightWork))

        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        await store.finish()
    }

    func testClosedAiChatFinalEventSavesSnapshotThroughBackgroundState() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()

        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertTrue(store.state.content.aiChat.sessionList.rows.isEmpty)

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.sendTabContent(.aiChat(.executionEvent(.final(response: response))))

        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == aiSessionID
        } assert: { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, aiSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertFalse(store.state.content.aiChat.sessionList.rows.contains { $0.sessionID == aiSessionID })
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testClosingAiChatTabPreservesBackgroundExecutionPhasesAndHandlesFinalEvent() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .idle
        aiChatContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()

        let backgroundState = store.state.backgroundAiChatStates[aiSessionID]
        XCTAssertNotNil(backgroundState)
        XCTAssertEqual(backgroundState?.aiChat.executionPhase, .idle)
        XCTAssertEqual(
            backgroundState?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .processing(requestLock),
        )

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.sendTabContent(.aiChat(.executionEvent(.final(response: response))))

        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == aiSessionID
        } assert: { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, aiSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertFalse(store.state.content.aiChat.sessionList.rows.contains { $0.sessionID == aiSessionID })
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testStaleBackgroundSnapshotDoesNotOverwriteAiChatTabTitle() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let currentLock = makeRequestLock(sessionID: sessionID)
        let staleSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Stale title",
            preview: nil,
            messageCount: 1,
            provider: staleLock.context.provider,
            model: staleLock.context.model,
            createdAtMs: 1_234_567_890_000,
            updatedAtMs: 1_234_567_891_000,
            status: .active,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .processing(currentLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Current title",
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.backgroundAiChatStates[sessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: nil,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "Current title")
        XCTAssertEqual(
            store.state.sidebar.contentTabSidebarItems.first(where: { $0.id == tabID })?.title,
            "Current title",
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[sessionID]?.aiChat.executionPhase,
            .processing(currentLock),
        )
    }

    func testBackgroundSnapshotOwnerDoesNotOverwriteNewerActiveAiChatTabTitle() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let currentLock = makeRequestLock(sessionID: sessionID)
        let sharedUpdatedAtMs: Int64 = 1_234_567_893_000
        let staleSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R1 title",
            preview: "R1 done",
            messageCount: 2,
            provider: staleLock.context.provider,
            model: staleLock.context.model,
            createdAtMs: 1_234_567_890_000,
            updatedAtMs: sharedUpdatedAtMs,
            status: .active,
        )
        let currentSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R2 title",
            preview: "R2 done",
            messageCount: 3,
            provider: currentLock.context.provider,
            model: currentLock.context.model,
            createdAtMs: 1_234_567_890_000,
            updatedAtMs: sharedUpdatedAtMs,
            status: .active,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .user, content: "R2 question"),
            AiChatMessage(role: .assistant, content: "R2 done"),
        ]
        activeContent.aiChat.executionPhase = .completed(currentLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [currentSummary],
            selectedSessionID: sessionID,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundExecutionPhases[staleLock.requestID] = .completed(staleLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: currentSummary.title,
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: nil,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, currentSummary)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, currentSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, currentSummary.title)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(currentLock))
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testLateBackgroundSnapshotDoesNotOverwriteNewerActiveTranscript() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let backgroundLock = makeRequestLock(sessionID: sessionID)
        let activeLock = makeRequestLock(sessionID: sessionID).recordingTerminal(
            at: 1_234_567_893_000,
            failure: nil,
            wasCancelled: false,
        )
        let staleBackgroundSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Background R1",
            preview: "R1 done",
            messageCount: 2,
            provider: backgroundLock.context.provider,
            model: backgroundLock.context.model,
            createdAtMs: 1_234_567_891_000,
            updatedAtMs: 1_234_567_891_000,
            status: .active,
        )
        let activeSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Active R2",
            preview: "R2 done",
            messageCount: 3,
            provider: activeLock.context.provider,
            model: activeLock.context.model,
            createdAtMs: 1_234_567_893_000,
            updatedAtMs: 1_234_567_893_000,
            status: .active,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .user, content: "R2 question"),
            AiChatMessage(role: .assistant, content: "R2 done"),
        ]
        activeContent.aiChat.executionPhase = .completed(activeLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [activeSummary],
            selectedSessionID: sessionID,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .assistant, content: "R1 done"),
        ]
        backgroundContent.aiChat.executionPhase = .completed(backgroundLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_893))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleBackgroundSummary,
            snapshot: nil,
            requestID: nil,
            runID: nil,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), [
            "R1 question",
            "R2 question",
            "R2 done",
        ])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(activeLock))
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.messageCount, 3)
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.preview, "R2 done")
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testEqualFreshnessBackgroundSnapshotDoesNotOverwriteNewerActivePayload() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let selectedSessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let currentLock = makeRequestLock(sessionID: sessionID)
        let sharedUpdatedAtMs: Int64 = 1_234_567_893_000
        let staleTranscript = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .assistant, content: "R1 done"),
        ]
        let currentTranscript = [
            AiChatMessage(role: .user, content: "R2 question"),
            AiChatMessage(role: .assistant, content: "R2 done"),
        ]
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "R1 title",
            provider: nil,
            model: nil,
            selectedThinking: .effort(.low),
            transcriptHistory: staleTranscript,
            lastRequestID: staleLock.requestID,
            lastRunID: staleLock.runID,
            lastRequestContext: nil,
            updatedAtMs: sharedUpdatedAtMs,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)
        let currentSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R2 title",
            preview: "R2 done",
            messageCount: currentTranscript.count,
            provider: currentLock.context.provider,
            model: currentLock.context.model,
            createdAtMs: staleSummary.createdAtMs,
            updatedAtMs: sharedUpdatedAtMs,
            status: .active,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .completed
        activeContent.aiChat.currentSessionCustomTitle = currentSummary.title
        activeContent.aiChat.transcriptHistory = currentTranscript
        activeContent.aiChat.lastRequestContext = currentLock.context.requestContext
        activeContent.aiChat.lastRequestContextModelHandle = currentLock.context.model
        activeContent.aiChat.selectedModelHandle = currentLock.context.model
        activeContent.aiChat.selectedThinking = .effort(.high)
        activeContent.aiChat.executionPhase = .completed(currentLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [currentSummary],
            errorMessage: "R2 error",
            selectedSessionID: selectedSessionID,
            unreadCompletedSessionIDs: [sessionID, selectedSessionID],
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.currentSessionCustomTitle = staleSummary.title
        backgroundContent.aiChat.transcriptHistory = staleTranscript
        backgroundContent.aiChat.selectedThinking = .effort(.low)
        backgroundContent.aiChat.backgroundExecutionPhases[staleLock.requestID] = .completed(
            staleLock.recordingFinalSnapshot(staleSnapshot),
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: currentSummary.title,
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: staleSnapshot,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, currentSummary.title)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, currentTranscript)
        XCTAssertEqual(store.state.content.aiChat.lastRequestContext, currentLock.context.requestContext)
        XCTAssertEqual(store.state.content.aiChat.lastRequestContextModelHandle, currentLock.context.model)
        XCTAssertEqual(store.state.content.aiChat.selectedModelHandle, currentLock.context.model)
        XCTAssertEqual(store.state.content.aiChat.selectedThinking, .effort(.high))
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .completed)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(currentLock))
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, currentSummary)
        XCTAssertEqual(store.state.content.aiChat.sessionList.selectedSessionID, selectedSessionID)
        XCTAssertEqual(
            store.state.content.aiChat.sessionList.unreadCompletedSessionIDs,
            [sessionID, selectedSessionID],
        )
        XCTAssertEqual(store.state.content.aiChat.sessionList.errorMessage, "R2 error")
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, currentSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, currentSummary.title)
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testIdenticalSummaryBackgroundSnapshotDoesNotOverwriteDifferentActivePayload() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let currentLock = makeRequestLock(sessionID: sessionID)
        let sharedUpdatedAtMs: Int64 = 1_234_567_893_500
        let staleTranscript = [
            AiChatMessage(role: .user, content: "Same   question"),
            AiChatMessage(role: .assistant, content: "Same answer"),
        ]
        let currentTranscript = [
            AiChatMessage(role: .user, content: "Same question"),
            AiChatMessage(role: .assistant, content: "Same answer"),
        ]
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Canonical title",
            provider: currentLock.context.provider,
            model: currentLock.context.model,
            selectedThinking: .effort(.low),
            transcriptHistory: staleTranscript,
            lastRequestID: staleLock.requestID,
            lastRunID: staleLock.runID,
            lastRequestContext: nil,
            updatedAtMs: sharedUpdatedAtMs,
        )
        let currentSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Canonical title",
            provider: currentLock.context.provider,
            model: currentLock.context.model,
            selectedThinking: .effort(.high),
            transcriptHistory: currentTranscript,
            lastRequestID: currentLock.requestID,
            lastRunID: currentLock.runID,
            lastRequestContext: nil,
            updatedAtMs: sharedUpdatedAtMs,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)
        let currentSummary = AiChatSessionSummary(snapshot: currentSnapshot)
        XCTAssertEqual(staleSummary, currentSummary)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .completed
        activeContent.aiChat.currentSessionCustomTitle = currentSummary.title
        activeContent.aiChat.transcriptHistory = currentTranscript
        activeContent.aiChat.selectedModelHandle = currentLock.context.model
        activeContent.aiChat.selectedThinking = .effort(.high)
        activeContent.aiChat.executionPhase = .completed(currentLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(allRows: [currentSummary])

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.transcriptHistory = staleTranscript
        backgroundContent.aiChat.selectedThinking = .effort(.low)
        backgroundContent.aiChat.backgroundExecutionPhases[staleLock.requestID] = .completed(
            staleLock.recordingFinalSnapshot(staleSnapshot),
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: currentSummary.title,
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()
        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: staleSnapshot,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, currentTranscript)
        XCTAssertEqual(store.state.content.aiChat.selectedThinking, .effort(.high))
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(currentLock))
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows, [currentSummary])
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, currentSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, currentSummary.title)
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testStaleForegroundSnapshotDoesNotOverwriteNewerVisibleTranscript() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let sharedUpdatedAtMs: Int64 = 1_234_567_893_000
        let staleTranscript = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .assistant, content: "R1 done"),
        ]
        let currentTranscript = [
            AiChatMessage(role: .user, content: "R1 question"),
            AiChatMessage(role: .user, content: "R2 question"),
            AiChatMessage(role: .assistant, content: "R2 done"),
        ]
        let staleSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "R1 title",
            provider: staleLock.context.provider,
            model: staleLock.context.model,
            selectedModelRow: staleLock.selectedModelRow,
            selectedThinking: staleLock.context.selectedThinking,
            transcriptHistory: staleTranscript,
            lastRequestID: staleLock.requestID,
            lastRunID: staleLock.runID,
            lastRequestContext: staleLock.context.requestContext,
            updatedAtMs: sharedUpdatedAtMs,
        )
        let staleSummary = AiChatSessionSummary(snapshot: staleSnapshot)
        let currentSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R2 title",
            preview: "R2 done",
            messageCount: currentTranscript.count,
            provider: staleLock.context.provider,
            model: staleLock.context.model,
            createdAtMs: staleSummary.createdAtMs,
            updatedAtMs: sharedUpdatedAtMs,
            status: .active,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.currentSessionCustomTitle = currentSummary.title
        activeContent.aiChat.transcriptHistory = currentTranscript
        activeContent.aiChat.executionPhase = .completed(staleLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [currentSummary],
            selectedSessionID: sessionID,
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: currentSummary.title,
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: staleSnapshot,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, currentTranscript)
        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, currentSummary.title)
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, currentSummary)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, currentSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, currentSummary.title)
    }

    func testEqualFreshnessSnapshotDoesNotRevertRenamedAiChatTitle() async {
        let tabID = ContentTabID()
        let sessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: sessionID)
        let sharedUpdatedAtMs: Int64 = 1_234_567_893_000
        let staleSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R1 title",
            preview: "done",
            messageCount: 2,
            provider: staleLock.context.provider,
            model: staleLock.context.model,
            createdAtMs: 1_234_567_890_000,
            updatedAtMs: sharedUpdatedAtMs,
            status: .active,
        )
        let renamedSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "R2 title",
            preview: staleSummary.preview,
            messageCount: staleSummary.messageCount,
            provider: staleSummary.provider,
            model: staleSummary.model,
            createdAtMs: staleSummary.createdAtMs,
            updatedAtMs: sharedUpdatedAtMs,
            status: staleSummary.status,
        )

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.currentSessionCustomTitle = renamedSummary.title
        activeContent.aiChat.executionPhase = .completed(staleLock)
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [renamedSummary],
            selectedSessionID: sessionID,
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: renamedSummary.title,
                    iconName: "message",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionSnapshotSaved(
            staleSummary,
            snapshot: nil,
            requestID: staleLock.requestID,
            runID: staleLock.runID,
        )))
        await store.finish()

        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, renamedSummary.title)
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, renamedSummary)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, renamedSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, renamedSummary.title)
    }

    func testBackgroundFinalSnapshotRefreshUsesFinalTranscript() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID).recordingCustomTitle("Renamed background")
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]
        activeContent.aiChat.sessionList = AiChatSessionListState(
            allRows: [AiChatSessionSummary(
                sessionID: sessionID,
                title: "Active",
                preview: "test",
                messageCount: 1,
                provider: requestLock.context.provider,
                model: requestLock.context.model,
                createdAtMs: 1_234_567_890_000,
                updatedAtMs: 1_234_567_890_000,
                status: .active,
            )],
            selectedSessionID: sessionID,
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.mode = .chat
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.transcriptHistory = []
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_891))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        let assistantMessage = AiChatMessage(role: .assistant, content: "done")
        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: assistantMessage,
            completedAtMs: 1_234_567_891_000,
        )
        let expectedTranscript = [
            AiChatMessage(role: .user, content: "test"),
            AiChatMessage(role: .assistant, content: "done", createdAtMs: 1_234_567_891_000),
        ]
        let expectedSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Renamed background",
            provider: requestLock.context.provider,
            model: requestLock.context.model,
            selectedModelRow: requestLock.selectedModelRow,
            selectedThinking: requestLock.context.selectedThinking,
            transcriptHistory: expectedTranscript,
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
        let expectedSummary = AiChatSessionSummary(snapshot: expectedSnapshot)

        await store.send(.backgroundAiChat(.executionEvent(.final(response: response))))
        await store.receive { action in
            guard case let .backgroundAiChatSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary == expectedSummary
        } assert: { state in
            state.content.aiChat.currentSessionCustomTitle = "Renamed background"
            state.content.aiChat.transcriptHistory = expectedTranscript
            state.content.aiChat.sessionList.allRows = [expectedSummary]
            state.content.aiChat.sessionList.rows = [expectedSummary]
            state.content.aiChat.sessionList.selectedSessionID = sessionID
            state.backgroundAiChatStates.removeValue(forKey: sessionID)
        }
        await store.finish()

        XCTAssertEqual(savedSnapshots.value.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(savedSnapshots.value.first?.customTitle, "Renamed background")
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.title, "Renamed background")
        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, "Renamed background")
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testAiChatTabSwitchDoesNotPreserveSavedCompletedBackgroundOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let savedCompletedLock = requestLock.clearingFinalSnapshot()

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(savedCompletedLock)

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testAiChatTabSwitchPreservesForegroundOwnerUnderLockSession() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let ownerSessionID = AiChatSessionID(rawValue: UUID())
        let routeSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: ownerSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = routeSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = requestLock.request.messages

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: routeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundAiChatStates[routeSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[ownerSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
    }

    func testAiChatTabSwitchPreservesBackgroundRequestOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.executionPhase = .processing(requestLock)
        aiChatContent.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        aiChatContent.aiChat.transcriptHistory = requestLock.request.messages

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, aiSessionID)

        await store.send(.contentTabs(.setCurrent(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(requestLock))
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testAddBackgroundAiChatStateMergesExistingSameSessionOwner() {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let existingLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let existingOwner = existingLock.recordingFinalSnapshot(finalSnapshot)

        var existingContent = FileManagerContentFeature.State()
        existingContent.aiChat.sessionID = aiSessionID
        existingContent.aiChat.executionPhase = .completed(existingOwner)

        var newContent = FileManagerContentFeature.State()
        newContent.aiChat.sessionID = aiSessionID
        newContent.aiChat.executionPhase = .processing(newLock)

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = existingContent
        state.addBackgroundAiChatState(sessionID: aiSessionID, state: newContent)

        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(newLock),
        )
        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[existingLock.requestID],
            .completed(existingOwner),
        )
    }

    func testBackgroundSnapshotPersistedRemovesOnlyMatchingRequestOwner() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: sessionID)
        let newLock = makeRequestLock(sessionID: sessionID)
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "old done"),
            ],
            lastRequestID: oldLock.requestID,
            lastRunID: oldLock.runID,
            lastRequestContext: oldLock.context.requestContext,
            updatedAtMs: 1_234_567_890_000,
        )
        let newSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "new"),
                AiChatMessage(role: .assistant, content: "new done"),
            ],
            lastRequestID: newLock.requestID,
            lastRunID: newLock.runID,
            lastRequestContext: newLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
        let oldOwner = oldLock.recordingFinalSnapshot(oldSnapshot)
        let newOwner = newLock.recordingFinalSnapshot(newSnapshot)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(oldOwner, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[newLock.requestID] = .completed(newOwner)

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_891))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChatSnapshotPersisted(newSnapshot))
        await store.finish()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[sessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldOwner, .unknown),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[sessionID]?.aiChat.backgroundExecutionPhases[newLock.requestID])
        XCTAssertNotNil(store.state.backgroundAiChatStates[sessionID])
    }

    func testBackgroundPersistedSnapshotRemovesOwnerFromAllContentAliases() async {
        let fixture = makeAliasedAiChatOwnerFixture()
        var state = FileManagerFeature.State()
        state.backgroundAiChatStates = [
            fixture.sessionID: fixture.backgroundContent,
            fixture.aliasSessionID: fixture.backgroundContent,
        ]
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChatSnapshotPersisted(fixture.snapshot))

        XCTAssertEqual(store.state.backgroundAiChatStates.count, 2)
        for backgroundContent in store.state.backgroundAiChatStates.values {
            XCTAssertEqual(backgroundContent.aiChat.executionPhase, .idle)
            XCTAssertNotNil(backgroundContent.aiChat.backgroundExecutionPhases[fixture.aliasRequestID])
        }

        await store.send(.backgroundAiChatSnapshotPersisted(fixture.aliasSnapshot))

        XCTAssertTrue(store.state.backgroundAiChatStates.isEmpty)
        await store.finish()
    }

    func testBackgroundPersistedSnapshotRemovesOwnerFromAllInspectorAliases() async {
        let fixture = makeAliasedAiChatOwnerFixture()
        var inspectorState = FileManagerInspectorFeature.State()
        inspectorState.aiChat = fixture.backgroundContent.aiChat
        var state = FileManagerFeature.State()
        state.backgroundInspectorAiChatStates = [
            fixture.sessionID: inspectorState,
            fixture.aliasSessionID: inspectorState,
        ]
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundInspectorSnapshotPersisted(fixture.snapshot))

        XCTAssertEqual(store.state.backgroundInspectorAiChatStates.count, 2)
        for backgroundInspector in store.state.backgroundInspectorAiChatStates.values {
            XCTAssertEqual(backgroundInspector.aiChat.executionPhase, .idle)
            XCTAssertNotNil(backgroundInspector.aiChat.backgroundExecutionPhases[fixture.aliasRequestID])
        }

        await store.send(.backgroundInspectorSnapshotPersisted(fixture.aliasSnapshot))

        XCTAssertTrue(store.state.backgroundInspectorAiChatStates.isEmpty)
        await store.finish()
    }

    func testAddBackgroundAiChatStatePreservesExistingPendingResolver() throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let oldModel = try XCTUnwrap(oldLock.context.selectedModel)
        let newModel = try XCTUnwrap(newLock.context.selectedModel)
        let oldResolutionID = UUID()
        let newResolutionID = UUID()

        func pendingRequest(
            resolutionID: UUID,
            lock: AiChatRequestLock,
            selectedModel: AiProviderModel,
        ) -> AiChatPendingRequestStart {
            AiChatPendingRequestStart(
                resolutionID: resolutionID,
                kind: .submit,
                sessionID: aiSessionID,
                selectedModel: selectedModel,
                selectedRow: lock.selectedModelRow,
                preparedRequest: AiChatPreparedRequest(
                    prompt: "test",
                    messages: lock.request.messages,
                    assistantReplacementIndex: nil,
                    historyTruncation: AiChatHistoryTruncationMetadata(
                        includedMessageCount: lock.request.messages.count,
                        excludedMessageCount: 0,
                        budget: 24000,
                        truncationReason: nil,
                    ),
                ),
            )
        }

        var existingContent = FileManagerContentFeature.State()
        existingContent.aiChat.sessionID = aiSessionID
        existingContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: oldResolutionID,
            lock: oldLock,
            selectedModel: oldModel,
        )

        var newContent = FileManagerContentFeature.State()
        newContent.aiChat.sessionID = aiSessionID
        newContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: newResolutionID,
            lock: newLock,
            selectedModel: newModel,
        )

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = existingContent
        state.addBackgroundAiChatState(sessionID: aiSessionID, state: newContent)

        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            newResolutionID,
        )
        XCTAssertEqual(
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundPendingRequestStarts[oldResolutionID]?
                .resolutionID,
            oldResolutionID,
        )
    }

    func testBackgroundPendingResolverStartsRequestWhenNewPendingExistsForSameSession() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let oldModel = try XCTUnwrap(oldLock.context.selectedModel)
        let newModel = try XCTUnwrap(newLock.context.selectedModel)
        let oldResolutionID = UUID()
        let newResolutionID = UUID()

        func pendingRequest(
            resolutionID: UUID,
            lock: AiChatRequestLock,
            selectedModel: AiProviderModel,
        ) -> AiChatPendingRequestStart {
            AiChatPendingRequestStart(
                resolutionID: resolutionID,
                kind: .submit,
                sessionID: aiSessionID,
                selectedModel: selectedModel,
                selectedRow: lock.selectedModelRow,
                preparedRequest: AiChatPreparedRequest(
                    prompt: "test",
                    messages: lock.request.messages,
                    assistantReplacementIndex: nil,
                    historyTruncation: AiChatHistoryTruncationMetadata(
                        includedMessageCount: lock.request.messages.count,
                        excludedMessageCount: 0,
                        budget: 24000,
                        truncationReason: nil,
                    ),
                ),
            )
        }

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.modelListState = .loaded([oldModel, newModel])
        backgroundContent.aiChat.selectedModelHandle = newModel.id
        backgroundContent.aiChat.pendingRequestStart = pendingRequest(
            resolutionID: newResolutionID,
            lock: newLock,
            selectedModel: newModel,
        )
        backgroundContent.aiChat.backgroundPendingRequestStarts[oldResolutionID] = pendingRequest(
            resolutionID: oldResolutionID,
            lock: oldLock,
            selectedModel: oldModel,
        )

        var state = FileManagerFeature.State()
        state.content = FileManagerContentFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.sendTabContent(.aiChat(.requestContextResolved(oldResolutionID, resolvedContext))) { state in
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background pending resolver should start the matching request")
            }
            XCTAssertNil(state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
            XCTAssertEqual(
                state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundPendingRequestStarts[newResolutionID]?
                    .resolutionID,
                newResolutionID,
            )
            XCTAssertNil(state.backgroundAiChatStates[aiSessionID]?.aiChat
                .backgroundPendingRequestStarts[oldResolutionID])
        }

        await store.skipReceivedActions()
        await store.finish()
    }

    func testAiChatTabSwitchStoresPendingRequestUnderPendingSessionID() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = visibleSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.pendingRequestStart = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: visibleSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: FileManagerContentFeature.State()]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[pendingSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            resolutionID,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[visibleSessionID]?.aiChat.pendingRequestStart)
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: active content authority는 forwarding effect보다 먼저 갱신된다.
    /// Parent reducer가 full forwarding effect를 실행하지 않아도 late completion을 안전하게 거부하는지 검증한다.
    /// - 검증 내용: canonical content와 active-tab snapshot의 동기 authority 및 lock 미생성
    /// - 사전 조건: active AI Chat content에 stale listing marker와 OpenAI pending request가 있음
    /// - 기대 결과: provider 제거 직후 두 snapshot이 갱신되고 late completion은 request를 시작하지 않음
    func testActiveContentRejectsLateCompletionBeforeProviderForwardingEffectRuns() throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let fixture = try makePendingProviderAuthorityFixture()
        var state = makePendingAiChatTabState(
            aiChatTabID: aiChatTabID,
            homeTabID: homeTabID,
            fixture: fixture,
        )
        state.syncActiveTabContentState()

        let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
        withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
        } operation: {
            _ = FileManagerFeature().reduce(into: &state, action: .aiConnectionsFileUpdated(.empty()))

            XCTAssertEqual(state.content.aiChat.providerConnectionSnapshot, .known([]))
            XCTAssertEqual(state.tabContentStates[aiChatTabID]?.aiChat.providerConnectionSnapshot, .known([]))

            _ = FileManagerFeature().reduce(
                into: &state,
                action: .tabContent(
                    tabID: aiChatTabID,
                    action: .aiChat(.requestContextResolved(fixture.resolutionID, resolvedContext)),
                ),
            )
        }

        XCTAssertNil(state.content.aiChat.executionPhase.lock)
        XCTAssertNil(state.tabContentStates[aiChatTabID]?.aiChat.executionPhase.lock)
    }

    /// CTM-005-ai_chat_provider_forwarding: active Inspector authority는 visibility와 무관하게 동기 갱신된다.
    /// Visible forwarding effect를 실행하지 않은 경우와 hidden forwarding이 없는 경우를 함께 검증한다.
    /// - 검증 내용: visible/hidden canonical Inspector와 active-tab snapshot의 authority 및 lock 미생성
    /// - 사전 조건: active directory Inspector에 stale listing failure와 OpenAI pending request가 있음
    /// - 기대 결과: 두 visibility 조건 모두 provider 제거 직후 late completion을 거부함
    func testActiveInspectorRejectsLateCompletionBeforeOrWithoutProviderForwarding() throws {
        for inspectorVisible in [true, false] {
            let tabID = ContentTabID()
            let fixture = try makePendingProviderAuthorityFixture()
            var state = makePendingCanonicalInspectorState(
                tabID: tabID,
                fixture: fixture,
                inspectorVisible: inspectorVisible,
            )

            let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
            withDependencies {
                $0.uuid = .incrementing
                $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
                $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
            } operation: {
                _ = FileManagerFeature().reduce(into: &state, action: .aiConnectionsFileUpdated(.empty()))

                XCTAssertEqual(state.inspector.aiChat.providerConnectionSnapshot, .known([]))
                XCTAssertEqual(state.tabInspectorStates[tabID]?.aiChat.providerConnectionSnapshot, .known([]))

                _ = FileManagerFeature().reduce(
                    into: &state,
                    action: .inspector(.aiChat(.requestContextResolved(fixture.resolutionID, resolvedContext))),
                )
            }

            XCTAssertNil(state.inspector.aiChat.executionPhase.lock)
        }
    }

    /// CTM-005-ai_chat_provider_forwarding: inactive pending owner는 최신 provider authority를 사용한다.
    /// 탭 전환 뒤 provider가 제거된 경우 late context completion이 stale request를 시작하지 않는지 검증한다.
    /// - 검증 내용: inactive tab 및 background owner의 pending completion이 request lock을 생성하지 않음
    /// - 사전 조건: Tab A에 OpenAI pending request가 있고 Tab B로 전환한 뒤 OpenAI 연결이 제거됨
    /// - 기대 결과: late completion 후 foreground/background processing lock이 모두 존재하지 않음
    func testInactivePendingAiChatRejectsLateCompletionAfterProviderRemoval() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let fixture = try makePendingProviderAuthorityFixture()
        let state = makePendingAiChatTabState(
            aiChatTabID: aiChatTabID,
            homeTabID: homeTabID,
            fixture: fixture,
        )

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
        }
        // Window 통합 reducer의 탭 전환 및 warm-up 후속 action은 이 authority 시나리오의 검증 대상이 아니다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()
        XCTAssertEqual(
            store.state.backgroundAiChatStates[fixture.sessionID]?.aiChat.pendingRequestStart?.resolutionID,
            fixture.resolutionID,
        )

        await store.send(.aiConnectionsFileUpdated(.empty()))
        let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
        await store.send(.tabContent(
            tabID: aiChatTabID,
            action: .aiChat(.requestContextResolved(fixture.resolutionID, resolvedContext)),
        ))

        XCTAssertNil(store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase.lock)
        XCTAssertNil(store.state.backgroundAiChatStates[fixture.sessionID]?.aiChat.executionPhase.lock)
        XCTAssertNil(store.state.backgroundAiChatStates[fixture.sessionID])
        await store.finish()
    }

    /// CTM-005-ai_chat_provider_forwarding: inactive/background Inspector도 최신 provider authority를 사용한다.
    /// Inspector 전용 routing 경로의 late completion이 제거된 provider로 request를 시작하지 않는지 검증한다.
    /// - 검증 내용: inactive Inspector와 background Inspector completion의 request lock 미생성
    /// - 사전 조건: 두 Inspector owner에 OpenAI pending request가 있고 completion 전에 연결이 제거됨
    /// - 기대 결과: 두 owner 모두 processing lock 없이 pending lifecycle을 종료함
    func testPendingInspectorOwnersRejectLateCompletionAfterProviderRemoval() async throws {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inactiveFixture = try makePendingProviderAuthorityFixture()
        let backgroundFixture = try makePendingProviderAuthorityFixture()
        var state = makeInspectorProviderAuthorityState(
            homeTabID: homeTabID,
            directoryTabID: directoryTabID,
            inactiveFixture: inactiveFixture,
            backgroundFixture: backgroundFixture,
        )
        state.inspector.inspectorVisible = false

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in AsyncStream { $0.finish() } }
        }
        // Window warm-up effect는 Inspector pending authority 계약의 검증 대상이 아니다.
        store.exhaustivity = .off

        await store.send(.aiConnectionsFileUpdated(.empty()))
        let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
        await store.send(.inspector(.aiChat(.requestContextResolved(inactiveFixture.resolutionID, resolvedContext))))
        await store.send(.inspector(.aiChat(.requestContextResolved(backgroundFixture.resolutionID, resolvedContext))))

        XCTAssertNil(store.state.tabInspectorStates[directoryTabID]?.aiChat.executionPhase.lock)
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[backgroundFixture.sessionID]?.aiChat.executionPhase
            .lock)
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[backgroundFixture.sessionID])
        await store.finish()
    }

    func testAiChatTabSwitchPreservesBackgroundPendingRequestOwner() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = visibleSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: visibleSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: FileManagerContentFeature.State()]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.setCurrent(homeTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[pendingSessionID]?.aiChat
                .backgroundPendingRequestStarts[resolutionID]?.resolutionID,
            resolutionID,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[visibleSessionID]?.aiChat
            .backgroundPendingRequestStarts[resolutionID])
        await store.finish()
    }

    func testDeleteSessionRemovesBackgroundPendingRequestOwnerFromOtherBackgroundState() async throws {
        let deletedSessionID = AiChatSessionID(rawValue: UUID())
        let preservedSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: deletedSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: deletedSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = preservedSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[preservedSessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.deleteSessionTapped(deletedSessionID)))
        await store.skipReceivedActions()

        XCTAssertNil(store.state.backgroundAiChatStates[preservedSessionID])
        XCTAssertNil(store.state.backgroundAiChatStates[deletedSessionID])
        await store.finish()
    }

    func testBackgroundSnapshotRefreshAppliesNilCustomTitle() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID).recordingTerminal(
            at: 1_234_567_890_000,
            failure: nil,
            wasCancelled: false,
        )
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: requestLock.context.provider,
            model: requestLock.context.model,
            selectedModelRow: requestLock.selectedModelRow,
            transcriptHistory: requestLock.request.messages + [AiChatMessage(role: .assistant, content: "done")],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_890_000,
        )
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.currentSessionCustomTitle = "Old title"
        backgroundContent.aiChat.executionPhase = .completed(requestLock.recordingFinalSnapshot(finalSnapshot))

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(sessionID.rawValue.uuidString)
        activeContent.aiChat.sessionID = sessionID
        activeContent.aiChat.currentSessionCustomTitle = "Old title"
        activeContent.aiChat.transcriptHistory = requestLock.request.messages

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[sessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: finalSnapshot),
            snapshot: finalSnapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        )))

        XCTAssertNil(store.state.content.aiChat.currentSessionCustomTitle)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testClosedPendingAiChatContextResolutionStartsBackgroundRequest() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.pendingRequestStart = pendingRequest
        aiChatContent.aiChat.modelListState = .loaded([selectedModel])
        aiChatContent.aiChat.selectedModelHandle = selectedModel.id

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart?.resolutionID,
            resolutionID,
        )

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.sendTabContent(.aiChat(.requestContextResolved(resolutionID, resolvedContext))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertNil(store.state.content.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testBackgroundResolverClearsMatchingPendingCopyFromInactiveTab() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat.sessionID = aiSessionID
        inactiveContent.aiChat.sessionStatus = .active
        inactiveContent.aiChat.pendingRequestStart = pendingRequest
        inactiveContent.aiChat.modelListState = .loaded([selectedModel])
        inactiveContent.aiChat.selectedModelHandle = selectedModel.id

        let backgroundContent = inactiveContent

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = FileManagerContentFeature.State()
        state.tabContentStates[aiChatTabID] = inactiveContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.sendTabContent(.aiChat(.requestContextResolved(resolutionID, resolvedContext))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.pendingRequestStart = nil
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.tabContentStates[aiChatTabID]?.aiChat.pendingRequestStart)
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testInactiveInspectorFindsBackgroundPendingResolver() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat.sessionID = aiSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest
        inactiveInspector.aiChat.modelListState = .loaded([selectedModel])
        inactiveInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[aiChatTabID] = inactiveInspector
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.tabInspectorStates[aiChatTabID]?.aiChat.backgroundPendingRequestStarts
                .removeValue(forKey: resolutionID)
            if case .processing = state.tabInspectorStates[aiChatTabID]?.aiChat.executionPhase {
            } else {
                XCTFail("inactive inspector AI Chat should start processing after parked resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.tabInspectorStates[aiChatTabID]?.aiChat.backgroundPendingRequestStarts[resolutionID])
        XCTAssertNotNil(store.state.tabInspectorStates[aiChatTabID])
        await store.finish()
    }

    func testBackgroundPendingResolverStaysParkedWhenAliasStateSessionDiffers() async throws {
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let pendingSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: pendingSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: pendingSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aliasSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundPendingRequestStarts[resolutionID] = pendingRequest
        backgroundContent.aiChat.modelListState = .loaded([selectedModel])
        backgroundContent.aiChat.selectedModelHandle = selectedModel.id
        backgroundContent.aiChat.providerConnectionSnapshot = .known([.openai])

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aliasSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(currentContext: .init(), addedAttachments: [], parts: [])
        await store.sendTabContent(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))
        await store.skipReceivedActions()

        let aiChat = try XCTUnwrap(store.state.backgroundAiChatStates[aliasSessionID]?.aiChat)
        XCTAssertNil(aiChat.pendingRequestStart)
        XCTAssertNil(aiChat.backgroundPendingRequestStarts[resolutionID])
        XCTAssertEqual(aiChat.backgroundExecutionPhases.count, 1)
        guard case let .processing(lock) = aiChat.backgroundExecutionPhases.values.first else {
            XCTFail("parked resolver should start as background processing owner")
            return
        }
        XCTAssertEqual(lock.context.sessionID, pendingSessionID)
    }

    func testBackgroundPendingResolverUsesPendingSessionIDWhenAliasKeyExists() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let aliasLock = makeRequestLock(sessionID: aliasSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: aiSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.pendingRequestStart = pendingRequest
        backgroundContent.aiChat.backgroundExecutionPhases[aliasLock.requestID] = .completed(aliasLock)
        backgroundContent.aiChat.modelListState = .loaded([selectedModel])
        backgroundContent.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundAiChatStates[aliasSessionID] = backgroundContent

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.sendTabContent(.aiChat(.requestContextResolved(resolutionID, resolvedContext))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background AI Chat should route resolver completion to the pending session key")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.pendingRequestStart)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aliasSessionID]?.aiChat.pendingRequestStart?.sessionID,
            aiSessionID,
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aliasSessionID]?.aiChat.backgroundExecutionPhases[aliasLock.requestID],
            .completed(aliasLock),
        )
        await store.finish()
    }

    func testCompletedAiChatClosePreservesFinalPersistenceOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID).recordingFinalSnapshot(finalSnapshot)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .completed(requestLock)
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
            AiChatMessage(role: .assistant, content: "done"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase, .completed(requestLock))

        await store.sendTabContent(.aiChat(.persistenceFailed(requestLock, .unknown))) { state in
            state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase = .persistenceRecovery(
                requestLock,
                .unknown,
            )
            state.backgroundAiChatStates[aiSessionID]?.aiChat.lastExecutionFailure = .unknown
        }

        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        await store.finish()
    }

    /// CTM-005-independent_content_tab_session: move participant 상태에서도 background AI Chat final save를 반영
    /// Content Tab 이동과 무관한 reducer-owned completion이 lifecycle 정리를 완료하는지 검증한다.
    /// - 검증 내용: final snapshot 전파와 background owner 제거
    /// - 사전 조건: window가 Content Tab move participant이고 동일 session의 background owner가 존재
    /// - 기대 결과: participant guard가 completion을 차단하지 않고 active/cache 상태를 갱신
    func testBackgroundAiChatFinalSaveDuringMoveParticipationRefreshesActiveSession() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .completed(requestLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.contentTabMoveParticipantRequestID = UUID()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.content.aiChat.executionPhase = .completed(requestLock)
            state.content.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testBackgroundRequestStartSnapshotUpdatedRefreshesActiveSessionRow() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: requestLock.request.messages,
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = []

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .processing(requestLock)
        backgroundContent.aiChat.transcriptHistory = requestLock.request.messages
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotUpdated(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = requestLock.request.messages
            state.content.aiChat.executionPhase = .processing(requestLock)
            state.content.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
        }

        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first?.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, requestLock.request.messages)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        await store.finish()
    }

    func testBackgroundFinalSnapshotRefreshesInactiveProcessingCopyWithMatchingOwner() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalLock = requestLock.recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        ))
        let snapshot = try XCTUnwrap(finalLock.finalSnapshot)
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = []
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(finalLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .completed(finalLock)
            state.tabContentStates[aiChatTabID]?.aiChat.sessionList.replaceRow(summary)
            state.tabContentStates[aiChatTabID]?.aiChat.sessionList.selectedSessionID = aiSessionID
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(finalLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testActiveFailureDoesNotRefreshContentFromItself() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .processing(requestLock)
        activeContent.aiChat.transcriptHistory = requestLock.request.messages
        activeContent.aiChat.streamingAssistantDraft = "partial answer"

        var state = FileManagerFeature.State()
        state.content = activeContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.executionEvent(.failed(
            context: requestLock.context,
            reason: .network,
        ))))

        let expectedFailedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .failed(expectedFailedLock, .network))
        XCTAssertEqual(store.state.content.aiChat.streamingAssistantDraft, "partial answer")
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, requestLock.request.messages)
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, .network)
        await store.finish()
    }

    func testBackgroundFailureRefreshesInactiveProcessingCopyWithMatchingOwner() async {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = []
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .failed(requestLock, .unknown)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceFailed(requestLock, .unknown))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = requestLock.persistenceTranscriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContext = requestLock.context.requestContext
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContextModelHandle = requestLock.context.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedModelHandle = requestLock.context.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedThinking = requestLock.context.selectedThinking
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptAutoScrollVersion = 1
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
            state.tabContentStates[aiChatTabID]?.aiChat.lastExecutionFailure = .unknown
            state.backgroundAiChatStates[aiSessionID]?.aiChat
                .backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
                    requestLock,
                    .unknown,
                )
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory,
            requestLock.persistenceTranscriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .persistenceRecovery(requestLock, .unknown),
        )
        await store.finish()
    }

    func testBackgroundRecoveryRefreshesInactiveProcessingCopyWithMatchingOwner() async throws {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalLock = requestLock.recordingFinalSnapshot(AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        ))
        let finalSnapshot = try XCTUnwrap(finalLock.finalSnapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home

        var inactiveAiChatContent = FileManagerContentFeature.State()
        inactiveAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        inactiveAiChatContent.aiChat.mode = .chat
        inactiveAiChatContent.aiChat.sessionID = aiSessionID
        inactiveAiChatContent.aiChat.sessionStatus = .active
        inactiveAiChatContent.aiChat.transcriptHistory = requestLock.request.messages
        inactiveAiChatContent.aiChat.executionPhase = .processing(requestLock)

        var backgroundContent = inactiveAiChatContent
        backgroundContent.aiChat.executionPhase = .idle
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            finalLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: inactiveAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(finalLock))) { state in
            state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory = finalSnapshot.transcriptHistory
            state.tabContentStates[aiChatTabID]?.aiChat.executionPhase = .completed(finalLock)
            state.tabContentStates[aiChatTabID]?.aiChat.lastExecutionFailure = nil
            state.tabContentStates[aiChatTabID]?.aiChat.currentSessionCustomTitle = finalSnapshot.customTitle
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContext = finalSnapshot.lastRequestContext
            state.tabContentStates[aiChatTabID]?.aiChat.lastRequestContextModelHandle = finalSnapshot.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedModelHandle = finalSnapshot.model
            state.tabContentStates[aiChatTabID]?.aiChat.selectedThinking = finalSnapshot.selectedThinking
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(finalLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testBackgroundSnapshotRefreshDoesNotCopyUnrelatedExecutionPhase() async {
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let unrelatedLock = makeRequestLock(sessionID: otherSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        activeContent.aiChat.mode = .chat
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = activeContent
        backgroundContent.aiChat.executionPhase = .processing(unrelatedLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [aiChatTabID: activeContent]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            state.content.aiChat.transcriptHistory = snapshot.transcriptHistory
            state.content.aiChat.sessionList.replaceRow(summary)
            state.content.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = state.content
            state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = nil
        }

        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .idle)
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(unrelatedLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[requestLock.requestID])
        await store.finish()
    }

    func testBackgroundAiChatFollowUpKeepsMismatchedRequestOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let oldLock = makeRequestLock(sessionID: aiSessionID)
        let newLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "old"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let oldRecoveryLock = oldLock.recordingFinalSnapshot(finalSnapshot)
        let newSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "new"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: newLock.requestID,
            lastRunID: newLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let newSummary = AiChatSessionSummary(snapshot: newSnapshot)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(oldRecoveryLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = aiSessionID
        state.content.aiChat.sessionStatus = .active
        state.content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "active")]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            newSummary,
            snapshot: newSnapshot,
            requestID: newLock.requestID,
            runID: newLock.runID,
        )))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["active"])

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(newLock)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )

        await store.finish()

        var mixedBackgroundContent = FileManagerContentFeature.State()
        mixedBackgroundContent.aiChat.sessionID = aiSessionID
        mixedBackgroundContent.aiChat.executionPhase = .persistenceRecovery(oldRecoveryLock, .unknown)
        mixedBackgroundContent.aiChat.backgroundExecutionPhases[newLock.requestID] = .completed(newLock)

        var mixedState = FileManagerFeature.State()
        mixedState.backgroundAiChatStates[aiSessionID] = mixedBackgroundContent

        let mixedStore = TestStore(initialState: mixedState) {
            FileManagerFeature()
        }
        mixedStore.exhaustivity = .off

        await mixedStore.send(.backgroundAiChat(.persistenceRecoverySucceeded(newLock)))

        XCTAssertEqual(
            mixedStore.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(oldRecoveryLock, .unknown),
        )
        XCTAssertNil(mixedStore.state.backgroundAiChatStates[aiSessionID]?.aiChat
            .backgroundExecutionPhases[newLock.requestID])
        XCTAssertNotNil(mixedStore.state.backgroundAiChatStates[aiSessionID])
        await mixedStore.finish()
    }

    func testBackgroundAiChatDeleteSessionRemovesClosedOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = otherSessionID
        state.content.aiChat.mode = .sessions
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.deleteSessionTapped(aiSessionID))) { state in
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }
        await store.finish()

        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
    }

    func testBackgroundAiChatFinalSaveRefreshesInactiveSameSessionTabSnapshot() async {
        let homeTabID = ContentTabID()
        let aiChatTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var staleAiChatContent = FileManagerContentFeature.State()
        staleAiChatContent.navigation.navigationState = .aiChat(aiSessionID.rawValue.uuidString)
        staleAiChatContent.aiChat.mode = .chat
        staleAiChatContent.aiChat.sessionID = aiSessionID
        staleAiChatContent.aiChat.sessionStatus = .active
        staleAiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundContent = staleAiChatContent
        backgroundContent.aiChat.executionPhase = .completed(requestLock)
        backgroundContent.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            aiChatTabID: staleAiChatContent,
        ]
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            var refreshedAiChatContent = staleAiChatContent
            refreshedAiChatContent.aiChat.transcriptHistory = snapshot.transcriptHistory
            refreshedAiChatContent.aiChat.transcriptAutoScrollVersion += 1
            refreshedAiChatContent.aiChat.executionPhase = .completed(requestLock)
            refreshedAiChatContent.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            refreshedAiChatContent.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            refreshedAiChatContent.aiChat.sessionList.replaceRow(summary)
            refreshedAiChatContent.aiChat.sessionList.selectedSessionID = aiSessionID
            state.tabContentStates[aiChatTabID] = refreshedAiChatContent
            state.backgroundAiChatStates.removeValue(forKey: aiSessionID)
        }

        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabContentStates[aiChatTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        await store.finish()
    }

    func testBackgroundInspectorPendingContextResolutionStartsRequest() async throws {
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = inspectorSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.pendingRequestStart = pendingRequest
        backgroundInspector.aiChat.modelListState = .loaded([selectedModel])
        backgroundInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background Inspector AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNotNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertNil(store.state.inspector.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testBackgroundInspectorPendingResolverUsesPendingSessionIDWhenAliasKeyExists() async throws {
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let aliasLock = makeRequestLock(sessionID: aliasSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = inspectorSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.pendingRequestStart = pendingRequest
        backgroundInspector.aiChat.backgroundExecutionPhases[aliasLock.requestID] = .completed(aliasLock)
        backgroundInspector.aiChat.modelListState = .loaded([selectedModel])
        backgroundInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[aliasSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase {
            } else {
                XCTFail("background Inspector AI Chat should route resolver completion to the pending session key")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.pendingRequestStart)
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aliasSessionID]?.aiChat.pendingRequestStart?.sessionID,
            inspectorSessionID,
        )
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aliasSessionID]?.aiChat
                .backgroundExecutionPhases[aliasLock.requestID],
            .completed(aliasLock),
        )
        await store.finish()
    }

    func testInactiveInspectorPendingContextResolutionStartsRequest() async throws {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: inspectorSessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.pendingRequestStart = pendingRequest
        inactiveInspector.aiChat.modelListState = .loaded([selectedModel])
        inactiveInspector.aiChat.selectedModelHandle = selectedModel.id

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatExecutionClient.execute = { _, _ in
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        let resolvedContext = AiChatResolvedRequestContext(
            currentContext: .init(),
            addedAttachments: [],
            parts: [],
        )
        await store.send(.inspector(.aiChat(.requestContextResolved(resolutionID, resolvedContext)))) { state in
            state.tabInspectorStates[directoryTabID]?.aiChat.pendingRequestStart = nil
            if case .processing = state.tabInspectorStates[directoryTabID]?.aiChat.executionPhase {
            } else {
                XCTFail("inactive Inspector AI Chat should start processing after resolver completion")
            }
        }

        await store.skipReceivedActions()
        XCTAssertNil(store.state.inspector.aiChat.pendingRequestStart)
        await store.finish()
    }

    func testClosingInspectorTabPreservesBackgroundExecutionPhases() async {
        let directoryTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryTabID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryTabID: directoryContent,
            homeTabID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = nil
        state.inspector.aiChat.executionPhase = .idle
        state.inspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)
        state.syncActiveTabInspectorState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()

        let backgroundInspector = store.state.backgroundInspectorAiChatStates[inspectorSessionID]
        XCTAssertNotNil(backgroundInspector)
        XCTAssertEqual(
            backgroundInspector?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .processing(requestLock),
        )
        XCTAssertNil(backgroundInspector?.aiChat.sessionID)
        await store.finish()
    }

    func testClosedInspectorTabFinalEventSavesSnapshotThroughBackgroundState() async {
        let directoryTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: directoryTabID,
            recentlyClosed: nil,
        )
        state.content = directoryContent
        state.tabContentStates = [
            directoryTabID: directoryContent,
            homeTabID: homeContent,
        ]
        state.inspector.inspectorVisible = true
        state.inspector.activeMode = .chat
        state.inspector.aiChat.sessionID = inspectorSessionID
        state.inspector.aiChat.sessionStatus = .active
        state.inspector.aiChat.executionPhase = .processing(requestLock)
        state.inspector.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        state.inspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]
        state.syncActiveTabInspectorState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(directoryTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()

        XCTAssertNotNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.inspector(.aiChat(.executionEvent(.final(response: response)))))

        await store.receive { action in
            guard case let .backgroundInspectorSnapshotPersisted(snapshot) = action else { return false }
            let summary = AiChatSessionSummary(snapshot: snapshot)
            return summary.sessionID == inspectorSessionID
        } assert: { state in
            state.backgroundInspectorAiChatStates.removeValue(forKey: inspectorSessionID)
        }

        await store.finish()

        let snapshots = savedSnapshots.value
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sessionID, inspectorSessionID)
        XCTAssertEqual(snapshots.first?.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
    }

    func testInactiveInspectorFinalSaveRefreshesTabInspectorSnapshot() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.executionPhase = .processing(requestLock)
        inactiveInspector.aiChat.lockedModelHandle = requestLock.selectedModelHandle
        inactiveInspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            directoryTabID: directoryContent,
        ]
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        store.exhaustivity = .off

        let response = AiChatResponse(
            context: requestLock.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "done"),
            completedAtMs: 1_234_567_891_000,
        )

        await store.send(.inspector(.aiChat(.executionEvent(.final(response: response)))))

        let savedSnapshot = savedSnapshots.value.first
        XCTAssertEqual(savedSnapshot?.sessionID, inspectorSessionID)
        XCTAssertEqual(savedSnapshot?.transcriptHistory.map(\.content), ["test", "done"])

        await store.receive { action in
            guard case let .backgroundInspectorAiChat(.sessionSnapshotSaved(summary, snapshot, requestID, runID)) =
                action
            else {
                return false
            }
            return summary.sessionID == inspectorSessionID
                && snapshot?.sessionID == inspectorSessionID
                && requestID == requestLock.requestID
                && runID == requestLock.runID
        }

        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundInspectorFinalSaveRefreshesInactiveSameSessionInspectorSnapshot() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: inspectorSessionID,
            status: .active,
            provider: .openai,
            model: requestLock.selectedModelHandle,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath("/Users/test/Documents")

        var staleInspector = FileManagerInspectorFeature.State()
        staleInspector.inspectorVisible = true
        staleInspector.activeMode = .chat
        staleInspector.aiChat.sessionID = inspectorSessionID
        staleInspector.aiChat.sessionStatus = .active
        staleInspector.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        var backgroundInspector = staleInspector
        backgroundInspector.aiChat.executionPhase = .completed(requestLock)
        backgroundInspector.aiChat.transcriptHistory = snapshot.transcriptHistory
        backgroundInspector.aiChat.selectedModelHandle = requestLock.selectedModelHandle
        backgroundInspector.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [
            homeTabID: homeContent,
            directoryTabID: directoryContent,
        ]
        state.tabInspectorStates[directoryTabID] = staleInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundInspectorAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        ))) { state in
            var refreshedInspector = staleInspector.tabSnapshot()
            refreshedInspector.aiChat.transcriptHistory = snapshot.transcriptHistory
            refreshedInspector.aiChat.transcriptAutoScrollVersion += 1
            refreshedInspector.aiChat.executionPhase = .completed(requestLock)
            refreshedInspector.aiChat.selectedModelHandle = requestLock.selectedModelHandle
            refreshedInspector.aiChat.lastRequestContextModelHandle = requestLock.selectedModelHandle
            refreshedInspector.aiChat.sessionList.replaceRow(summary)
            refreshedInspector.aiChat.sessionList.selectedSessionID = inspectorSessionID
            refreshedInspector.aiChat.sessionList.unreadCompletedSessionIDs.insert(inspectorSessionID)
            state.tabInspectorStates[directoryTabID] = refreshedInspector
            state.backgroundInspectorAiChatStates.removeValue(forKey: inspectorSessionID)
        }

        XCTAssertNil(store.state.inspector.aiChat.sessionID)
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[inspectorSessionID])
        await store.finish()
    }

    func testInactiveInspectorEventBypassesMismatchedBackgroundInspectorOwner() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let staleLock = makeRequestLock(sessionID: inspectorSessionID)
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let failedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.inspectorVisible = true
        inactiveInspector.activeMode = .chat
        inactiveInspector.aiChat.sessionID = inspectorSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var staleBackgroundInspector = FileManagerInspectorFeature.State()
        staleBackgroundInspector.inspectorVisible = true
        staleBackgroundInspector.activeMode = .chat
        staleBackgroundInspector.aiChat.sessionID = inspectorSessionID
        staleBackgroundInspector.aiChat.sessionStatus = .active
        staleBackgroundInspector.aiChat.executionPhase = .completed(staleLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = inactiveInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = staleBackgroundInspector.tabSnapshot()
        state.syncContentTabSidebarItems()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.executionEvent(.failed(
            context: requestLock.context,
            reason: .network,
        ))))) { state in
            state.tabInspectorStates[directoryTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID] = .failed(
                failedLock,
                .network,
            )
        }

        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .failed(failedLock, .network),
        )
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat.executionPhase,
            .completed(staleLock),
        )
        await store.finish()
    }

    func testBackgroundInspectorSnapshotSavedUsesSavedSnapshotPayload() async {
        let homeTabID = ContentTabID()
        let directoryTabID = ContentTabID()
        let inspectorSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: inspectorSessionID)
        let snapshot = AiChatSessionSnapshot(
            sessionID: inspectorSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            updatedAtMs: 1_234_567_891_000,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        var staleInspector = FileManagerInspectorFeature.State()
        staleInspector.inspectorVisible = true
        staleInspector.activeMode = .chat
        staleInspector.aiChat.sessionID = inspectorSessionID
        staleInspector.aiChat.sessionStatus = .active
        staleInspector.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "stale")]

        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.inspectorVisible = true
        backgroundInspector.activeMode = .chat
        backgroundInspector.aiChat.sessionID = visibleSessionID
        backgroundInspector.aiChat.sessionStatus = .active
        backgroundInspector.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "visible")]
        backgroundInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = staleInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[inspectorSessionID] = backgroundInspector.tabSnapshot()

        let store: TestStore<FileManagerFeature.State, FileManagerWindowAction> = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundInspectorAiChat(.sessionSnapshotSaved(
            summary,
            snapshot: snapshot,
            requestID: requestLock.requestID,
            runID: requestLock.runID,
        )))

        XCTAssertEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        XCTAssertNotEqual(
            store.state.tabInspectorStates[directoryTabID]?.aiChat.transcriptHistory.map(\.content),
            ["visible"],
        )
        await store.finish()
    }

    func testCompletedAiChatPageCloseDoesNotCancelFinalPersistence() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID).recordingFinalSnapshot(finalSnapshot)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .completed(requestLock)
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
            AiChatMessage(role: .assistant, content: "done"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()
        await store.finish()

        guard let backgroundContent = store.state.backgroundAiChatStates[aiSessionID] else {
            XCTFail("Expected completed AI Chat state to remain in background")
            return
        }
        XCTAssertEqual(backgroundContent.aiChat.executionPhase, .completed(requestLock))
    }

    func testPersistenceRecoveryAiChatPageClosePreservesFinalSnapshotOwner() async {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        aiChatContent.aiChat.lastExecutionFailure = .unknown
        aiChatContent.aiChat.transcriptHistory = [
            AiChatMessage(role: .user, content: "test"),
        ]

        let homeContent = FileManagerContentFeature.State()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))
        await store.receiveTabContent(\.internal.applyNavigationState)
        await store.skipReceivedActions()
        await store.finish()

        guard let backgroundContent = store.state.backgroundAiChatStates[aiSessionID] else {
            XCTFail("Expected persistence recovery AI Chat state to remain in background")
            return
        }
        XCTAssertEqual(
            backgroundContent.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            backgroundContent.aiChat.executionPhase.lock?.finalSnapshot?.transcriptHistory.map(\.content),
            ["test", "done"],
        )
    }

    func testAiChatDeleteSucceededRefreshesAllOpenCopies() async throws {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let parkedSessionID = AiChatSessionID(rawValue: UUID())
        let parkedRequestLock = makeRequestLock(sessionID: parkedSessionID)
        let parkedResolutionID = UUID()
        let parkedPendingRequest = try AiChatPendingRequestStart(
            resolutionID: parkedResolutionID,
            kind: .submit,
            sessionID: parkedSessionID,
            selectedModel: XCTUnwrap(parkedRequestLock.context.selectedModel),
            selectedRow: parkedRequestLock.context.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "parked",
                messages: [AiChatMessage(role: .user, content: "parked")],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 1,
                    excludedMessageCount: 0,
                    budget: 200_000,
                    truncationReason: nil,
                ),
            ),
        )
        let snapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Delete me",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )
        let summary = AiChatSessionSummary(snapshot: snapshot)

        func aiChatState() -> AiChatFeature.State {
            var aiChat = AiChatFeature.State(
                sessionList: .init(allRows: [summary]),
                sessionID: aiSessionID,
                currentSessionCustomTitle: "Delete me",
                executionPhase: .processing(requestLock),
            )
            aiChat.restoreSessionID = aiSessionID
            aiChat.restoreOutcome = .restored(snapshot: snapshot)
            aiChat.sessionStatus = .active
            aiChat.backgroundPendingRequestStarts[parkedResolutionID] = parkedPendingRequest
            aiChat.backgroundExecutionPhases[parkedRequestLock.requestID] = .processing(parkedRequestLock)
            return aiChat
        }

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat = aiChatState()
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat = aiChatState()
        var activeInspector = FileManagerInspectorFeature.State()
        activeInspector.aiChat = aiChatState()
        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat = aiChatState()
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat = aiChatState()
        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.aiChat = aiChatState()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Active",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "bubble.right",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.tabContentStates[activeTabID] = activeContent
        state.tabContentStates[inactiveTabID] = inactiveContent
        state.content = activeContent
        state.tabInspectorStates[activeTabID] = activeInspector
        state.tabInspectorStates[inactiveTabID] = inactiveInspector
        state.inspector = activeInspector
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundInspectorAiChatStates[aiSessionID] = backgroundInspector.tabSnapshot()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionDeleteSucceeded(aiSessionID))) { state in
            state.content.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabContentStates[activeTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabContentStates[inactiveTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.inspector.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabInspectorStates[activeTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.tabInspectorStates[inactiveTabID]?.aiChat.applyDeletedSessionExpectation(sessionID: aiSessionID)
            state.backgroundAiChatStates[aiSessionID] = nil
            state.backgroundInspectorAiChatStates[aiSessionID] = nil
        }

        XCTAssertTrue(store.state.content.aiChat.sessionList.deletedSessionIDs.contains(aiSessionID))
        XCTAssertFalse(store.state.content.aiChat.sessionList.allRows.contains { $0.sessionID == aiSessionID })
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.deletedSessionIDs
            .contains(aiSessionID), true)
        XCTAssertFalse(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.allRows
            .contains { $0.sessionID == aiSessionID } ?? true)
        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, [])
        XCTAssertEqual(store.state.content.aiChat.draftText, "")
        XCTAssertNil(store.state.content.aiChat.selectedModelHandle)
        XCTAssertNil(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionID)
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.transcriptHistory, [])
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.draftText, "")
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertNil(store.state.backgroundInspectorAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.content.aiChat.backgroundPendingRequestStarts[parkedResolutionID],
            parkedPendingRequest,
        )
        XCTAssertEqual(
            store.state.content.aiChat.backgroundExecutionPhases[parkedRequestLock.requestID],
            .processing(parkedRequestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.backgroundPendingRequestStarts[parkedResolutionID],
            parkedPendingRequest,
        )
    }

    func testAiChatRenameRefreshesAllOpenCopiesCustomTitle() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let staleLock = requestLock.recordingCustomTitle("Stale title")
        let renamedLock = requestLock.recordingCustomTitle("Renamed everywhere")
        let oldSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Stale title",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )
        let renamedSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Renamed everywhere",
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 2,
        )
        let oldSummary = AiChatSessionSummary(snapshot: oldSnapshot)
        let renamedSummary = AiChatSessionSummary(snapshot: renamedSnapshot)

        func aiChatState() -> AiChatFeature.State {
            var aiChat = AiChatFeature.State(
                sessionList: .init(allRows: [oldSummary]),
                sessionID: aiSessionID,
                currentSessionCustomTitle: "Stale title",
                executionPhase: .processing(staleLock),
            )
            aiChat.sessionStatus = .active
            return aiChat
        }

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat = aiChatState()
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat = aiChatState()
        var activeInspector = FileManagerInspectorFeature.State()
        activeInspector.aiChat = aiChatState()
        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat = aiChatState()
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat = aiChatState()
        var backgroundInspector = FileManagerInspectorFeature.State()
        backgroundInspector.aiChat = aiChatState()

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates[inactiveTabID] = inactiveContent
        state.inspector = activeInspector
        state.tabInspectorStates[inactiveTabID] = inactiveInspector
        state.backgroundAiChatStates[aiSessionID] = backgroundContent
        state.backgroundInspectorAiChatStates[aiSessionID] = backgroundInspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionRenameSucceeded(
            renamedSummary,
            customTitle: "Renamed everywhere",
        )))

        XCTAssertEqual(store.state.content.aiChat.currentSessionCustomTitle, "Renamed everywhere")
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.currentSessionCustomTitle,
            "Renamed everywhere",
        )
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(store.state.inspector.aiChat.currentSessionCustomTitle, "Renamed everywhere")
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.tabInspectorStates[inactiveTabID]?.aiChat.currentSessionCustomTitle,
            "Renamed everywhere",
        )
        XCTAssertEqual(store.state.tabInspectorStates[inactiveTabID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase, .processing(renamedLock))
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(renamedLock),
        )
        XCTAssertEqual(store.state.content.aiChat.sessionList.allRows.first, renamedSummary)
        XCTAssertEqual(store.state.tabContentStates[inactiveTabID]?.aiChat.sessionList.allRows.first, renamedSummary)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.title, "Renamed everywhere")
        XCTAssertEqual(store.state.contentTabs.tabs[id: inactiveTabID]?.title, "Renamed everywhere")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.map(\.title), [
            "Renamed everywhere",
            "Renamed everywhere",
        ])
        await store.finish()
    }

    func testLiveSessionListTitleUpdatesActiveAiChatSidebarRow() async {
        let inactiveSessionID = AiChatSessionID(rawValue: UUID())
        let activeSessionID = AiChatSessionID(rawValue: UUID())
        let inactiveTabID = ContentTabID()
        let activeTabID = ContentTabID()
        let activeSummary = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "현재 폴더에 qa-created-folder 폴더를 만들어줘",
            messageCount: 1,
            provider: nil,
            model: nil,
            createdAtMs: 1,
            updatedAtMs: 1,
            status: .active,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: inactiveSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: activeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "bubble.right",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionListLoaded([activeSummary])))

        XCTAssertEqual(store.state.contentTabs.tabs[id: inactiveTabID]?.title, "AI Chat")
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.title, activeSummary.title)
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.map(\.title), [
            "AI Chat",
            activeSummary.title,
        ])
    }

    /// CTM-005-independent_content_tab_session: inactive A AI action은 active B title을 refresh하지 않음
    /// parent AI bridge가 origin snapshot을 읽고 unrelated active content를 wildcard로 refresh하지 않는지 검증한다.
    /// - 검증 내용: A sessionListLoaded 후 A/B tab title과 sidebar projection을 비교한다.
    /// - 사전 조건: A는 inactive, B는 active이며 서로 다른 session summary를 가진다.
    /// - 기대 결과: A title만 A summary로 갱신되고 B title은 기존 값으로 유지된다.
    func testInactiveAiActionDoesNotRefreshActiveTabTitle() async {
        let inactiveSessionID = AiChatSessionID(rawValue: UUID())
        let activeSessionID = AiChatSessionID(rawValue: UUID())
        let inactiveTabID = ContentTabID()
        let activeTabID = ContentTabID()
        let inactiveSummary = AiChatSessionSummary(
            sessionID: inactiveSessionID,
            title: "Inactive A title",
            messageCount: 1,
            provider: nil,
            model: nil,
            createdAtMs: 1,
            updatedAtMs: 1,
            status: .active,
        )
        let activeSummary = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Must not apply to B",
            messageCount: 1,
            provider: nil,
            model: nil,
            createdAtMs: 1,
            updatedAtMs: 1,
            status: .active,
        )
        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat.sessionList = AiChatSessionListState(allRows: [inactiveSummary])
        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionList = AiChatSessionListState(allRows: [activeSummary])
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: inactiveSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: activeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Active B stable",
                    iconName: "bubble.right",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.content = activeContent
        state.tabContentStates = [inactiveTabID: inactiveContent, activeTabID: activeContent]
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.tabContent(
            tabID: inactiveTabID,
            action: .aiChat(.sessionListLoaded([inactiveSummary])),
        )) { state in
            state.updateAiChatTabTitle(sessionID: inactiveSessionID, title: inactiveSummary.title)
        }

        XCTAssertEqual(store.state.contentTabs.tabs[id: inactiveTabID]?.title, inactiveSummary.title)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.title, "Active B stable")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.map(\.title), [
            inactiveSummary.title,
            "Active B stable",
        ])
    }

    func testStaleSessionListDoesNotOverwriteRestoredAiChatTabTitle() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let tabID = ContentTabID()
        let staleSummary = AiChatSessionSummary(
            sessionID: sessionID,
            title: "Old session title",
            messageCount: 1,
            provider: nil,
            model: nil,
            createdAtMs: 1,
            updatedAtMs: 1,
            status: .active,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                isPinned: false,
                title: "Current session title",
                iconName: "bubble.right",
            )],
            activeTabID: tabID,
        )
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionListLoaded([staleSummary])))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "Current session title")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "Current session title")
    }

    func testAiChatTabTitleFallsBackWhenRestoredSessionHasNoTitleCandidate() {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let tabID = ContentTabID()
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            updatedAtMs: 1,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .aiChat,
                anchor: .aiChat(sessionID: sessionID.rawValue.uuidString),
                isPinned: false,
                title: "Previous",
                iconName: "message",
            )],
            activeTabID: tabID,
        )

        let restoredTitle = AiChatSessionSummary.titleCandidate(from: snapshot) ?? ""
        state.updateAiChatTabTitle(sessionID: sessionID, title: restoredTitle)

        XCTAssertNil(AiChatSessionSummary.titleCandidate(from: snapshot))
        XCTAssertEqual(AiChatSessionSummary(snapshot: snapshot).title, "New Chat")
        XCTAssertEqual(state.contentTabs.tabs[id: tabID]?.title, "AI Chat")
        XCTAssertEqual(state.sidebar.contentTabSidebarItems.first?.title, "AI Chat")
    }

    func testBackgroundAiChatRenameRefreshesClosedOwnerCustomTitle() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .completed(requestLock)

        var renamedSnapshot = finalSnapshot
        renamedSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            customTitle: "Renamed while closed",
            provider: finalSnapshot.provider,
            model: finalSnapshot.model,
            selectedModelRow: finalSnapshot.selectedModelRow,
            selectedThinking: finalSnapshot.selectedThinking,
            transcriptHistory: finalSnapshot.transcriptHistory,
            lastRequestID: finalSnapshot.lastRequestID,
            lastRunID: finalSnapshot.lastRunID,
            lastRequestContext: finalSnapshot.lastRequestContext,
            updatedAtMs: finalSnapshot.updatedAtMs,
        )
        let renamedSummary = AiChatSessionSummary(snapshot: renamedSnapshot)
        let expectedLock = requestLock.recordingCustomTitle("Renamed while closed")

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.sessionRenameSucceeded(
            renamedSummary,
            customTitle: "Renamed while closed",
        )))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .completed(expectedLock),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase.lock?.finalSnapshot?.customTitle,
            "Renamed while closed",
        )
        await store.finish()
    }

    func testBackgroundAiChatRecoveryRetryFailedKeepsClosedOwner() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            selectedModelRow: nil,
            selectedThinking: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            lastRequestID: nil,
            lastRunID: nil,
            lastRequestContext: nil,
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        backgroundContent.aiChat.lastExecutionFailure = .unknown

        var state = FileManagerFeature.State()
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoveryRetryFailed(requestLock, .unknown)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase.lock?.finalSnapshot?
                .transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundAiChatPersistenceFailedRefreshesActiveRecovery() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .idle
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .completed(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceFailed(requestLock, .unknown)))

        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .persistenceRecovery(requestLock, .unknown),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .persistenceRecovery(requestLock, .unknown))
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, .unknown)
        await store.finish()
    }

    func testBackgroundAiChatDeleteSessionCancelsOnlyMatchingSessionOwner() async {
        let deletedSessionID = AiChatSessionID(rawValue: UUID())
        let preservedSessionID = AiChatSessionID(rawValue: UUID())
        let deletedLock = makeRequestLock(sessionID: deletedSessionID)
        let preservedLock = makeRequestLock(sessionID: preservedSessionID)

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = deletedSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .persistenceRecovery(deletedLock, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[preservedLock.requestID] = .processing(preservedLock)

        var state = FileManagerFeature.State()
        state.content.aiChat.sessionID = AiChatSessionID(rawValue: UUID())
        state.backgroundAiChatStates[deletedSessionID] = backgroundContent
        state.backgroundAiChatStates[preservedSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.deleteSessionTapped(deletedSessionID))) { state in
            state.backgroundAiChatStates.removeValue(forKey: deletedSessionID)
        }
        XCTAssertEqual(
            store.state.backgroundAiChatStates[preservedSessionID]?.aiChat
                .backgroundExecutionPhases[preservedLock.requestID],
            .processing(preservedLock),
        )
        await store.finish()
    }

    func testInactiveInspectorBackgroundRecoverySucceededRefreshesContentSession() async {
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorVisibleSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var content = FileManagerContentFeature.State()
        content.aiChat.sessionID = aiSessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        content.aiChat.executionPhase = .idle

        var inactiveInspector = FileManagerInspectorFeature.State()
        inactiveInspector.aiChat.sessionID = inspectorVisibleSessionID
        inactiveInspector.aiChat.sessionStatus = .active
        inactiveInspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .directory,
                    anchor: .directory(path: "/tmp/inactive"),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        var staleBackgroundInspector = FileManagerInspectorFeature.State()
        let staleLock = makeRequestLock(sessionID: aiSessionID)
        staleBackgroundInspector.aiChat.sessionID = aiSessionID
        staleBackgroundInspector.aiChat.sessionStatus = .active
        staleBackgroundInspector.aiChat.backgroundExecutionPhases[staleLock.requestID] = .persistenceRecovery(
            staleLock,
            .unknown,
        )

        state.content = content
        state.tabInspectorStates[inactiveTabID] = inactiveInspector.tabSnapshot()
        state.backgroundInspectorAiChatStates[aiSessionID] = staleBackgroundInspector.tabSnapshot()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.persistenceRecoverySucceeded(requestLock))))

        XCTAssertEqual(
            store.state.tabInspectorStates[inactiveTabID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        XCTAssertEqual(
            store.state.backgroundInspectorAiChatStates[aiSessionID]?.aiChat
                .backgroundExecutionPhases[staleLock.requestID],
            .persistenceRecovery(staleLock, .unknown),
        )
        await store.finish()
    }

    func testActiveInspectorBackgroundRecoverySucceededRefreshesContentSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let inspectorVisibleSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var content = FileManagerContentFeature.State()
        content.aiChat.sessionID = aiSessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        content.aiChat.executionPhase = .idle

        var inspector = FileManagerInspectorFeature.State()
        inspector.aiChat.sessionID = inspectorVisibleSessionID
        inspector.aiChat.sessionStatus = .active
        inspector.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.content = content
        state.inspector = inspector

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.inspector(.aiChat(.persistenceRecoverySucceeded(requestLock))))

        XCTAssertEqual(
            store.state.inspector.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testActiveContentBackgroundRecoverySucceededRefreshesInactiveSession() async {
        let activeTabID = ContentTabID()
        let inactiveTabID = ContentTabID()
        let activeSessionID = AiChatSessionID(rawValue: UUID())
        let inactiveSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: inactiveSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: inactiveSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = activeSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var inactiveContent = FileManagerContentFeature.State()
        inactiveContent.aiChat.sessionID = inactiveSessionID
        inactiveContent.aiChat.sessionStatus = .active
        inactiveContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]
        inactiveContent.aiChat.executionPhase = .idle

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: activeSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Active",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: inactiveTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: inactiveSessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "Inactive",
                    iconName: "bubble.right",
                ),
            ],
            activeTabID: activeTabID,
            recentlyClosed: nil,
        )
        state.content = activeContent
        state.tabContentStates = [
            activeTabID: activeContent,
            inactiveTabID: inactiveContent,
        ]

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.persistenceRecoverySucceeded(requestLock)))

        XCTAssertEqual(
            store.state.content.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .completed(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.executionPhase,
            .completed(requestLock),
        )
        XCTAssertEqual(
            store.state.tabContentStates[inactiveTabID]?.aiChat.transcriptHistory.map(\.content),
            ["test", "done"],
        )
        await store.finish()
    }

    func testBackgroundAiChatRecoverySucceededAppliesFinalSnapshotToActiveSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let finalSnapshot = AiChatSessionSnapshot(
            sessionID: aiSessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "done"),
            ],
            updatedAtMs: 1_234_567_890_000,
        )
        let requestLock = makeRequestLock(sessionID: aiSessionID)
            .recordingFinalSnapshot(finalSnapshot)

        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .persistenceRecovery(requestLock, .unknown)
        activeContent.aiChat.lastExecutionFailure = .unknown
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .persistenceRecovery(
            requestLock,
            .unknown,
        )

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.persistenceRecoverySucceeded(requestLock)))

        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(requestLock))
        XCTAssertNil(store.state.content.aiChat.lastExecutionFailure)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory.map(\.content), ["test", "done"])
        await store.finish()
    }

    func testBackgroundAiChatFailureKeepsOwnerAndRefreshesActiveSession() async {
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let otherSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let unrelatedLock = makeRequestLock(sessionID: otherSessionID)
        let unrelatedFailedLock = unrelatedLock.recordingTerminal(
            at: 1_234_567_889_000,
            failure: .unknown,
            wasCancelled: false,
        )
        var activeContent = FileManagerContentFeature.State()
        activeContent.aiChat.sessionID = aiSessionID
        activeContent.aiChat.sessionStatus = .active
        activeContent.aiChat.executionPhase = .idle
        activeContent.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "test")]

        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = aiSessionID
        backgroundContent.aiChat.sessionStatus = .active
        backgroundContent.aiChat.executionPhase = .failed(unrelatedFailedLock, .unknown)
        backgroundContent.aiChat.backgroundExecutionPhases[requestLock.requestID] = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.content = activeContent
        state.backgroundAiChatStates[aiSessionID] = backgroundContent

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.backgroundAiChat(.executionEvent(.failed(context: requestLock.context, reason: .network))))

        let expectedFailedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.backgroundExecutionPhases[requestLock.requestID],
            .failed(expectedFailedLock, .network),
        )
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .failed(unrelatedFailedLock, .unknown),
        )
        XCTAssertEqual(
            store.state.content.aiChat.executionPhase,
            .failed(expectedFailedLock, .network),
        )
        await store.finish()
    }
}

// MARK: - CTM-005-ai_chat_invalid_session

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// 존재하지 않는 AI Chat sessionID로 ContentPane이 초기화될 때 빈 새 session으로 fallback됨
    /// ContentPane AI Chat이 restoreSessionID를 가지고 restore를 시도할 때 persistence에 session이 없으면
    /// .restoreOutcome(.newSession)으로 fallback되어 새 빈 session으로 전환됨을 검증한다.
    /// - 검증 내용: .setup 전송 후 sessionStatus가 .restoring이 되었다가,
    ///   restoreOutcome 수신 후 sessionID가 새 ID로 설정되고 restoreFailure가 설정됨
    /// - 사전 조건: aiChatSessionPersistenceClient.loadSession → nil (session 없음)
    /// - 기대 결과: restoreFailure(.missingRecord)가 설정되고 새 빈 session으로 전환됨
    func testInvalidAiChatSessionFallsBackToNewSession() async {
        let originalSessionID = AiChatSessionID(rawValue: UUID())
        let setup = AiChatSetupState(
            restoreSessionID: originalSessionID,
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: .init(summary: "Test context"),
            transcriptHistory: [],
            draftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            selectedThinking: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "missing-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.setup(setup)))

        // setup에서 restoreSessionID가 있으므로 sessionStatus가 .restoring이 됨
        XCTAssertEqual(store.state.content.aiChat.restoreSessionID, originalSessionID)

        // restoreOutcome이 도착할 때까지 기다림
        await store.receiveTabContent(\.aiChat.restoreOutcome)
        await store.finish()

        // restore failure가 설정되어야 함 (missing record)
        XCTAssertNotNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.restoreFailure, .missingRecord)
        // 새 sessionID가 할당되어야 함 (원래 sessionID와 다름)
        XCTAssertNotEqual(store.state.content.aiChat.sessionID, originalSessionID)
        // mode는 .setup에서 변경되지 않음 — .sessions 유지
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        // sessionStatus는 .idle (applyNewSessionSnapshot에서 .idle로 설정)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .idle)
        // transcript는 빈 배열
        XCTAssertTrue(store.state.content.aiChat.transcriptHistory.isEmpty)
    }

    /// AI Chat setup에 restoreSessionID가 없으면 restore 없이 session이 바로 설정됨
    /// restore 없이 초기화되는 경우(예: 새 AI Chat 탭) .setup 수신 후
    /// sessionID가 설정되고 sessionStatus가 .idle이며 restore 관련 state가 nil임을 검증한다.
    /// mode는 .setup에서 변경되지 않고 기본값 .sessions를 유지한다 (view가 이후 .newChatTapped로 전환).
    /// - 검증 내용: .setup(restoreSessionID: nil) 전송 후 sessionID가 설정되고
    ///   restoreSessionID == nil, sessionStatus == .idle
    /// - 사전 조건: ContentPane AI Chat에 restoreSessionID 없는 setup 전송
    /// - 기대 결과: restore 없이 session이 설정되고 restore 관련 state는 nil
    func testAiChatSetupWithoutRestoreSetsSessionDirectly() async {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let setup = AiChatSetupState(
            restoreSessionID: nil,
            sessionID: sessionID,
            sessionStatus: .idle,
            currentContext: .init(summary: "Test context"),
            transcriptHistory: [],
            draftText: "",
            catalogRows: [],
            selectedModelHandle: nil,
            selectedThinking: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )

        var state = FileManagerFeature.State()
        state.content.aiChat.mode = .sessions
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: ContentTabID(),
                page: .aiChat,
                anchor: .aiChat(sessionID: "test-session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "message",
            )],
            activeTabID: ContentTabID(),
            recentlyClosed: nil,
        )
        state.contentTabs.activeTabID = state.contentTabs.tabs.first?.id
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("restoreSessionID가 nil이므로 restore가 호출되지 않아야 함")
                return nil
            }
        }
        store.exhaustivity = .off

        await store.sendTabContent(.aiChat(.setup(setup)))

        XCTAssertEqual(store.state.content.aiChat.sessionID, sessionID)
        XCTAssertNil(store.state.content.aiChat.restoreSessionID)
        XCTAssertNil(store.state.content.aiChat.restoreOutcome)
        XCTAssertNil(store.state.content.aiChat.restoreFailure)
        XCTAssertEqual(store.state.content.aiChat.sessionStatus, .idle)
        // setup에서 mode는 .chat으로 전환되지 않음 — AiChatFeature.setup은 mode를 변경하지 않음
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        await store.finish()
    }
}

@MainActor
extension CTM005IndependentContentTabSessionTests {
    /// CTM-005-independent_content_tab_session (VOY-578): AI Chat 복원은 Directory load를 호출하지 않음
    /// Directory snapshot revalidation 변경이 AI Chat session restore 경로를 침범하지 않는지 검증한다.
    /// - 검증 내용: restored AI Chat anchor/session state와 Directory loadItems 0회
    /// - 사전 조건: Home active 상태와 recentlyClosed AI Chat snapshot
    /// - 기대 결과: 새 AI Chat tab이 복원되고 entryLoadingClient.loadItems는 호출되지 않음
    func testRestoringAiChatTabInitializesContentSessionFromRestoredAnchor() async {
        let fixture = AiChatRestoreFixture()
        let store = fixture.store
        await store.send(.contentTabs(.restore))

        guard let activeTabID = store.state.contentTabs.activeTabID else {
            return XCTFail("restore should activate a restored tab")
        }
        XCTAssertNotEqual(activeTabID, fixture.homeID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .aiChat(sessionID: fixture.sessionID))
        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.page, .aiChat)
        XCTAssertEqual(store.state.content.navigation.navigationState, .aiChat(fixture.sessionID))
        XCTAssertNil(store.state.contentTabs.recentlyClosed)
        guard let restoredContent = store.state.tabContentStates[activeTabID] else {
            return XCTFail("restored AI Chat tab should have content state")
        }
        XCTAssertEqual(restoredContent.navigation.navigationState, .aiChat(fixture.sessionID))
        XCTAssertTrue(fixture.directoryLoadPaths.value.isEmpty)
        await store.finish()
    }

    func testCloseAiChatTabAndReopenSameSessionDoesNotCorruptState() async throws {
        let aiChatTabID = ContentTabID()
        let homeTabID = ContentTabID()
        let sessionUUID = try XCTUnwrap(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
        let sessionID = sessionUUID.uuidString
        let aiSessionID = AiChatSessionID(rawValue: sessionUUID)
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = try AiChatRequestID(
            rawValue: XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        )
        let runID = try AiChatRunID(
            rawValue: XCTUnwrap(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")),
        )
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: aiSessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(
            context: requestContext,
            messages: [AiChatMessage(role: .user, content: "test")],
        )
        let requestLock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
        )

        var aiChatContent = FileManagerContentFeature.State()
        aiChatContent.navigation.navigationState = .aiChat(sessionID)
        aiChatContent.aiChat.mode = .chat
        aiChatContent.aiChat.sessionID = aiSessionID
        aiChatContent.aiChat.sessionStatus = .active
        aiChatContent.aiChat.executionPhase = .processing(requestLock)

        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/Users/test/Home")

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionID),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "bubble.right",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = aiChatContent
        state.tabContentStates = [homeTabID: homeContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.contentTabs(.close(aiChatTabID)))

        XCTAssertNil(store.state.contentTabs.tabs[id: aiChatTabID])
        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(
            store.state.backgroundAiChatStates[aiSessionID]?.aiChat.executionPhase,
            .processing(requestLock),
        )
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeTabID)

        await store.skipReceivedActions()

        await store.send(.contentTabs(.open(.aiChat(sessionID: sessionID))))

        let newAIChatTabs = store.state.contentTabs.tabs.filter { $0.page == .aiChat }
        XCTAssertEqual(newAIChatTabs.count, 1, "should have exactly one AI Chat tab")
        XCTAssertEqual(newAIChatTabs[0].anchor, .aiChat(sessionID: sessionID))
        XCTAssertNotEqual(newAIChatTabs[0].id, aiChatTabID, "reopened tab should get a new ContentTabID")

        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.count, 2)
        let sidebarAiChatItems = store.state.sidebar.contentTabSidebarItems.filter { $0.pageType == .aiChat }
        XCTAssertEqual(sidebarAiChatItems.count, 1)

        if let newTabID = newAIChatTabs.first?.id {
            let newTabContentState = store.state.tabContentStates[newTabID]
            XCTAssertNotEqual(
                newTabContentState?.aiChat.executionPhase,
                .processing(requestLock),
                "new tab should not inherit the old background processing state",
            )
        }

        XCTAssertEqual(store.state.contentTabs.recentlyClosed?.anchor, .aiChat(sessionID: sessionID))

        await store.skipReceivedActions()
        await store.finish()
    }

    // MARK: - CTM-005-content_tab_duplicate

    /// CTM-005-content_tab_duplicate: Active Directory source duplicate는 history만 복사하고 owner state는 초기화
    func testDuplicate_activeDirectorySource_copiesHistoryIntoFreshOwnerState() async throws {
        let sourceID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        let backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .home),
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/Users/test")),
        ]
        let forwardHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/Users/test/Downloads")),
        ]
        var state = makeDirectoryDuplicateState(
            sourceID: sourceID,
            directoryPath: directoryPath,
            backHistory: backHistory,
            forwardHistory: forwardHistory,
        )
        let ownerFixture = makeDuplicateOwnerFixture()
        seedDuplicateOwnerState(&state.content, fixture: ownerFixture, pendingSelectEntryID: "entry-id")
        state.syncActiveTabContentState()
        let store = makeContentTabDuplicateStore(state: state, existingDirectoryPath: directoryPath)

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(duplicateID, sourceID)
        XCTAssertEqual(store.state.content.navigation.backHistory, backHistory)
        XCTAssertEqual(store.state.content.navigation.forwardHistory, forwardHistory)
        assertFreshDuplicateOwnerState(store.state.content, fixture: ownerFixture)
        XCTAssertEqual(store.state.tabContentStates[sourceID]?.navigation.backHistory, backHistory)
        assertSourceOwnerStatePreserved(store.state.tabContentStates[sourceID], fixture: ownerFixture)

        let duplicateOnlyHistory = ContentPageNavigationHistorySnapshot(navigationState: .folder("/duplicate-only"))
        await store.send(.navigation(.internal(.appendBackHistory(duplicateOnlyHistory))))
        XCTAssertEqual(store.state.content.navigation.backHistory, backHistory + [duplicateOnlyHistory])
        XCTAssertEqual(store.state.tabContentStates[sourceID]?.navigation.backHistory, backHistory)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Inactive unpinned source는 source history와 fresh owner state로 활성화
    func testDuplicate_inactiveUnpinnedSource_copiesHistoryIntoFreshOwnerState() async throws {
        let activeID = ContentTabID()
        let sourceID = ContentTabID()
        let sourceHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let ownerFixture = makeDuplicateOwnerFixture()
        var sourceContent = FileManagerContentFeature.State()
        sourceContent.navigation.navigationState = .recents
        sourceContent.navigation.backHistory = sourceHistory
        seedDuplicateOwnerState(&sourceContent, fixture: ownerFixture, pendingSelectEntryID: "source-entry")
        var state = makeInactiveDuplicateState(activeID: activeID, sourceID: sourceID, sourceIsPinned: false)
        state.tabContentStates[sourceID] = sourceContent
        let store = makeContentTabDuplicateStore(state: state)

        await store.send(.request(.duplicateContentTab(sourceID)))
        await store.skipReceivedActions()

        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(duplicateID, activeID)
        XCTAssertNotEqual(duplicateID, sourceID)
        XCTAssertEqual(store.state.content.navigation.navigationState, .tags("Recents"))
        XCTAssertEqual(store.state.content.navigation.backHistory, sourceHistory)
        assertFreshDuplicateOwnerState(store.state.content, fixture: ownerFixture)
        XCTAssertEqual(store.state.tabContentStates[sourceID], sourceContent)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Pinned source는 active 유지와 함께 history만 fresh cache에 복제
    func testDuplicate_pinnedSource_copiesHistoryIntoFreshCacheWithoutActivation() async throws {
        let activeID = ContentTabID()
        let sourceID = ContentTabID()
        let sourceHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let ownerFixture = makeDuplicateOwnerFixture()
        var sourceContent = FileManagerContentFeature.State()
        sourceContent.navigation.navigationState = .recents
        sourceContent.navigation.backHistory = sourceHistory
        seedDuplicateOwnerState(&sourceContent, fixture: ownerFixture, pendingSelectEntryID: "pinned-entry")
        var state = makeInactiveDuplicateState(activeID: activeID, sourceID: sourceID, sourceIsPinned: true)
        state.tabContentStates[sourceID] = sourceContent
        let store = makeContentTabDuplicateStore(state: state)

        await store.send(.request(.duplicateContentTab(sourceID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, activeID)
        let duplicateID = try XCTUnwrap(
            store.state.contentTabs.tabs.first { $0.id != sourceID && $0.id != activeID }?.id,
        )
        let duplicateContent = try XCTUnwrap(store.state.tabContentStates[duplicateID])
        XCTAssertNotEqual(duplicateID, sourceID)
        XCTAssertEqual(duplicateContent.navigation.navigationState, .tags("Recents"))
        XCTAssertEqual(duplicateContent.navigation.backHistory, sourceHistory)
        assertFreshDuplicateOwnerState(duplicateContent, fixture: ownerFixture)
        XCTAssertEqual(store.state.tabContentStates[sourceID], sourceContent)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Active pinned source는 live history를 fresh duplicate cache에 복제
    func testDuplicate_activePinnedSource_copiesLiveHistoryIntoFreshCache() async throws {
        let sourceID = ContentTabID()
        let sourceHistory = [ContentPageNavigationHistorySnapshot(navigationState: .home)]
        let ownerFixture = makeDuplicateOwnerFixture()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: sourceID,
                page: .collection,
                anchor: .virtualCollection(id: "Recents"),
                isPinned: true,
                title: "Recents",
                iconName: "clock",
            )],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content.navigation.navigationState = .recents
        state.content.navigation.backHistory = sourceHistory
        seedDuplicateOwnerState(&state.content, fixture: ownerFixture, pendingSelectEntryID: "active-pinned-entry")
        state.syncActiveTabContentState()
        var staleCachedContent = state.content
        staleCachedContent.navigation.navigationState = .home
        staleCachedContent.navigation.backHistory = []
        state.tabContentStates[sourceID] = staleCachedContent
        state.syncContentTabSidebarItems()
        let store = makeContentTabDuplicateStore(state: state)

        await store.send(.request(.duplicateContentTab(sourceID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        let duplicateID = try XCTUnwrap(store.state.contentTabs.tabs.last?.id)
        let duplicateContent = try XCTUnwrap(store.state.tabContentStates[duplicateID])
        XCTAssertEqual(duplicateContent.navigation.navigationState, .tags("Recents"))
        XCTAssertEqual(duplicateContent.navigation.backHistory, sourceHistory)
        assertFreshDuplicateOwnerState(duplicateContent, fixture: ownerFixture)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Active Collection file duplicate는 stable anchor로 fresh owner를 다시 엶
    func testDuplicate_activeCollectionFileSource_reopensWithFreshOwnerState() async throws {
        let sourceID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/test.voycoll")
        let baselineContext = CollectionContext(query: "kind:document", scopes: ["/tmp"], conditions: [])
        let dirtyContext = CollectionContext(query: "kind:image", scopes: ["/tmp"], conditions: [])
        let ownerFixture = makeDuplicateOwnerFixture()
        var state = makeLoadedCollectionDuplicateState(
            sourceID: sourceID,
            collectionURL: collectionURL,
            collectionContext: baselineContext,
        )
        state.content.collection.collectionContext = dirtyContext
        seedDuplicateOwnerState(&state.content, fixture: ownerFixture, pendingSelectEntryID: "collection-entry")
        state.syncActiveTabContentState()
        XCTAssertTrue(state.content.canSaveCollection)

        let store = makeContentTabDuplicateStore(
            state: state,
            existingDirectoryPath: collectionURL.path,
        )
        await store.send(.request(.duplicateActiveContentTab))
        await store.receive { action in
            guard case let .contentTabs(.duplicate(receivedSourceID, _)) = action else { return false }
            return receivedSourceID == sourceID
        }
        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        await store.receive { action in
            guard case let .internal(.duplicateContentTabReduced(
                receivedSourceID,
                receivedDuplicateID,
                duplicateIDWasPreexisting,
            )) = action else { return false }
            return receivedSourceID == sourceID
                && receivedDuplicateID == duplicateID
                && !duplicateIDWasPreexisting
        }

        let sourceContent = try XCTUnwrap(store.state.tabContentStates[sourceID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: duplicateID]?.anchor, .collectionFile(url: collectionURL))
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(store.state.content.collection.collectionContext)
        XCTAssertNil(store.state.content.collection.collectionSession.document)
        XCTAssertNil(store.state.content.collection.collectionSession.metadata.baseline)
        assertFreshDuplicateOwnerState(store.state.content, fixture: ownerFixture)
        XCTAssertEqual(sourceContent.collection.collectionContext, dirtyContext)
        XCTAssertEqual(sourceContent.collection.collectionSession.metadata.baseline, .init(context: baselineContext))
        assertSourceOwnerStatePreserved(sourceContent, fixture: ownerFixture)

        await store.receive(\.navigation.view.openCollectionFile, collectionURL)
        await store.skipReceivedActions()
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Collection ownerless 작업 중에는 duplicate를 생성하지 않음
    func testDuplicate_activeCollectionOperationInProgress_isBlocked() async {
        await assertCollectionDuplicateBlocked(
            phase: .opened(kind: .definition, base: .ready, inflight: .none),
            isSaving: true,
        )
        await assertCollectionDuplicateBlocked(
            phase: .reopening(kind: .definition, base: .ready, inflight: .none),
        )
        await assertCollectionDuplicateBlocked(
            phase: .opened(kind: .definition, base: .stale, inflight: .refreshingHydratedSnapshot),
        )
        await assertCollectionDuplicateBlocked(
            phase: .opened(kind: .definition, base: .stale, inflight: .writingBackRefreshedSnapshot),
        )
    }

    /// CTM-005-content_tab_duplicate: 기존 AI Chat session duplicate는 같은 session을 fresh content에 복원
    func testDuplicate_activeAiChatSession_restoresSameSessionInFreshContent() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let sessionIDString = aiSessionID.rawValue.uuidString
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let snapshot = makeAiChatSessionSnapshot(sessionID: aiSessionID)
        let providerFixture = makeConnectedAiProviderFixture()
        let duplicateUUID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let state = makeSettledAiChatWindowState(
            sourceID: sourceID,
            sessionID: aiSessionID,
        )

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .constant(duplicateUUID)
            $0.aiConnectionsFileClient.load = { providerFixture.connectionsFile }
            $0.aiProviderModelListClient = AiProviderModelListClient { provider, credential in
                XCTAssertEqual(provider, .openai)
                XCTAssertEqual(credential, providerFixture.credential)
                return [providerFixture.model]
            }
            $0.aiChatSessionPersistenceClient.loadSession = { requestedSessionID in
                loadedSessionIDs.withValue { $0.append(requestedSessionID) }
                return snapshot
            }
            $0.aiChatSessionPersistenceClient.saveSession = { savedSnapshot in savedSnapshot }
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { _, _ in false }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(duplicateID, sourceID)
        XCTAssertEqual(store.state.contentTabs.tabs[id: duplicateID]?.anchor, .aiChat(sessionID: sessionIDString))
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, snapshot.transcriptHistory)
        XCTAssertEqual(store.state.content.aiChat.modelListState, .loaded([providerFixture.model]))
        XCTAssertEqual(loadedSessionIDs.value, [aiSessionID])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Pinned settled AI Chat duplicate는 선택 시 같은 session을 fresh owner에 복원
    func testDuplicate_pinnedAiChatSession_restoresWhenSelected() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let snapshot = makeAiChatSessionSnapshot(sessionID: aiSessionID)
        let providerFixture = makeConnectedAiProviderFixture()
        var state = makeSettledAiChatWindowState(sourceID: sourceID, sessionID: aiSessionID, sourceIsPinned: true)
        state.syncActiveTabContentState()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { providerFixture.connectionsFile }
            $0.aiProviderModelListClient = AiProviderModelListClient { _, _ in [providerFixture.model] }
            $0.aiChatSessionPersistenceClient.loadSession = { requestedSessionID in
                loadedSessionIDs.withValue { $0.append(requestedSessionID) }
                return snapshot
            }
            $0.aiChatSessionPersistenceClient.saveSession = { savedSnapshot in savedSnapshot }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        let duplicateID = try XCTUnwrap(store.state.contentTabs.tabs.last?.id)
        XCTAssertNil(store.state.tabContentStates[duplicateID]?.aiChat.sessionID)
        XCTAssertEqual(store.state.tabContentStates[duplicateID]?.aiChat.transcriptHistory.isEmpty, true)

        await store.send(.contentTabs(.setCurrent(duplicateID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, duplicateID)
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, snapshot.transcriptHistory)
        XCTAssertEqual(loadedSessionIDs.value, [aiSessionID])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: active AI Chat in-flight duplicate는 final snapshot으로 hydrate
    func testDuplicate_activeAiChatInFlight_preservesLifecycleAndHydratesFromFinalSnapshot() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = makeFinalAiChatSessionSnapshot(sessionID: aiSessionID, requestLock: requestLock)
        let ownerLock = requestLock.recordingFinalSnapshot(finalSnapshot)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let state = makeInFlightAiChatDuplicateState(
            sourceID: sourceID,
            sessionID: aiSessionID,
            requestLock: ownerLock,
            sourceIsPinned: false,
        )
        let store = makeInFlightAiChatDuplicateStore(
            state: state,
            loadedSessionIDs: loadedSessionIDs,
            staleSnapshot: makeAiChatSessionSnapshot(sessionID: aiSessionID),
        )

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        XCTAssertNotEqual(duplicateID, sourceID)
        XCTAssertEqual(store.state.tabContentStates[sourceID]?.aiChat.executionPhase, .processing(ownerLock))
        XCTAssertNotEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.backgroundAiChatSnapshotPersisted(finalSnapshot))

        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertEqual(
            store.state.tabContentStates[duplicateID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[sourceID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: active AI Chat in-flight 실패는 disk restore 없이 duplicate에 전파
    func testDuplicate_activeAiChatInFlight_hydratesFailureWithoutDiskRestore() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let state = makeInFlightAiChatDuplicateState(
            sourceID: sourceID,
            sessionID: aiSessionID,
            requestLock: requestLock,
            sourceIsPinned: false,
        )
        let store = makeInFlightAiChatDuplicateStore(
            state: state,
            loadedSessionIDs: loadedSessionIDs,
            staleSnapshot: makeAiChatSessionSnapshot(sessionID: aiSessionID),
        )

        await store.send(.request(.duplicateActiveContentTab))
        await store.receive { action in
            guard case let .contentTabs(.duplicate(receivedSourceID, _)) = action else { return false }
            return receivedSourceID == sourceID
        }
        let duplicateID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        await store.receive { action in
            guard case let .internal(.duplicateContentTabReduced(
                receivedSourceID,
                receivedDuplicateID,
                duplicateIDWasPreexisting,
            )) = action else { return false }
            return receivedSourceID == sourceID
                && receivedDuplicateID == duplicateID
                && !duplicateIDWasPreexisting
        }

        XCTAssertNil(store.state.content.aiChat.sessionID)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.backgroundAiChat(.executionEvent(.failed(
            context: requestLock.context,
            reason: .network,
        ))))

        let failedLock = requestLock.recordingTerminal(
            at: 1_234_567_890_000,
            failure: .network,
            wasCancelled: false,
        )
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .failed(failedLock, .network))
        XCTAssertEqual(store.state.content.aiChat.lastExecutionFailure, .network)
        XCTAssertEqual(store.state.tabContentStates[duplicateID]?.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.tabContentStates[sourceID]?.aiChat.executionPhase, .failed(failedLock, .network))
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])

        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .failed(failedLock, .network))
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: pinned AI Chat in-flight duplicate 선택은 disk restore 없이 final snapshot으로 hydrate
    func testDuplicate_pinnedAiChatInFlight_selectingDuplicateHydratesFromFinalSnapshot() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = makeFinalAiChatSessionSnapshot(sessionID: aiSessionID, requestLock: requestLock)
        let ownerLock = requestLock.recordingFinalSnapshot(finalSnapshot)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let state = makeInFlightAiChatDuplicateState(
            sourceID: sourceID,
            sessionID: aiSessionID,
            requestLock: ownerLock,
            sourceIsPinned: true,
        )
        let store = makeInFlightAiChatDuplicateStore(
            state: state,
            loadedSessionIDs: loadedSessionIDs,
            staleSnapshot: makeAiChatSessionSnapshot(sessionID: aiSessionID),
        )

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        let duplicateID = try XCTUnwrap(store.state.contentTabs.tabs.last?.id)
        XCTAssertNil(store.state.tabContentStates[duplicateID]?.aiChat.sessionID)

        await store.send(.contentTabs(.setCurrent(duplicateID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, duplicateID)
        XCTAssertNotEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.backgroundAiChatSnapshotPersisted(finalSnapshot))

        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertEqual(
            store.state.tabContentStates[duplicateID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[sourceID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: pinned AI Chat persistence recovery는 duplicate에 최신 snapshot을 전파
    func testDuplicate_pinnedAiChatInFlight_hydratesPersistenceRecoveryWithoutDiskRestore() async throws {
        let sourceID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = makeFinalAiChatSessionSnapshot(sessionID: aiSessionID, requestLock: requestLock)
        let ownerLock = requestLock.recordingFinalSnapshot(finalSnapshot)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        var state = makeInFlightAiChatDuplicateState(
            sourceID: sourceID,
            sessionID: aiSessionID,
            requestLock: ownerLock,
            sourceIsPinned: true,
        )
        state.content.aiChat.executionPhase = .persistenceRecovery(ownerLock, .unknown)
        state.content.aiChat.lastExecutionFailure = .unknown
        state.tabContentStates[sourceID] = state.content
        let store = makeInFlightAiChatDuplicateStore(
            state: state,
            loadedSessionIDs: loadedSessionIDs,
            staleSnapshot: makeAiChatSessionSnapshot(sessionID: aiSessionID),
        )

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()
        let duplicateID = try XCTUnwrap(store.state.contentTabs.tabs.last?.id)

        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        XCTAssertNil(store.state.tabContentStates[duplicateID]?.aiChat.sessionID)
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.content(.aiChat(.persistenceRecoverySucceeded(ownerLock))))
        XCTAssertEqual(store.state.tabContentStates[duplicateID]?.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.tabContentStates[duplicateID]?.aiChat.executionPhase, .completed(ownerLock))
        XCTAssertEqual(
            store.state.tabContentStates[duplicateID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )

        await store.send(.contentTabs(.setCurrent(duplicateID)))
        await store.skipReceivedActions()
        XCTAssertEqual(store.state.content.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.content.aiChat.executionPhase, .completed(ownerLock))
        XCTAssertEqual(store.state.content.aiChat.transcriptHistory, finalSnapshot.transcriptHistory)
        XCTAssertNil(store.state.content.aiChat.lastExecutionFailure)
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: pinned AI Chat in-flight duplicate cache는 final snapshot으로 hydrate
    func testDuplicate_pinnedAiChatInFlight_inactiveDuplicateHydratesFromFinalSnapshot() async throws {
        let sourceID = ContentTabID()
        let homeID = ContentTabID()
        let aiSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: aiSessionID)
        let finalSnapshot = makeFinalAiChatSessionSnapshot(sessionID: aiSessionID, requestLock: requestLock)
        let ownerLock = requestLock.recordingFinalSnapshot(finalSnapshot)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let state = makeInFlightAiChatDuplicateStateWithInactiveHome(
            sourceID: sourceID,
            homeID: homeID,
            sessionID: aiSessionID,
            requestLock: ownerLock,
        )
        let store = makeInFlightAiChatDuplicateStore(
            state: state,
            loadedSessionIDs: loadedSessionIDs,
            staleSnapshot: makeAiChatSessionSnapshot(sessionID: aiSessionID),
        )

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        let duplicateID = try XCTUnwrap(
            store.state.contentTabs.tabs.first { $0.id != sourceID && $0.id != homeID }?.id,
        )
        XCTAssertNil(store.state.tabContentStates[duplicateID]?.aiChat.sessionID)

        await store.send(.contentTabs(.setCurrent(homeID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertNotNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertNil(store.state.tabContentStates[duplicateID]?.aiChat.sessionID)
        XCTAssertEqual(loadedSessionIDs.value, [])

        await store.send(.backgroundAiChatSnapshotPersisted(finalSnapshot))

        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.tabContentStates[duplicateID]?.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(
            store.state.tabContentStates[duplicateID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertEqual(
            store.state.tabContentStates[sourceID]?.aiChat.transcriptHistory,
            finalSnapshot.transcriptHistory,
        )
        XCTAssertNil(store.state.backgroundAiChatStates[aiSessionID])
        XCTAssertEqual(loadedSessionIDs.value, [])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Virtual Collection source duplicate는 항상 허용됨
    func testDuplicate_virtualCollectionSource_allowed() async {
        let sourceID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .collection,
                    anchor: .virtualCollection(id: "Recents"),
                    isPinned: false,
                    title: "Recents",
                    iconName: "clock",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { _, _ in false }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateActiveContentTab))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 2)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, sourceID)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Inactive pinned source duplicate는 pinned 경계에 삽입되고 active 탭이 변경되지 않음
    func testDuplicate_pinnedInactiveSource_doesNotChangeActive() async {
        let pinID = ContentTabID()
        let homeID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinID,
                    page: .directory,
                    anchor: .directory(path: "/pinned"),
                    isPinned: true,
                    title: "Pinned",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.contentTabs.selectedTabIDs = [pinID, homeID]
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { path, isDir in
                if path == "/pinned" { isDir?.pointee = true
                    return true
                }
                return false
            }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateContentTab(pinID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 3)
        XCTAssertEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, [pinID, homeID])
        XCTAssertNil(store.state.contentTabs.selectionAnchorID)
        XCTAssertEqual(store.state.contentTabs.tabs.first?.id, pinID)
        XCTAssertEqual(store.state.contentTabs.tabs.last?.id, homeID)
        let duplicate = store.state.contentTabs.tabs[1]
        XCTAssertNotEqual(duplicate.id, pinID)
        XCTAssertNotEqual(duplicate.id, homeID)
        XCTAssertEqual(duplicate.anchor, .directory(path: "/pinned"))
        XCTAssertFalse(duplicate.isPinned)
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: Inactive source duplicate는 source ID의 cache를 사용해 검증
    func testDuplicate_inactiveSource_usesTabContentStateForValidation() async {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.seedInitialFolderPath("/home")
        var directoryContent = FileManagerContentFeature.State()
        directoryContent.navigation.seedInitialFolderPath(directoryPath)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
        )
        state.content = homeContent
        state.tabContentStates = [homeID: homeContent, directoryID: directoryContent]
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { path, isDir in
                if path == directoryPath { isDir?.pointee = true
                    return true
                }
                return false
            }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateContentTab(directoryID)))
        await store.skipReceivedActions()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 3)
        XCTAssertNotEqual(store.state.contentTabs.activeTabID, homeID)
        XCTAssertNotNil(store.state.contentTabs.activeTabID)
        XCTAssertEqual(store.state.tabContentStates[directoryID]?.navigation.currentPath, directoryPath)
        XCTAssertNotNil(store.state.tabContentStates[homeID])
        await store.finish()
    }

    /// CTM-005-content_tab_duplicate: missing path/file → no-op
    func testDuplicate_missingPath_noop() async {
        let sourceID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .directory,
                    anchor: .directory(path: "/nonexistent"),
                    isPinned: false,
                    title: "Missing",
                    iconName: "folder",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { _, _ in false }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateActiveContentTab))

        // 검증 실패 시 effect와 state 변경 없음
        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        await store.finish()
    }
}

// MARK: - Helpers

private struct ConnectedAiProviderFixture {
    let connectionsFile: AIConnectionsFile
    let credential: StoredCredentialPayload
    let model: AiProviderModel
}

private struct AliasedAiChatOwnerFixture {
    let sessionID: AiChatSessionID
    let aliasSessionID: AiChatSessionID
    let aliasRequestID: AiChatRequestID
    let snapshot: AiChatSessionSnapshot
    let aliasSnapshot: AiChatSessionSnapshot
    let backgroundContent: FileManagerContentFeature.State
}

private struct DuplicateOwnerFixture {
    let windowID: UUID
    let composerOwnerID: UUID
    let undoRecord: EntryActionRecord
    let redoRecord: EntryActionRecord
}

private extension CTM005IndependentContentTabSessionTests {
    func makeAliasedAiChatOwnerFixture() -> AliasedAiChatOwnerFixture {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let aliasSessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID)
        let aliasLock = makeRequestLock(sessionID: aliasSessionID)
        let snapshot = makeFinalAiChatSessionSnapshot(sessionID: sessionID, requestLock: requestLock)
        let aliasSnapshot = makeFinalAiChatSessionSnapshot(sessionID: aliasSessionID, requestLock: aliasLock)
        let ownerLock = requestLock.recordingFinalSnapshot(snapshot)
        let aliasOwnerLock = aliasLock.recordingFinalSnapshot(aliasSnapshot)
        var backgroundContent = FileManagerContentFeature.State()
        backgroundContent.aiChat.sessionID = sessionID
        backgroundContent.aiChat.executionPhase = .completed(ownerLock)
        backgroundContent.aiChat.backgroundExecutionPhases[aliasLock.requestID] = .completed(aliasOwnerLock)
        return AliasedAiChatOwnerFixture(
            sessionID: sessionID,
            aliasSessionID: aliasSessionID,
            aliasRequestID: aliasLock.requestID,
            snapshot: snapshot,
            aliasSnapshot: aliasSnapshot,
            backgroundContent: backgroundContent,
        )
    }

    func makeDuplicateOwnerFixture() -> DuplicateOwnerFixture {
        DuplicateOwnerFixture(
            windowID: UUID(),
            composerOwnerID: UUID(),
            undoRecord: EntryActionRecord(
                operationKind: .rename,
                targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
            ),
            redoRecord: EntryActionRecord(
                operationKind: .moveToTrash,
                targets: [EntryActionRecord.Target(beforePath: "/tmp/c.txt", afterPath: "/tmp/d.txt")],
            ),
        )
    }

    func seedDuplicateOwnerState(
        _ content: inout FileManagerContentFeature.State,
        fixture: DuplicateOwnerFixture,
        pendingSelectEntryID: String,
    ) {
        content.entryViewLayout.entryOperations.windowID = fixture.windowID
        content.entryViewLayout.entryOperations.undoRecords = [fixture.undoRecord]
        content.entryViewLayout.entryOperations.redoRecords = [fixture.redoRecord]
        content.entryViewLayout.entryOperations.selectedEntryIDs = ["selected-entry"]
        content.entryViewLayout.entryOperations.clipboardItems = ["/tmp/clipboard.txt"]
        content.entryViewLayout.entryOperations.clipboardOperation = .cut
        content.composer.cancellationOwnerID = fixture.composerOwnerID
        content.composer.isPresented = true
        content.composer.text = "owner draft"
        content.composer.collectionContext = CollectionContext(query: "draft", scopes: ["/tmp"], conditions: [])
        content.pendingSelectEntryID = pendingSelectEntryID
    }

    func assertFreshDuplicateOwnerState(
        _ content: FileManagerContentFeature.State,
        fixture: DuplicateOwnerFixture,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let entryOperations = content.entryViewLayout.entryOperations
        XCTAssertEqual(entryOperations.windowID, fixture.windowID, file: file, line: line)
        XCTAssertTrue(entryOperations.undoRecords.isEmpty, file: file, line: line)
        XCTAssertTrue(entryOperations.redoRecords.isEmpty, file: file, line: line)
        XCTAssertTrue(entryOperations.selectedEntryIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(entryOperations.clipboardItems.isEmpty, file: file, line: line)
        XCTAssertEqual(entryOperations.clipboardOperation, .copy, file: file, line: line)
        XCTAssertEqual(content.composer.cancellationOwnerID, fixture.composerOwnerID, file: file, line: line)
        XCTAssertFalse(content.composer.isPresented, file: file, line: line)
        XCTAssertTrue(content.composer.text.isEmpty, file: file, line: line)
        XCTAssertNil(content.composer.collectionContext, file: file, line: line)
        XCTAssertNil(content.pendingSelectEntryID, file: file, line: line)
    }

    func assertSourceOwnerStatePreserved(
        _ content: FileManagerContentFeature.State?,
        fixture: DuplicateOwnerFixture,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard let content else {
            XCTFail("Source content state is missing", file: file, line: line)
            return
        }
        XCTAssertEqual(
            content.entryViewLayout.entryOperations.undoRecords,
            [fixture.undoRecord],
            file: file,
            line: line,
        )
        XCTAssertEqual(
            content.entryViewLayout.entryOperations.redoRecords,
            [fixture.redoRecord],
            file: file,
            line: line,
        )
        XCTAssertEqual(
            content.entryViewLayout.entryOperations.selectedEntryIDs,
            ["selected-entry"],
            file: file,
            line: line,
        )
        XCTAssertEqual(
            content.entryViewLayout.entryOperations.clipboardItems,
            ["/tmp/clipboard.txt"],
            file: file,
            line: line,
        )
        XCTAssertTrue(content.composer.isPresented, file: file, line: line)
        XCTAssertEqual(content.composer.text, "owner draft", file: file, line: line)
    }

    func makeDirectoryDuplicateState(
        sourceID: ContentTabID,
        directoryPath: String,
        backHistory: [ContentPageNavigationHistorySnapshot],
        forwardHistory: [ContentPageNavigationHistorySnapshot],
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .directory,
                    anchor: .directory(path: directoryPath),
                    isPinned: false,
                    title: "Desktop",
                    iconName: "folder",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content.navigation.seedInitialFolderPath(directoryPath)
        state.content.navigation.backHistory = backHistory
        state.content.navigation.forwardHistory = forwardHistory
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }

    func makeLoadedCollectionDuplicateState(
        sourceID: ContentTabID,
        collectionURL: URL,
        collectionContext: CollectionContext,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .collection,
                    anchor: .collectionFile(url: collectionURL),
                    isPinned: false,
                    title: "Collection",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = collectionContext
        state.content.collection.collectionSession.document = .init(
            url: collectionURL,
            name: "test",
        )
        state.content.collection.collectionSession.metadata.baseline = .init(context: collectionContext)
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        return state
    }

    func assertCollectionDuplicateBlocked(
        phase: CollectionSessionPhase,
        isSaving: Bool = false,
    ) async {
        let sourceID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/tmp/test.voycoll")
        let alerts = LockIsolated<[String]>([])
        var state = makeLoadedCollectionDuplicateState(
            sourceID: sourceID,
            collectionURL: collectionURL,
            collectionContext: CollectionContext(query: "", scopes: ["/tmp"], conditions: []),
        )
        state.content.collection.collectionSession.phase = phase
        state.content.collection.isSaving = isSaving
        state.syncActiveTabContentState()
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            var fileManagerClient = FileManagerClient.testValue
            fileManagerClient.fileExistsWithIsDirectory = { path, _ in path == collectionURL.path }
            $0.fileManagerClient = fileManagerClient
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alerts.withValue { $0.append("\(title): \(message)") }
            }
        }
        store.exhaustivity = .off

        await store.send(.request(.duplicateActiveContentTab))
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs.count, 1)
        XCTAssertEqual(store.state.contentTabs.activeTabID, sourceID)
        XCTAssertEqual(
            alerts.value,
            ["Cannot Duplicate Tab: Wait for the current collection operation to finish, then try again."],
        )
    }

    func makeInactiveDuplicateState(
        activeID: ContentTabID,
        sourceID: ContentTabID,
        sourceIsPinned: Bool,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .collection,
                    anchor: .virtualCollection(id: "Recents"),
                    isPinned: sourceIsPinned,
                    title: "Recents",
                    iconName: "clock",
                ),
                ContentTabItem(
                    id: activeID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: activeID,
            recentlyClosed: nil,
        )
        state.tabContentStates = [activeID: state.content]
        state.syncContentTabSidebarItems()
        return state
    }

    func makeContentTabDuplicateStore(
        state: FileManagerFeature.State,
        existingDirectoryPath: String? = nil,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { path, isDirectory in
                guard path == existingDirectoryPath else { return false }
                isDirectory?.pointee = true
                return true
            }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off
        return store
    }

    func makeConnectedAiProviderFixture() -> ConnectedAiProviderFixture {
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-test")
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-test"))
        return ConnectedAiProviderFixture(
            connectionsFile: AIConnectionsFile(
                updatedAtMs: 1,
                lastUsedProviderId: .openai,
                providers: [
                    AiProvider.openai.rawValue: ProviderRecordFile(
                        providerId: .openai,
                        authMethod: .apiKey,
                        credential: credential,
                        snapshot: ProviderSnapshotFile(lastKnownStatus: .connected),
                    ),
                ],
            ),
            credential: credential,
            model: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-test",
                displayName: "GPT Test",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unsupported(reason: AiThinkingUnavailableReason(message: "unsupported")),
            ),
        )
    }

    func makeFinalAiChatSessionSnapshot(
        sessionID: AiChatSessionID,
        requestLock: AiChatRequestLock,
    ) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: requestLock.context.provider,
            model: requestLock.selectedModelHandle,
            selectedModelRow: requestLock.selectedModelRow,
            selectedThinking: requestLock.context.selectedThinking,
            transcriptHistory: [
                AiChatMessage(role: .user, content: "test"),
                AiChatMessage(role: .assistant, content: "latest done"),
            ],
            lastRequestID: requestLock.requestID,
            lastRunID: requestLock.runID,
            lastRequestContext: requestLock.context.requestContext,
            updatedAtMs: 1_234_567_891_000,
        )
    }

    func makeInFlightAiChatDuplicateState(
        sourceID: ContentTabID,
        sessionID: AiChatSessionID,
        requestLock: AiChatRequestLock,
        sourceIsPinned: Bool,
    ) -> FileManagerFeature.State {
        let sessionIDString = sessionID.rawValue.uuidString
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .aiChat(sessionIDString)
        content.aiChat.sessionID = sessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.executionPhase = .processing(requestLock)

        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionIDString),
                    isPinned: sourceIsPinned,
                    title: "AI Chat",
                    iconName: "sparkles",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [sourceID: content]
        state.syncContentTabSidebarItems()
        return state
    }

    func makeInFlightAiChatDuplicateStateWithInactiveHome(
        sourceID: ContentTabID,
        homeID: ContentTabID,
        sessionID: AiChatSessionID,
        requestLock: AiChatRequestLock,
    ) -> FileManagerFeature.State {
        var state = makeInFlightAiChatDuplicateState(
            sourceID: sourceID,
            sessionID: sessionID,
            requestLock: requestLock,
            sourceIsPinned: true,
        )
        let homeContent = FileManagerContentFeature.State.initialContent(
            for: .homeDefault,
            inheritingWindowContextFrom: state.content,
        )
        state.contentTabs.tabs.append(ContentTabItem(
            id: homeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        ))
        state.tabContentStates[homeID] = homeContent
        state.syncContentTabSidebarItems()
        return state
    }

    func makeInFlightAiChatDuplicateStore(
        state: FileManagerFeature.State,
        loadedSessionIDs: LockIsolated<[AiChatSessionID]>,
        staleSnapshot: AiChatSessionSnapshot,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { sessionID in
                loadedSessionIDs.withValue { $0.append(sessionID) }
                return staleSnapshot
            }
            var client = FileManagerClient.testValue
            client.fileExistsWithIsDirectory = { _, _ in false }
            $0.fileManagerClient = client
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
        store.exhaustivity = .off
        return store
    }

    func makeAiChatSessionSnapshot(sessionID: AiChatSessionID) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Existing session",
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "duplicate me")],
            updatedAtMs: 1_234_567_890_000,
        )
    }

    func makeSettledAiChatContent(
        sessionID: AiChatSessionID,
        sessionIDString: String,
    ) -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .aiChat(sessionIDString)
        content.aiChat.sessionID = sessionID
        content.aiChat.sessionStatus = .active
        return content
    }

    func makeSettledAiChatWindowState(
        sourceID: ContentTabID,
        sessionID: AiChatSessionID,
        sourceIsPinned: Bool = false,
    ) -> FileManagerFeature.State {
        let sessionIDString = sessionID.rawValue.uuidString
        let content = makeSettledAiChatContent(
            sessionID: sessionID,
            sessionIDString: sessionIDString,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: sourceID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: sessionIDString),
                    isPinned: sourceIsPinned,
                    title: "Existing session",
                    iconName: "sparkles",
                ),
            ],
            activeTabID: sourceID,
            recentlyClosed: nil,
        )
        state.content = content
        state.tabContentStates = [sourceID: content]
        state.syncContentTabSidebarItems()
        return state
    }

    func receiveDirectoryReload(
        tabID: ContentTabID,
        path: String,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) async {
        await store.receive { action in
            guard case let .tabContent(receivedTabID, .internal(.applyNavigationState(.folder(receivedPath)))) = action
            else { return false }
            return receivedTabID == tabID && receivedPath == path
        }
        await store.receive { action in
            guard case let .tabContent(receivedTabID,
                                       .entryViewLayout(.internal(.clearCollectionPresentation))) = action
            else { return false }
            return receivedTabID == tabID
        }
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .entryViewLayout(.entryOperations(.loading(.loadItems(
                    path: receivedPath,
                    showHidden: false,
                    priority: _,
                )))),
            ) = action else { return false }
            return receivedTabID == tabID && receivedPath == path
        }
    }

    func receiveHomeReload(
        tabID: ContentTabID,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) async {
        await store.receive { action in
            guard case let .tabContent(receivedTabID, .internal(.applyNavigationState(.home))) = action
            else { return false }
            return receivedTabID == tabID
        }
        await store.receive { action in
            guard case let .tabContent(receivedTabID,
                                       .entryViewLayout(.internal(.clearCollectionPresentation))) = action
            else { return false }
            return receivedTabID == tabID
        }
        await store.receive { action in
            guard case let .tabContent(receivedTabID, .entryViewLayout(.internal(.applyClearSelection))) = action
            else { return false }
            return receivedTabID == tabID
        }
        await receiveItemsLoaded(tabID: tabID, store: store)
    }

    func receiveItemsLoaded(
        tabID _: ContentTabID,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) async {
        await store.receiveTabContent(\.entryViewLayout.view.applyContentProjection)
    }

    func assertRestoredDirectoryPresentation(
        _ fixture: InactiveDirectoryRestoreFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) {
        XCTAssertEqual(store.state.content.entryViewLayout.mode, .grid)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.staleEntry])
        XCTAssertEqual(Array(store.state.content.entryViewLayout.entryOperations.items), [fixture.staleEntry])
        XCTAssertTrue(store.state.content.isOrdinaryDirectoryLoading)
    }

    func assertFreshDirectoryReload(
        _ fixture: InactiveDirectoryRestoreFixture,
        loadCountBeforeRestore: Int,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) {
        XCTAssertEqual(fixture.loadPaths.value, [fixture.directoryPath, fixture.directoryPath])
        XCTAssertEqual(fixture.loadPaths.value.count - loadCountBeforeRestore, 1)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.freshEntry])
        XCTAssertEqual(fixture.watchedRoots.value, [[fixture.directoryPath], [fixture.directoryPath]])
    }

    func assertFreshSupersededDirectoryLoad(
        _ fixture: SupersededDirectoryLoadFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) {
        XCTAssertEqual(store.state.content.navigation.currentPath, fixture.secondPath)
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.freshEntry])
        XCTAssertEqual(Array(store.state.content.entryViewLayout.entryOperations.items), [fixture.freshEntry])
    }

    func verifyDirectoryReloadFailureRetriesAndReloadsSuccessfulEmptySnapshot() async {
        let fixture = makeDirectoryLoadFailureRetryFixture()
        let store = fixture.store

        await store.send(.contentTabs(.setCurrent(fixture.directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(fixture.directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await fixture.gate.waitUntilWaiting()
        XCTAssertEqual(store.state.content.entryViewLayout.entries, [fixture.staleEntry])

        await fixture.gate.resume(with: .failure)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamFailed, 1)

        await store.send(.contentTabs(.setCurrent(fixture.homeID)))
        await store.skipReceivedActions()
        await store.send(.contentTabs(.setCurrent(fixture.directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(fixture.directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await fixture.gate.waitUntilWaiting()
        await fixture.gate.resume(with: .entries([]))
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)
        await store.skipReceivedActions()
        assertSuccessfulEmptyDirectorySnapshot(fixture, store: store)

        await store.send(.contentTabs(.setCurrent(fixture.homeID)))
        await store.skipReceivedActions()
        await store.send(.contentTabs(.setCurrent(fixture.directoryID)))
        await store.receiveTabContent(\.internal.applyNavigationState, .folder(fixture.directoryPath))
        await store.receiveTabContent(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.loadItems)
        await fixture.gate.waitUntilWaiting()
        await fixture.gate.resume(with: .entries([]))
        await store.receiveTabContent(\.entryViewLayout.entryOperations.loading.streamEvent)
        XCTAssertEqual(fixture.loadPaths.value, [
            fixture.directoryPath,
            fixture.directoryPath,
            fixture.directoryPath,
        ])
        XCTAssertTrue(store.state.content.entryViewLayout.entries.isEmpty)

        fixture.eventContinuation.value?.finish()
        await store.finish()
    }

    func makeDirectoryLoadFailureRetryFixture() -> DirectoryLoadFailureRetryFixture {
        let homeID = ContentTabID()
        let directoryID = ContentTabID()
        let directoryPath = "/Users/test/Desktop"
        let staleEntry = EntryModel.temporaryFolder(id: "\(directoryPath)/Stale", name: "Stale")
        let gate = DirectoryLoadSuspensionGate()
        let loadPaths = LockIsolated<[String]>([])
        let eventContinuation = LockIsolated<AsyncStream<FileChangeGatewayEventBatch>.Continuation?>(nil)
        var state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [.init(id: directoryID, anchorPath: directoryPath, savedPath: directoryPath)],
        )
        state.tabContentStates[directoryID]?.entryViewLayout.entries = [staleEntry]
        state.tabContentStates[directoryID]?.entryViewLayout.entryOperations.items = [staleEntry]

        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return try await gate.wait()
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in eventContinuation.setValue(continuation) }
            }
        }
        // store.exhaustivity = .off: tab handoff 부수 action보다 VOY-578 failure/snapshot lifecycle에 집중함
        store.exhaustivity = .off
        return DirectoryLoadFailureRetryFixture(
            homeID: homeID,
            directoryID: directoryID,
            directoryPath: directoryPath,
            staleEntry: staleEntry,
            gate: gate,
            loadPaths: loadPaths,
            eventContinuation: eventContinuation,
            store: store,
        )
    }

    func assertSuccessfulEmptyDirectorySnapshot(
        _ fixture: DirectoryLoadFailureRetryFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) {
        XCTAssertEqual(fixture.loadPaths.value, [fixture.directoryPath, fixture.directoryPath])
        XCTAssertTrue(store.state.content.entryViewLayout.entries.isEmpty)
    }

    func makeDirtyCollectionContent() -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = CollectionContext(
            query: "current",
            scopes: ["/tmp"],
            conditions: [],
        )
        content.collection.collectionSession.metadata.baseline = .init(
            context: CollectionContext(
                query: "baseline",
                scopes: ["/tmp"],
                conditions: [],
            ),
        )
        return content
    }

    func makeSaveCompletion() -> CollectionSaveCompletion {
        CollectionSaveCompletion(
            url: URL(fileURLWithPath: "/tmp/test.voycoll"),
            file: VoyagerCollectionFile(
                id: "test-id",
                name: "test",
                createdAt: Date(timeIntervalSince1970: 1_234_567_890),
                updatedAt: Date(timeIntervalSince1970: 1_234_567_890),
                query: "",
                scopes: [],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
            savedContext: nil,
        )
    }

    struct DirectoryHandoffFixture {
        let id: ContentTabID
        let anchorPath: String
        let savedPath: String?
    }

    func makeInFlightDirectoryLifecycleStore(
        homeID: ContentTabID,
        directoryID: ContentTabID,
        firstPath: String,
        gate: DirectoryLoadSuspensionGate,
        loadPaths: LockIsolated<[String]>,
    ) throws -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let firstEntry = EntryModel.temporaryFolder(id: "\(firstPath)/First", name: "First")
        var state = makeDirectoryHandoffState(
            homeID: homeID,
            tabs: [.init(id: directoryID, anchorPath: firstPath, savedPath: firstPath)],
        )
        state.contentTabs.activeTabID = directoryID
        state.content = try XCTUnwrap(state.tabContentStates[directoryID])
        state.content.entryViewLayout.entries = [firstEntry]
        state.content.entryViewLayout.entryOperations.items = [firstEntry]
        state.tabContentStates[directoryID] = state.content

        return TestStore(initialState: state) { FileManagerFeature() } withDependencies: { dependencies in
            dependencies.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            dependencies.entryLoadingClient.loadItems = { url, _ in
                let requestIndex = loadPaths.withValue { paths in
                    paths.append(url.path)
                    return paths.count
                }
                return requestIndex == 1 ? try await gate.wait() : []
            }
            dependencies.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in continuation.finish() }
            }
        }
    }

    func makeDirectoryHandoffState(
        homeID: ContentTabID,
        tabs fixtures: [DirectoryHandoffFixture],
    ) -> FileManagerFeature.State {
        var homeContent = FileManagerContentFeature.State()
        homeContent.navigation.navigationState = .home
        var tabs: IdentifiedArrayOf<ContentTabItem> = [
            ContentTabItem(
                id: homeID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
        ]
        var snapshots = [homeID: homeContent]
        for fixture in fixtures {
            tabs.append(ContentTabItem(
                id: fixture.id,
                page: .directory,
                anchor: .directory(path: fixture.anchorPath),
                isPinned: false,
                title: URL(fileURLWithPath: fixture.anchorPath).lastPathComponent,
                iconName: "folder",
            ))
            if let savedPath = fixture.savedPath {
                var content = FileManagerContentFeature.State()
                content.navigation.seedInitialFolderPath(savedPath)
                snapshots[fixture.id] = content
            }
        }
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(tabs: tabs, activeTabID: homeID, recentlyClosed: nil)
        state.content = homeContent
        state.tabContentStates = snapshots
        state.syncContentTabSidebarItems()
        return state
    }

    func makeSupersedingWatcherStore(
        state: FileManagerFeature.State,
        loadPaths: LockIsolated<[String]>,
        watcherEvents: LockIsolated<[String]>,
        removedInterestIDs: LockIsolated<Set<String>>,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.loadItems = { url, _ in
                loadPaths.withValue { $0.append(url.path) }
                return []
            }
            $0.fileChangeGatewayClient.updateInterests = { interests in
                guard let root = interests.first?.roots.first else { return }
                watcherEvents.withValue { $0.append("start:\(root)") }
            }
            $0.fileChangeGatewayClient.removeInterests = { ids in
                let removedNewInterest = removedInterestIDs.withValue { removedIDs in
                    ids.map { removedIDs.insert($0).inserted }.contains(true)
                }
                if removedNewInterest {
                    watcherEvents.withValue { $0.append("stop") }
                }
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { _ in }
            }
        }
    }

    func makeRequestLock(
        sessionID: AiChatSessionID,
        requestMessages: [AiChatMessage] = [AiChatMessage(role: .user, content: "test")],
        persistenceTranscriptHistory: [AiChatMessage]? = nil,
    ) -> AiChatRequestLock {
        let modelHandle = AiModelHandle(provider: .openai, rawValue: "gpt-4.1-mini")
        let catalogRow = AiModelCatalogRow(
            handle: modelHandle,
            displayName: "GPT-4.1 Mini",
            authMethod: .apiKey,
            sortOrder: 10,
        )
        let requestID = AiChatRequestID(rawValue: UUID())
        let runID = AiChatRunID(rawValue: UUID())
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: .openai,
            model: modelHandle,
            selectedModel: AiProviderModel(
                id: modelHandle,
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                displayName: "GPT-4.1 Mini",
                providerDisplayName: "OpenAI",
                thinkingCapability: .unknown(reason: .init(message: "Not loaded")),
            ),
            selectedModelRow: catalogRow,
            sessionStatus: .active,
            promptSummary: "test",
            submittedAtMs: 0,
        )
        let request = AiChatRequest(context: requestContext, messages: requestMessages)
        return AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: modelHandle,
            selectedModelRow: catalogRow,
            assistantReplacementIndex: nil,
            persistenceTranscriptHistory: persistenceTranscriptHistory,
        )
    }

    struct PendingProviderAuthorityFixture {
        let sessionID: AiChatSessionID
        let resolutionID: UUID
        let content: FileManagerContentFeature.State
        let inspector: FileManagerInspectorFeature.State
    }

    func makePendingProviderAuthorityFixture() throws -> PendingProviderAuthorityFixture {
        let sessionID = AiChatSessionID(rawValue: UUID())
        let requestLock = makeRequestLock(sessionID: sessionID)
        let selectedModel = try XCTUnwrap(requestLock.context.selectedModel)
        let resolutionID = UUID()
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: resolutionID,
            kind: .submit,
            sessionID: sessionID,
            selectedModel: selectedModel,
            selectedRow: requestLock.selectedModelRow,
            preparedRequest: AiChatPreparedRequest(
                prompt: "test",
                messages: requestLock.request.messages,
                assistantReplacementIndex: nil,
                historyTruncation: AiChatHistoryTruncationMetadata(
                    includedMessageCount: requestLock.request.messages.count,
                    excludedMessageCount: 0,
                    budget: 24000,
                    truncationReason: nil,
                ),
            ),
        )
        var content = FileManagerContentFeature.State()
        content.aiChat.sessionID = sessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.pendingRequestStart = pendingRequest
        content.aiChat.modelListState = .loaded([selectedModel])
        content.aiChat.modelListPendingProviders = [.openai]
        content.aiChat.selectedModelHandle = selectedModel.id
        content.aiChat.providerConnectionSnapshot = .known([.openai])
        var inspector = FileManagerInspectorFeature.State()
        inspector.aiChat.pendingRequestStart = pendingRequest
        inspector.aiChat.modelListFailedProviders = [.openai: .init(message: "Stale OpenAI listing failure")]
        inspector.aiChat.providerConnectionSnapshot = .known([.openai])
        return PendingProviderAuthorityFixture(
            sessionID: sessionID,
            resolutionID: resolutionID,
            content: content,
            inspector: inspector,
        )
    }

    func makePendingAiChatTabState(
        aiChatTabID: ContentTabID,
        homeTabID: ContentTabID,
        fixture: PendingProviderAuthorityFixture,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: aiChatTabID,
                    page: .aiChat,
                    anchor: .aiChat(sessionID: fixture.sessionID.rawValue.uuidString),
                    isPinned: false,
                    title: "AI Chat",
                    iconName: "message",
                ),
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: aiChatTabID,
            recentlyClosed: nil,
        )
        state.content = fixture.content
        state.tabContentStates = [homeTabID: FileManagerContentFeature.State()]
        state.syncContentTabSidebarItems()
        return state
    }

    func makePendingCanonicalInspectorState(
        tabID: ContentTabID,
        fixture: PendingProviderAuthorityFixture,
        inspectorVisible: Bool,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.inspector = fixture.inspector
        state.inspector.inspectorVisible = inspectorVisible
        state.inspector.inspectorPaneExists = true
        state.inspector.activeMode = .chat
        state.syncActiveTabInspectorState()
        state.syncContentTabSidebarItems()
        return state
    }

    func makeInspectorProviderAuthorityState(
        homeTabID: ContentTabID,
        directoryTabID: ContentTabID,
        inactiveFixture: PendingProviderAuthorityFixture,
        backgroundFixture: PendingProviderAuthorityFixture,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: homeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: directoryTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Documents"),
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeTabID,
            recentlyClosed: nil,
        )
        state.tabInspectorStates[directoryTabID] = inactiveFixture.inspector
        state.backgroundInspectorAiChatStates[backgroundFixture.sessionID] = backgroundFixture.inspector
        state.syncContentTabSidebarItems()
        return state
    }

    func assertDormantProviderAuthorityUnchanged(
        state: FileManagerFeature.State,
        contentTabID: ContentTabID,
        inspectorTabID: ContentTabID,
        contentSessionID: AiChatSessionID,
        inspectorSessionID: AiChatSessionID,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let expectedSnapshot = AiChatProviderConnectionSnapshot.known([.openai])
        let dormantStates = [
            state.tabContentStates[contentTabID]?.aiChat,
            state.tabInspectorStates[inspectorTabID]?.aiChat,
            state.backgroundAiChatStates[contentSessionID]?.aiChat,
            state.backgroundInspectorAiChatStates[inspectorSessionID]?.aiChat,
        ]
        for dormantState in dormantStates {
            XCTAssertEqual(dormantState?.providerConnectionSnapshot, expectedSnapshot, file: file, line: line)
            XCTAssertNil(dormantState?.modelListRequestID, file: file, line: line)
        }
    }

    func makeTestStore(
        state: FileManagerFeature.State,
        alertChoice: CollectionNavigationChoice? = nil,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.continuousClock = ContinuousClock()
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { alertChoice ?? .save },
                showCollectionOpenErrorAlert: { _, _ in },
            )
        }
        // 통합 window reducer 테스트는 close 요청이 content/sidebar child action을 함께 방출하므로
        // 각 시나리오에서 검증하는 핵심 상태 변화만 명시적으로 확인한다.
        store.exhaustivity = .off
        return store
    }
}

private struct BackgroundContentStatusFixture {
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>
    let ownerSessionID: AiChatSessionID
    let ownerLock: AiChatRequestLock
    let signal: AiChatExecutionActivitySignal
    let visibleTabID: ContentTabID
    let parkedTabID: ContentTabID
    let visibleContent: FileManagerContentFeature.State
    let parkedContent: FileManagerContentFeature.State
    let savedSnapshots: LockIsolated<[AiChatSessionSnapshot]>
}

private struct BackgroundInspectorStatusFixture {
    let store: TestStore<FileManagerFeature.State, FileManagerWindowAction>
    let ownerSessionID: AiChatSessionID
    let ownerLock: AiChatRequestLock
    let signal: AiChatExecutionActivitySignal
    let parkedTabID: ContentTabID
    let activeInspector: FileManagerInspectorFeature.State
    let parkedInspector: FileManagerInspectorFeature.State
    let content: FileManagerContentFeature.State
}

@MainActor
private extension CTM005IndependentContentTabSessionTests {
    func makeBackgroundContentStatusFixture() -> BackgroundContentStatusFixture {
        let ownerSessionID = AiChatSessionID(rawValue: UUID())
        let visibleSessionID = AiChatSessionID(rawValue: UUID())
        let parkedSessionID = AiChatSessionID(rawValue: UUID())
        let ownerLock = makeRequestLock(sessionID: ownerSessionID)
        let visibleLock = makeRequestLock(sessionID: visibleSessionID)
        let parkedLock = makeRequestLock(sessionID: parkedSessionID)
        let visibleTabID = ContentTabID()
        let parkedTabID = ContentTabID()
        let signal = makeStatusSignal(id: "background-content-search", kind: .searching)
        let visibleContent = makeStatusContent(
            sessionID: visibleSessionID,
            lock: visibleLock,
            transcript: "Visible transcript",
            draft: "Visible draft",
            autoScrollVersion: 7,
        )
        let parkedContent = makeStatusContent(
            sessionID: parkedSessionID,
            lock: parkedLock,
            transcript: "Parked transcript",
        )
        let backgroundContent = makeStatusContent(
            sessionID: ownerSessionID,
            lock: ownerLock,
            transcript: "Background prompt",
            role: .user,
        )
        let state = makeBackgroundContentStatusState(
            visibleTabID: visibleTabID,
            parkedTabID: parkedTabID,
            visibleContent: visibleContent,
            parkedContent: parkedContent,
            backgroundContent: backgroundContent,
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let store = makeBackgroundContentStatusStore(state: state, savedSnapshots: savedSnapshots)
        return BackgroundContentStatusFixture(
            store: store,
            ownerSessionID: ownerSessionID,
            ownerLock: ownerLock,
            signal: signal,
            visibleTabID: visibleTabID,
            parkedTabID: parkedTabID,
            visibleContent: visibleContent,
            parkedContent: parkedContent,
            savedSnapshots: savedSnapshots,
        )
    }

    func makeBackgroundInspectorStatusFixture() -> BackgroundInspectorStatusFixture {
        let ownerSessionID = AiChatSessionID(rawValue: UUID())
        let activeSessionID = AiChatSessionID(rawValue: UUID())
        let parkedSessionID = AiChatSessionID(rawValue: UUID())
        let ownerLock = makeRequestLock(sessionID: ownerSessionID)
        let activeLock = makeRequestLock(sessionID: activeSessionID)
        let parkedLock = makeRequestLock(sessionID: parkedSessionID)
        let parkedTabID = ContentTabID()
        let activeInspector = makeStatusInspector(
            sessionID: activeSessionID,
            lock: activeLock,
            transcript: "Active inspector",
            draft: "Active draft",
            autoScrollVersion: 3,
        )
        let parkedInspector = makeStatusInspector(
            sessionID: parkedSessionID,
            lock: parkedLock,
            transcript: "Parked inspector",
        )
        let backgroundInspector = makeStatusInspector(
            sessionID: ownerSessionID,
            lock: ownerLock,
            transcript: "Background inspector prompt",
            role: .user,
        )
        let content = makeStatusVisibleContent()
        let state = makeBackgroundInspectorStatusState(
            parkedTabID: parkedTabID,
            activeInspector: activeInspector,
            parkedInspector: parkedInspector,
            backgroundInspector: backgroundInspector,
            content: content,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() }
        // store.exhaustivity = .off: background inspector 전용 route의 owner 격리 결과만 집중 검증함
        store.exhaustivity = .off
        return BackgroundInspectorStatusFixture(
            store: store,
            ownerSessionID: ownerSessionID,
            ownerLock: ownerLock,
            signal: makeStatusSignal(id: "background-inspector-tool", kind: .toolExecution),
            parkedTabID: parkedTabID,
            activeInspector: activeInspector,
            parkedInspector: parkedInspector,
            content: content,
        )
    }

    private func makeStatusContent(
        sessionID: AiChatSessionID,
        lock: AiChatRequestLock,
        transcript: String,
        role: AiChatMessageRole = .assistant,
        draft: String? = nil,
        autoScrollVersion: Int = 0,
    ) -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .aiChat(sessionID.rawValue.uuidString)
        content.aiChat.sessionID = sessionID
        content.aiChat.sessionStatus = .active
        content.aiChat.executionPhase = .processing(lock)
        content.aiChat.transcriptHistory = [AiChatMessage(role: role, content: transcript)]
        content.aiChat.streamingAssistantDraft = draft
        content.aiChat.transcriptAutoScrollVersion = autoScrollVersion
        return content
    }

    private func makeStatusInspector(
        sessionID: AiChatSessionID,
        lock: AiChatRequestLock,
        transcript: String,
        role: AiChatMessageRole = .assistant,
        draft: String? = nil,
        autoScrollVersion: Int = 0,
    ) -> FileManagerInspectorFeature.State {
        var inspector = FileManagerInspectorFeature.State()
        inspector.inspectorVisible = true
        inspector.activeMode = .chat
        inspector.aiChat.sessionID = sessionID
        inspector.aiChat.sessionStatus = .active
        inspector.aiChat.executionPhase = .processing(lock)
        inspector.aiChat.transcriptHistory = [AiChatMessage(role: role, content: transcript)]
        inspector.aiChat.streamingAssistantDraft = draft
        inspector.aiChat.transcriptAutoScrollVersion = autoScrollVersion
        return inspector
    }

    private func makeBackgroundContentStatusState(
        visibleTabID: ContentTabID,
        parkedTabID: ContentTabID,
        visibleContent: FileManagerContentFeature.State,
        parkedContent: FileManagerContentFeature.State,
        backgroundContent: FileManagerContentFeature.State,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                makeStatusTab(id: visibleTabID, content: visibleContent, title: "Visible chat"),
                makeStatusTab(id: parkedTabID, content: parkedContent, title: "Parked chat"),
            ],
            activeTabID: visibleTabID,
        )
        state.content = visibleContent
        state.tabContentStates[parkedTabID] = parkedContent
        if let ownerSessionID = backgroundContent.aiChat.sessionID {
            state.backgroundAiChatStates[ownerSessionID] = backgroundContent
        }
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeBackgroundInspectorStatusState(
        parkedTabID: ContentTabID,
        activeInspector: FileManagerInspectorFeature.State,
        parkedInspector: FileManagerInspectorFeature.State,
        backgroundInspector: FileManagerInspectorFeature.State,
        content: FileManagerContentFeature.State,
    ) -> FileManagerFeature.State {
        let activeTabID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: activeTabID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: parkedTabID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Parked"),
                    isPinned: false,
                    title: "Parked",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeTabID,
        )
        state.content = content
        state.inspector = activeInspector
        state.tabInspectorStates[parkedTabID] = parkedInspector.tabSnapshot()
        if let ownerSessionID = backgroundInspector.aiChat.sessionID {
            state.backgroundInspectorAiChatStates[ownerSessionID] = backgroundInspector.tabSnapshot()
        }
        state.syncContentTabSidebarItems()
        return state
    }

    private func makeBackgroundContentStatusStore(
        state: FileManagerFeature.State,
        savedSnapshots: LockIsolated<[AiChatSessionSnapshot]>,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: window routing의 owner 선택 결과와 비가시 상태 불변만 집중 검증함
        store.exhaustivity = .off
        return store
    }

    private func makeStatusTab(
        id: ContentTabID,
        content: FileManagerContentFeature.State,
        title: String,
    ) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .aiChat,
            anchor: .aiChat(sessionID: content.aiChat.sessionID?.rawValue.uuidString ?? ""),
            isPinned: false,
            title: title,
            iconName: "message",
        )
    }

    private func makeStatusVisibleContent() -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.navigation.navigationState = .home
        content.aiChat.transcriptHistory = [AiChatMessage(role: .assistant, content: "Visible content")]
        return content
    }

    private func makeStatusSignal(
        id: String,
        kind: AiChatExecutionActivityKind,
    ) -> AiChatExecutionActivitySignal {
        AiChatExecutionActivitySignal(
            activityID: AiChatExecutionActivityID(rawValue: id),
            kind: kind,
            phase: .began,
            evidence: .init(origin: .providerWire, providerEventType: "test.filemanager.status"),
        )
    }

    private func mismatchedStatusContexts(for lock: AiChatRequestLock) -> [AiChatRequestContextSnapshot] {
        [
            replacingStatusIdentity(
                in: lock.context,
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: lock.requestID,
                runID: lock.runID,
            ),
            replacingStatusIdentity(
                in: lock.context,
                sessionID: lock.context.sessionID,
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: lock.runID,
            ),
            replacingStatusIdentity(
                in: lock.context,
                sessionID: lock.context.sessionID,
                requestID: lock.requestID,
                runID: AiChatRunID(rawValue: UUID()),
            ),
        ]
    }

    private func replacingStatusIdentity(
        in context: AiChatRequestContextSnapshot,
        sessionID: AiChatSessionID?,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
    ) -> AiChatRequestContextSnapshot {
        AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: context.provider,
            model: context.model,
            selectedModel: context.selectedModel,
            selectedModelRow: context.selectedModelRow,
            selectedThinking: context.selectedThinking,
            sessionStatus: context.sessionStatus,
            requestContext: context.requestContext,
            promptSummary: context.promptSummary,
            submittedAtMs: context.submittedAtMs,
        )
    }
}

private extension AiChatFeature.State {
    mutating func applyDeletedSessionExpectation(sessionID deletedSessionID: AiChatSessionID) {
        pendingEmptyDraftDeletionSessionIDs.remove(deletedSessionID)
        sessionList.removeRow(sessionID: deletedSessionID)
        if restoreSessionID == deletedSessionID {
            restoreSessionID = nil
            restoreOutcome = nil
            restoreFailure = nil
        }
        if sessionID == deletedSessionID {
            sessionID = nil
            sessionStatus = .idle
            currentSessionCustomTitle = nil
            transcriptHistory = []
            draftText = ""
            streamingAssistantDraft = nil
            lockedModelHandle = nil
            lastExecutionFailure = nil
            lastRequestContext = nil
            lastRequestContextModelHandle = nil
            addedAttachments = []
            currentContextFolderStructureModes = [:]
            pendingRequestStart = nil
            executionPhase = .idle
            selectedModelHandle = nil
            selectedThinking = nil
            unavailableSelectedModelHandle = nil
        }
        backgroundPendingRequestStarts = backgroundPendingRequestStarts.filter { _, pendingRequestStart in
            pendingRequestStart.sessionID != deletedSessionID
        }
        backgroundExecutionPhases = backgroundExecutionPhases.filter { _, phase in
            phase.lock?.context.sessionID != deletedSessionID
        }
    }
}
