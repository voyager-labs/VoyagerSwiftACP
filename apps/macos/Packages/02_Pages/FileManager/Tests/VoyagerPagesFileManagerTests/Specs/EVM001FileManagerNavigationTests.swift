import ComposableArchitecture
import CoreServices
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EVM001FileManagerNavigationTests: XCTestCase {
    // MARK: - EVM-001-reload_directory_page_on_external_change

    /// EVM-001-reload_directory_page_on_external_change: folder 내부 child path 변경 시 reload
    /// 현재 folder 경로 하위의 file 또는 nested child path가 외부에서 변경되면 현재 폴더를 reload하는지 검증.
    /// - 검증 내용: folder route에서 child path 변경을 event path와 affected parent로 전달하고 loadItems 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), showHiddenFiles == true
    /// - 기대 결과: removed prefix 없이 hierarchy invalidation 후 entryOperations.loading.loadItems 수신
    func testExternalFolderChildChangeReloadsCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(folderPath)/11.txt"
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedPath = URL(fileURLWithPath: changedPath).standardizedFileURL.resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        state.entryViewLayout.showHiddenFiles = true
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 자체 변경 시 child cache reload
    /// folder path 자체에 modified/rescan event가 발생해도 해당 folder hierarchy cache를 갱신하는지 검증한다.
    /// - 검증 내용: changed folder path와 parent path를 hierarchy invalidation에 함께 전달
    /// - 사전 조건: 현재 directory 아래 expanded folder path에 non-deletion event가 발생함
    /// - 기대 결과: removed prefix 없이 folder path와 parent path가 affectedPaths에 포함됨
    func testExternalExpandedFolderChangeInvalidatesFolderAndParent() async {
        let folderPath = Self.fixtureDir("texts")
        let changedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalChangedFolderPath = URL(fileURLWithPath: changedFolderPath).standardizedFileURL
            .resolvingSymlinksInPath().path
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedFolderPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) = action
            else { return false }
            return affectedPaths == [canonicalChangedFolderPath, canonicalFolderPath] && removedPrefixes.isEmpty
        }
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: expanded folder 외부 삭제·rename 시 hierarchy identity 제거
    /// watcher의 remove·rename event가 parent reload뿐 아니라 사라진 folder cache prefix도 전달하는지 검증한다.
    /// - 검증 내용: identity 변경 path의 parent affected path와 removed prefix 분리
    /// - 사전 조건: 현재 directory 아래 expanded folder에 remove 또는 rename event가 발생함
    /// - 기대 결과: 두 event 모두 folder path를 removedPrefixes로 전달함
    func testExternalExpandedFolderRemovalOrRenameEvictsHierarchyPrefix() async {
        let folderPath = Self.fixtureDir("texts")
        let removedFolderPath = Self.fixtureDir("texts/plain")
        let canonicalFolderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalRemovedPath = URL(fileURLWithPath: removedFolderPath).standardizedFileURL.resolvingSymlinksInPath()
            .path
        let identityChangeFlags = [
            UInt32(kFSEventStreamEventFlagItemRemoved),
            UInt32(kFSEventStreamEventFlagItemRenamed),
        ]

        for flags in identityChangeFlags {
            var state = FileManagerContentState()
            state.navigation.navigationState = .folder(folderPath)
            let store = makeStore(initialState: state)

            await store.send(.externalFileSystemChanged(Self.externalChangeEvents([removedFolderPath], flags: flags)))
            await store.receive { action in
                guard case let .entryViewLayout(.hierarchy(.hierarchyInvalidated(affectedPaths, removedPrefixes))) =
                    action
                else { return false }
                return affectedPaths == [canonicalRemovedPath, canonicalFolderPath]
                    && removedPrefixes == [canonicalRemovedPath]
            }
            await store.receive { action in
                guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
                return true
            }
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: 관련 없는 folder 외부 변경 시 reload 안 함
    /// 현재 폴더와 관련 없는 경로의 외부 변경은 reload를 트리거하지 않는지 검증.
    /// - 검증 내용: sibling 경로 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain)
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalSiblingChangeDoesNotReloadCurrentFolder() async {
        let folderPath = Self.fixtureDir("texts/plain")
        let unrelatedPath = Self.fixturePath("images/jpeg/hopper.jpg")
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(folderPath)
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([unrelatedPath])))
    }

    /// EVM-001-reload_directory_page_on_external_change: Recents route에서 route loader refresh
    /// Recents route에서 외부 변경 감지 시 recents 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: recents route에서 externalFileSystemChanged 전송 시 loadRecentItems 수신
    /// - 사전 조건: navigationState == .recents, showHiddenFiles == true
    /// - 기대 결과: entryOperations.loading.loadRecentItems 액션 수신
    func testExternalChangeReloadsRecentsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .recents
        state.entryViewLayout.showHiddenFiles = true
        state.entryViewLayout.entryArrangements.sortKey = .kind
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadRecentItems(showHidden, priority)))) =
                action else { return false }
            return showHidden && priority == .active([.spotlight])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Tags route에서 route loader refresh
    /// Tags route에서 외부 변경 감지 시 tags 전용 loader만 refresh하는지 검증.
    /// - 검증 내용: tags route에서 externalFileSystemChanged 전송 시 loadTagItems 수신
    /// - 사전 조건: navigationState == .tags("Work")
    /// - 기대 결과: entryOperations.loading.loadTagItems 액션 수신
    func testExternalChangeReloadsTagsRoute() async {
        let changedPath = Self.fixturePath("texts/plain/11.txt")
        var state = FileManagerContentState()
        state.navigation.navigationState = .tags("Work")
        state.entryViewLayout.entryArrangements.groupKey = .tags
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([changedPath])))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadTagItems(
                tagName,
                showHidden,
                priority,
            )))) = action else { return false }
            return tagName == "Work" && !showHidden && priority == .active([.tags])
        }
    }

    /// EVM-001-reload_directory_page_on_external_change: Collection route에서 directory reload로 contents 대체하지 않음
    /// Collection route에서 collection document path의 외부 변경이 directory reload로 collection contents를 대체하지 않는지 검증.
    /// - 검증 내용: collection route에서 collectionURL path 및 metadata.json path 변경 시 어떤 load 액션도 수신하지 않음
    /// - 사전 조건: navigationState == .collection, collectionSession.document 설정됨
    /// - 기대 결과: externalFileSystemChanged 전송 후 수신 액션 없음
    func testExternalChangeIgnoresOpenedCollectionDocumentPath() async {
        let collectionURL = URL(fileURLWithPath: Self.fixturePath("data/sample-config.yaml"))
        var state = FileManagerContentState()
        state.navigation.navigationState = .collection(.init(
            kind: .file(url: collectionURL, name: "sample-config"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.collection.collectionSession.document = .init(url: collectionURL, name: "sample-config")
        let store = makeStore(initialState: state)

        await store.send(.externalFileSystemChanged(Self.externalChangeEvents([
            collectionURL.path,
            collectionURL.appendingPathComponent("metadata.json").path,
        ])))
    }

    /// EVM-001-reload_directory_page_on_external_change: folder 이동 시 watcher 시작 및 외부 변경 전달
    /// folder navigation 시 directory watcher가 시작되고, 외부 변경 사항이 externalFileSystemChanged로 전달되는지 검증.
    /// - 검증 내용: applyNavigationState(.folder) 전송 시 watcher 시작, clearCollectionPresentation, loadItems,
    /// externalFileSystemChanged 수신
    /// - 사전 조건: navigationState == .folder(fixtures/fixtures/texts/plain), custom fileChangeGatewayClient
    /// - 기대 결과: watcher가 changedPath를 yield하고 externalFileSystemChanged로 전달
    func testFolderNavigationStartsWatcherAndForwardsExternalChanges() async {
        let currentPath = Self.fixtureDir("texts/plain")
        let changedPath = "\(currentPath)/11.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder(currentPath)
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [[currentPath]])
                XCTAssertEqual(interests.map(\.purpose), [.visibleFolderReload])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(changedEvents)
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.folder(currentPath))))
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.loading(.loadItems))) = action else { return false }
            return true
        }
        await store.receive(\.externalFileSystemChanged, changedEvents)
    }

    /// EVM-001-reload_directory_page_on_external_change: collection 이동 시 scope watcher 시작 및 외부 변경 전달
    /// Collection route 진입 시 `.voycoll` 위치가 아닌 collection scope 절대경로만 감시하고 변경을 전달하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection) 전송 시 FileChangeGateway interest 등록, externalFileSystemChanged 수신
    /// - 사전 조건: collectionContext.scopes에 중복/상대 경로가 섞여 있음
    /// - 기대 결과: canonical absolute scope만 감시하고 changedPath를 전달
    func testCollectionScopeRootsChangedSinceSnapshotDetectsNewerRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: root.path,
        )
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: CollectionSnapshotMeta(
                definitionFingerprint: "fingerprint",
                capturedAt: Date(timeIntervalSince1970: 100),
                itemCount: 0,
                relevanceRoots: [root.path],
            ),
            appVersion: nil,
        )

        XCTAssertTrue(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionScopeRootsChangedSinceSnapshotIgnoresMissingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-scope-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = VoyagerCollectionFile(
            id: UUID().uuidString,
            name: "demo",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            query: "",
            scopes: [root.path],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        XCTAssertFalse(collectionScopeRootsChangedSinceSnapshot(file))
    }

    func testCollectionNavigationStartsScopeWatcherAndForwardsExternalChanges() async {
        let firstScope = "/tmp/voyager/scope-a"
        let secondScope = "/tmp/voyager/scope-b/../scope-b"
        let changedPath = "/tmp/voyager/scope-a/changed.txt"
        let changedEvents = Self.externalChangeEvents(
            [changedPath],
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(
            query: "",
            scopes: [firstScope, "relative", secondScope, firstScope],
            conditions: [],
        )
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [["/tmp/voyager/scope-a", "/tmp/voyager/scope-b"]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield(changedEvents)
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
        await store.receive(\.externalFileSystemChanged, changedEvents)
    }

    func testCollectionNavigationIgnoresMetadataOnlyScopeEvents() async {
        let scope = "/tmp/voyager/scope-a"
        let changedPath = "/tmp/voyager/scope-a/opened.txt"
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/demo.voycoll")
        let context = CollectionContext(query: "", scopes: [scope], conditions: [])
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "demo"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.collection.collectionContext = context
        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        } withDependencies: {
            $0.fileChangeGatewayClient.updateInterests = { interests in
                XCTAssertEqual(interests.map(\.roots), [[scope]])
                XCTAssertEqual(interests.map(\.purpose), [.collectionStale])
            }
            $0.fileChangeGatewayClient.observeEvents = {
                AsyncStream { continuation in
                    continuation.yield([
                        FileChangeGatewayEvent(
                            path: changedPath,
                            flags: UInt32(kFSEventStreamEventFlagItemXattrMod),
                        ),
                    ])
                    continuation.finish()
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = "collection:\(collectionURL.standardizedFileURL.path)"
        }
    }

    /// EVM-001-navigate_pages: collection navigation도 scroll position key를 저장/복원
    /// Collection route 진입 시 saved collection URL 기반 key로 currentPath와 savedScrollOffset을 주입하는지 검증.
    /// - 검증 내용: applyNavigationState(.collection(.file)) 전송 시 entryViewLayout.currentPath와 savedScrollOffset 동기화
    /// - 사전 조건: scrollPositions에 saved collection URL 기반 key가 저장됨
    /// - 기대 결과: collection 진입 후 list/grid coordinator가 같은 key로 scroll offset을 복원할 수 있음
    func testCollectionNavigationRestoresSavedScrollOffset() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 240)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.navigation.scrollPositions[scrollKey] = savedOffset

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState))) {
            $0.entryViewLayout.currentPath = scrollKey
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-navigate_pages: collection scroll offset 저장은 현재 collection key에 즉시 반영
    /// EntryViewLayout delegate가 저장한 collection scroll offset이 현재 route의 savedScrollOffset과 scrollPositions에 동기화되는지 검증.
    /// - 검증 내용: saveScrollOffset(offset, forPath: collectionKey) 전송 시 scrollPositions와 savedScrollOffset 갱신
    /// - 사전 조건: navigationState == .collection(.file), entryViewLayout.currentPath == collection URL 기반 key
    /// - 기대 결과: collection에서 다른 route로 이동 후 돌아왔을 때 같은 offset을 복원할 수 있음
    func testCollectionNavigationSavesScrollOffsetForCurrentCollectionKey() async {
        let collectionURL = URL(fileURLWithPath: "/tmp/voyager/collections/saved.voycoll")
        let scrollKey = "collection:\(collectionURL.standardizedFileURL.path)"
        let savedOffset = CGPoint(x: 0, y: 480)
        let navigationState = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: collectionURL, name: "saved"),
            context: CollectionContext(query: "", scopes: [], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        var state = FileManagerContentState()
        state.navigation.navigationState = navigationState
        state.entryViewLayout.currentPath = scrollKey

        let store = TestStore(initialState: state) {
            FileManagerContentNavigationBridgeReducer()
        }

        await store.send(.internal(.saveScrollOffset(savedOffset, forPath: scrollKey))) {
            $0.navigation.scrollPositions[scrollKey] = savedOffset
            $0.entryViewLayout.savedScrollOffset = savedOffset
        }
    }

    /// EVM-001-home_navigation_clears_hidden_entries: Home route 적용 시 숨은 folder selection 정리
    /// Home 화면 진입 후에도 이전 folder entry/selection이 메뉴 command projection에 남지 않도록 검증.
    /// - 검증 내용: applyNavigationState(.home)이 selection·entry list를 비우고 이전 generation batch를 무시함
    /// - 사전 조건: generation 1의 folder load와 선택된 entry가 남아 있는 상태
    /// - 기대 결과: generation을 무효화하고 Home 전환 뒤 도착한 generation 1 batch를 반영하지 않음
    func testHomeNavigationClearsHiddenEntrySelectionAndItems() async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-hidden-selection",
            name: "voyager-hidden-selection",
        )
        let staleEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-stale-root-batch",
            name: "voyager-stale-root-batch",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]
        state.entryViewLayout.entryOperations.loadingContext.generation = 1
        state.entryViewLayout.entryOperations.loadingContext.sourceKind = .directory
        state.entryViewLayout.entryOperations.isLoading = true

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(.home)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.finish()

        await store.send(.entryViewLayout(.entryOperations(.loading(.streamEvent(.init(
            generation: 1,
            event: .coreBatch(items: [staleEntry], batchIndex: 0),
        ))))))

        XCTAssertEqual(store.state.entryViewLayout.currentPath, "Home")
        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
        XCTAssertEqual(store.state.entryViewLayout.entryOperations.loadingContext.generation, 2)
        XCTAssertNil(store.state.entryViewLayout.entryOperations.loadingContext.sourceKind)
    }

    /// EVM-001-ai_chat_navigation_clears_hidden_entries: AI Chat route 적용 시 숨은 folder selection 정리
    /// AI Chat 화면 진입 후에도 이전 folder entry/selection이 command projection에 남지 않도록 검증.
    func testAiChatNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChat(Self.aiChatRouteSessionID))
    }

    /// EVM-001-ai_chat_sessions_navigation_clears_hidden_entries: AI Chat History route 적용 시 숨은 folder selection 정리
    /// AI Chat History 화면도 파일 command와 분리되어야 하므로 이전 entry projection을 비움.
    func testAiChatSessionsNavigationClearsHiddenEntrySelectionAndItems() async {
        await assertAiChatNavigationClearsHiddenEntrySelectionAndItems(.aiChatSessions(Self.aiChatRouteSessionID))
    }

    private static let aiChatRouteSessionID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

    private func assertAiChatNavigationClearsHiddenEntrySelectionAndItems(
        _ navigationState: ContentPageNavigationRoute,
    ) async {
        let previousEntry = EntryModel.temporaryFolder(
            id: "/tmp/voyager-ai-chat-hidden-selection",
            name: "voyager-ai-chat-hidden-selection",
        )
        var state = FileManagerContentState()
        state.navigation.navigationState = .folder("/tmp")
        state.entryViewLayout.entries = [previousEntry]
        state.entryViewLayout.selectedIds = [previousEntry.id]
        state.entryViewLayout.lastSelectedId = previousEntry.id
        state.entryViewLayout.rangeAnchorId = previousEntry.id
        state.entryViewLayout.entryOperations.loadingContext.items = [previousEntry]

        let store = TestStore(initialState: state) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.internal(.applyNavigationState(navigationState)))
        await store.receive(\.entryViewLayout.entryOperations.loading.cancelAndClearItems)
        await store.receive(\.entryViewLayout.internal.clearCollectionPresentation)
        await store.receive(\.entryViewLayout.internal.applyClearSelection)
        await store.finish()

        XCTAssertTrue(store.state.entryViewLayout.selectedIds.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entries.isEmpty)
        XCTAssertTrue(store.state.entryViewLayout.entryOperations.loadingContext.items.isEmpty)
    }

    private func makeStore(initialState: FileManagerContentState)
        -> TestStore<FileManagerContentState, FileManagerContentAction>
    {
        TestStore(initialState: initialState) {
            FileManagerContentSyncReducer()
        }
    }

    // Fixture path helpers

    /// `fixtures/fixtures/` 하위 디렉토리의 절대 경로를 반환.
    private static func fixtureDir(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    private static func externalChangeEvents(
        _ paths: [String],
        flags: UInt32 = UInt32(kFSEventStreamEventFlagItemModified),
    ) -> [FileChangeGatewayEvent] {
        paths.map { FileChangeGatewayEvent(path: $0, flags: flags, emittedAt: .distantPast) }
    }

    /// `fixtures/fixtures/` 하위 파일의 절대 경로를 반환.
    private static func fixturePath(_ subpath: String) -> String {
        guard let root = try? resolveRepoRoot() else {
            XCTFail("Repository fixture root could not be resolved")
            return FileManager.default.temporaryDirectory.appendingPathComponent(subpath).path
        }
        return root.appendingPathComponent("fixtures/fixtures")
            .appendingPathComponent(subpath).path
    }

    /// CWD에서 위로 올라가며 repo root(`.git` 또는 `Package.swift`)를 찾고
    /// `fixtures/fixtures/` 존재를 교차 검증한다.
    /// `FixtureSandbox.resolveRepoRoot`와 동일한 탐지 정책을 사용한다.
    private static func resolveRepoRoot() throws -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)
        for _ in 0 ..< 10 {
            let hasRepoMarker = FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
                || FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
            if hasRepoMarker,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("fixtures/fixtures").path)
            {
                return url
            }
            guard let parent = url.pathComponents.count > 1 ? url.deletingLastPathComponent() : nil else { break }
            url = parent
        }
        throw FixturePathError.repoRootNotFound(searchFrom: cwd)
    }

    // MARK: - EVM-001-reload_directory_page_on_external_change

    private let reducer = FileManagerContentFeature()

    struct LifecycleBridgeHarness: @MainActor Reducer {
        // swiftlint:disable:next nesting
        struct State: Equatable {
            var content: FileManagerContentState
        }

        // swiftlint:disable:next nesting
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

    private func makeInitialState() -> LifecycleBridgeHarness.State {
        LifecycleBridgeHarness.State(content: FileManagerContentState())
    }

    private func makeInitialState(folderPath: String) -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.seedInitialFolderPath(folderPath)
        state.content.navigation.navigationState = .folder(folderPath)
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: folder route entry operation 완료 시 directory reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: folder route에서 entry operation 완료 액션이 현재 folder loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))

        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority: _,
            ))))) =
                action else { return false }
            return path == folderPath && showHidden == false
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: recents route entry operation 완료 시 recents reload forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: recents route에서 entry operation 완료 액션이 recents loader로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedTriggersContentReloadForRecents() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .recents

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .moveToTrash,
            .success(()),
        ))))

        await store.receive { action in
            guard case .forwarded(.entryViewLayout(.entryOperations(.loading(.loadRecentItems(
                showHidden: false,
                priority: _,
            ))))) =
                action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: 개별 setTags 완료는 최종 record 전에는 reload하지 않는다.
    func testSetTagsOperationFinishedDoesNotReloadBeforeFinalRecord() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .tags("Work")

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .setTags,
            .success(()),
        ))))

        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: setTags의 최종 성공 record는 일반 folder를 한 번 reload한다.
    func testSetTagsEntryActionCompletedReloadsFolderOnce() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: "/tmp/voyager/file.txt", afterPath: "/tmp/voyager/file.txt")],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.entryViewLayout(.entryOperations(.loading(.loadItems(
                path,
                showHidden,
                priority: _,
            ))))) =
                action else { return false }
            return path == folderPath && !showHidden
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags 최종 record는 성공 target만 stale 처리 후 refresh한다.
    func testSetTagsEntryActionCompletedRefreshesOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [
                .init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt"),
                .init(beforePath: "/tmp/b.txt", afterPath: "/tmp/b.txt"),
            ],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.receive { action in
            guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
            return paths == ["/tmp/a.txt", "/tmp/b.txt"]
        }
        await store.receive { action in
            guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection setTags undo/redo도 최종 성공 target만 같은 refresh seam으로
    /// 전달한다.
    func testSetTagsUndoAndRedoRefreshOnlySuccessfulCollectionTargets() async {
        let store = TestStore(initialState: makeCollectionInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off
        let record = EntryActionRecord(
            operationKind: .setTags,
            targets: [.init(beforePath: "/tmp/a.txt", afterPath: "/tmp/a.txt")],
        )

        for direction in [EntryActionDirection.undo, .redo] {
            await store.send(.bridge(.undoRedo(.entryActionApplied(direction: direction, record: record))))
            await store.receive { action in
                guard case let .forwarded(.collection(.externalPathsChanged(paths))) = action else { return false }
                return paths == ["/tmp/a.txt"]
            }
            await store.receive { action in
                guard case .forwarded(.view(.refreshStaleCollection)) = action else { return false }
                return true
            }
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route entry operation 완료 시 directory reload 차단
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 entry operation 완료가 directory loader로 전달되지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testOperationFinishedOnCollectionNavigationReturnsNone() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        ))))
        await store.finish()
    }

    private func makeCollectionInitialState() -> LifecycleBridgeHarness.State {
        var state = makeInitialState()
        state.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        state.content.entryViewLayout.isCollectionMode = true
        return state
    }

    /// EVM-001-reload_directory_page_on_external_change: empty trash 완료 시 window close delegate forwarding
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: empty trash 완료 lifecycle이 FileManager closeWindow delegate로 전달되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEmptyTrashCompletedTriggersCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.emptyTrashCompleted)))

        await store.receive { action in
            guard case .forwarded(.delegate(.closeWindow)) = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: entry action completed metrics-only lifecycle no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: entryActionCompleted lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testEntryActionCompletedReturnsNoneWithoutReload() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        let record = EntryActionRecord(
            operationKind: .rename,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/tmp/b.txt")],
        )

        await store.send(.bridge(.lifecycle(.entryActionCompleted(record))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route put back 완료 시 collection presentation restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 putBack 완료 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testPutBackEntryActionCompletedOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let restoredRecord = EntryActionRecord(
            operationKind: .putBack,
            targets: [EntryActionRecord.Target(beforePath: "/Users/me/.Trash/a.txt", afterPath: "/tmp/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.entryActionCompleted(restoredRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: collection route move-to-trash undo 시 collection presentation
    /// restore
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: collection route에서 moveToTrash undo 후 collection presentation 복구 액션이 생성되는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testUndoAppliedMoveToTrashOnCollectionNavigationRestoresCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.content.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: CollectionContext(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )
        initialState.content.entryViewLayout.isCollectionMode = true

        let trashedRecord = EntryActionRecord(
            operationKind: .moveToTrash,
            targets: [EntryActionRecord.Target(beforePath: "/tmp/a.txt", afterPath: "/Users/me/.Trash/a.txt")],
        )

        let store = TestStore(initialState: initialState) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.undoRedo(.entryActionApplied(direction: .undo, record: trashedRecord))))
        await store.receive { action in
            guard case .forwarded = action else { return false }
            return true
        }
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: loading 결과 액션 bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: itemsLoaded 액션이 FileManager content lifecycle bridge side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testLoadingItemsLoadedReturnsNone() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.loading(.itemsLoaded([]))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: windowIDChanged lifecycle bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: windowIDChanged lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testWindowIDChangedDoesNotTriggerReloadOrCloseWindow() async {
        let store = TestStore(initialState: makeInitialState()) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.windowIDChanged(UUID()))))
        await store.finish()
    }

    /// EVM-001-reload_directory_page_on_external_change: folder route pathsMutated lifecycle bridge no-op
    /// FileManager content entry operation lifecycle bridge가 navigation route별 reload/restore boundary를 지키는지 검증.
    /// - 검증 내용: folder route pathsMutated lifecycle이 reload나 closeWindow side effect를 만들지 않는지 검증
    /// - 사전 조건: FileManagerContentState와 EntryOperations lifecycle bridge harness 구성
    /// - 기대 결과: route에 맞는 forwarding 또는 no-op/restore 동작 발생
    func testPathsMutatedDoesNotTriggerReloadOrCloseWindow() async {
        let folderPath = "/tmp/voyager"
        let store = TestStore(initialState: makeInitialState(folderPath: folderPath)) {
            LifecycleBridgeHarness()
        }
        store.exhaustivity = .off

        await store.send(.bridge(.lifecycle(.pathsMutated(["/tmp/a.txt", "/tmp/b.txt"]))))
        await store.finish()
    }
}

private enum FixturePathError: Error, CustomStringConvertible {
    case repoRootNotFound(searchFrom: String)

    var description: String {
        switch self {
        case let .repoRootNotFound(searchFrom):
            "repo root not found while searching from \(searchFrom)"
        }
    }
}
