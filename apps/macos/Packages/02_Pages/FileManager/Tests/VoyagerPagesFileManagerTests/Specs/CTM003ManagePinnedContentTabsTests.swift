import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

@Reducer
private struct CTM003PinnedPersistenceHarness {
    typealias State = ContentTabState
    typealias Action = ContentTabAction

    @Dependency(\.contentTabPinnedRecordClient)
    var client
    @Dependency(\.userDefaultsClient)
    var defaults

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .pinnedRecordPersistenceRequested(request) = action else {
                return ContentTabFeature().reduce(into: &state, action: action)
            }

            let generation = client.reserveMutationGeneration(request.tabID)
            let context = ContentTabPinnedRecordTerminalContext(
                intentID: request.intentID,
                generation: generation,
            )
            let client = client
            let defaults = defaults
            return .run { send in
                do {
                    let disposition = try await client.updateStoreGuarded(generation, defaults) { store in
                        request.mutation.applying(to: store)
                    }
                    switch disposition {
                    case .applied:
                        await send(.pinnedRecordSaveSucceeded(tabID: request.tabID, context: context))
                    case .superseded:
                        await send(.pinnedRecordSaveNotApplied(
                            tabID: request.tabID,
                            context: context,
                            reason: .superseded,
                            rollback: request.rollback,
                        ))
                    }
                } catch is CancellationError {
                    await send(.pinnedRecordSaveNotApplied(
                        tabID: request.tabID,
                        context: context,
                        reason: .cancelled,
                        rollback: request.rollback,
                    ))
                } catch {
                    await send(.pinnedRecordSaveFailed(
                        tabID: request.tabID,
                        context: context,
                        rollback: request.rollback,
                    ))
                }
            }
            .cancellable(
                id: PinnedRecordPersistenceCancelID(
                    scopeID: state.pinnedRecordPersistenceScopeID,
                    tabID: request.tabID,
                ),
                cancelInFlight: true,
            )
        }
    }
}

@Reducer
struct CTM003FileManagerPersistenceHarness {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.contentTabPinnedRecordClient)
    var client
    @Dependency(\.userDefaultsClient)
    var defaults

    var body: some Reducer<State, Action> {
        FileManagerFeature()

        Reduce { _, action in
            guard case let .delegate(.pinnedRecordPersistenceRequested(routedRequest)) = action else {
                return .none
            }
            let request = routedRequest.request
            let generation = client.reserveMutationGeneration(request.tabID)
            let context = ContentTabPinnedRecordTerminalContext(
                intentID: request.intentID,
                generation: generation,
            )
            let client = client
            let defaults = defaults
            return .run { send in
                let terminal: ContentTabAction
                do {
                    let disposition = try await client.updateStoreGuarded(generation, defaults) { store in
                        request.mutation.applying(to: store)
                    }
                    switch disposition {
                    case .applied:
                        terminal = .pinnedRecordSaveSucceeded(tabID: request.tabID, context: context)
                    case .superseded:
                        terminal = .pinnedRecordSaveNotApplied(
                            tabID: request.tabID,
                            context: context,
                            reason: .superseded,
                            rollback: request.rollback,
                        )
                    }
                } catch is CancellationError {
                    terminal = .pinnedRecordSaveNotApplied(
                        tabID: request.tabID,
                        context: context,
                        reason: .cancelled,
                        rollback: request.rollback,
                    )
                } catch {
                    terminal = .pinnedRecordSaveFailed(
                        tabID: request.tabID,
                        context: context,
                        rollback: request.rollback,
                    )
                }

                switch routedRequest.route {
                case .single:
                    await send(.contentTabs(terminal))
                case let .selectedPin(operationID):
                    await send(.performSelectedContentTabPinMutation(
                        operationID: operationID,
                        tabID: request.tabID,
                        action: terminal,
                    ))
                case let .selectedClose(operationID):
                    await send(.performSelectedContentTabCloseMutation(
                        operationID: operationID,
                        tabID: request.tabID,
                        action: terminal,
                    ))
                }
            }
        }
    }
}

private final class PinnedRecordStoreRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var savedStores: [ContentTabPinnedRecordStore] = []

    func record(_ store: ContentTabPinnedRecordStore) -> Int {
        lock.lock()
        defer { lock.unlock() }
        savedStores.append(store)
        return savedStores.count
    }

    func latestStore() -> ContentTabPinnedRecordStore {
        lock.lock()
        defer { lock.unlock() }
        return savedStores.last ?? ContentTabPinnedRecordStore()
    }

    func stores() -> [ContentTabPinnedRecordStore] {
        lock.lock()
        defer { lock.unlock() }
        return savedStores
    }
}

private final class PinnedRecordDefaultsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var writes = 0

    init(store: ContentTabPinnedRecordStore) throws {
        storedData = try JSONEncoder().encode(store)
    }

    func object() -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    func setObject(_ value: Any?) {
        lock.lock()
        defer { lock.unlock() }
        storedData = value as? Data
        writes += 1
    }

    func writeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    func client() -> UserDefaultsClient {
        UserDefaultsClient(
            bool: { _ in false },
            setBool: { _, _ in },
            string: { _ in nil },
            setString: { _, _ in },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { [self] _ in object() },
            setObject: { [self] value, _ in setObject(value) },
        )
    }
}

private final class CollectionPinAlertRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var alerts: [(title: String, message: String)] = []

    func record(title: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        alerts.append((title: title, message: message))
    }

    func latestAlert() -> (title: String, message: String)? {
        lock.lock()
        defer { lock.unlock() }
        return alerts.last
    }

    func alertCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return alerts.count
    }
}

@MainActor
final class CTM003ManagePinnedContentTabsTests: XCTestCase {
    private func temporaryCollectionWindowState(tabID: ContentTabID) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .directory(path: "/Users/test/Previous"),
                isPinned: false,
                title: "Temporary Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        state.syncActiveTabContentState()
        return state
    }

    private struct DirtyPinnedCollectionFixture {
        let tabID: ContentTabID
        let state: FileManagerFeature.State
        let sourceRoute: ContentPageNavigationRoute
        let sourceAnchor: ContentTabPageAnchor
        let record: ContentTabPinnedRecord
        let dirtyContext: CollectionContext
    }

    private func makeDirtyPinnedCollectionFixture(isActive: Bool) -> DirtyPinnedCollectionFixture {
        let tabID = ContentTabID()
        let homeID = ContentTabID()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.voycoll")
        let sourceContext = CollectionContext(query: "source", scopes: ["/tmp/source"], conditions: [])
        let dirtyContext = CollectionContext(query: "dirty draft", scopes: ["/tmp/source"], conditions: [])
        let sourceAnchor: ContentTabPageAnchor = .collectionFile(url: sourceURL)
        let record = Self.pinnedRecord(
            id: tabID,
            page: .collection,
            anchor: sourceAnchor,
            title: "Source",
            iconName: "rectangle.stack",
        )
        let sourceRoute = ContentPageNavigationRoute.collection(.init(
            kind: .file(url: sourceURL, name: "Source"),
            context: sourceContext,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        let dirtyContent = makeDirtyCollectionContent(
            sourceContext: sourceContext,
            dirtyContext: dirtyContext,
            sourceRoute: sourceRoute,
        )
        var state = FileManagerFeature.State()
        state.contentTabs = makeDirtyPinnedContentTabs(
            tabID: tabID,
            homeID: homeID,
            sourceAnchor: sourceAnchor,
            record: record,
            isActive: isActive,
        )
        state.tabContentStates[tabID] = dirtyContent
        if isActive {
            state.content = dirtyContent
        } else {
            state.tabContentStates[homeID] = state.content
        }
        state.syncContentTabSidebarItems()
        return DirtyPinnedCollectionFixture(
            tabID: tabID,
            state: state,
            sourceRoute: sourceRoute,
            sourceAnchor: sourceAnchor,
            record: record,
            dirtyContext: dirtyContext,
        )
    }

    private func makeDirtyCollectionContent(
        sourceContext: CollectionContext,
        dirtyContext: CollectionContext,
        sourceRoute: ContentPageNavigationRoute,
    ) -> FileManagerContentFeature.State {
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = dirtyContext
        content.collection.collectionSession.metadata.baseline = .init(context: sourceContext)
        content.navigation.navigationState = sourceRoute
        return content
    }

    private func makeDirtyPinnedContentTabs(
        tabID: ContentTabID,
        homeID: ContentTabID,
        sourceAnchor: ContentTabPageAnchor,
        record: ContentTabPinnedRecord,
        isActive: Bool,
    ) -> ContentTabState {
        ContentTabState(
            tabs: [
                ContentTabItem(
                    id: tabID,
                    page: .collection,
                    anchor: sourceAnchor,
                    isPinned: true,
                    title: "Source",
                    iconName: "rectangle.stack",
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
            activeTabID: isActive ? tabID : homeID,
            recentlyClosed: nil,
            pinnedRecords: [tabID: record],
        )
    }

    private static let pinnedAt = Date(timeIntervalSince1970: 443)

    private static func pinnedRecord(
        id: ContentTabID,
        page: ContentTabPage = .directory,
        anchor: ContentTabPageAnchor,
        title: String? = nil,
        iconName: String? = nil,
    ) -> ContentTabPinnedRecord {
        ContentTabPinnedRecord(
            id: id.rawValue,
            page: page,
            anchor: anchor,
            title: title,
            iconName: iconName,
            pinnedAt: pinnedAt,
        )
    }

    private static func pinnedItem(
        id: ContentTabID,
        anchor: ContentTabPageAnchor,
        title: String,
    ) -> ContentTabItem {
        ContentTabItem(
            id: id,
            page: .directory,
            anchor: anchor,
            isPinned: true,
            title: title,
            iconName: "folder",
        )
    }

    private static func pinnedRuntimeNavigationMatcher(
        tabID: ContentTabID,
        path: String,
    ) -> (FileManagerWindowAction) -> Bool {
        { action in
            guard case let .delegate(.pinnedContentTabRuntimeNavigationChanged(
                tabID: receivedTabID,
                navigationState: .folder(receivedPath),
            )) = action
            else { return false }
            return receivedTabID == tabID && receivedPath == path
        }
    }

    func testPinnedRecordClient_invalidPersistedDataFallsBackToEmptyStore() throws {
        let invalidDefaults = UserDefaultsClient(
            bool: { _ in false },
            setBool: { _, _ in },
            string: { _ in nil },
            setString: { _, _ in },
            double: { _ in 0 },
            setDouble: { _, _ in },
            object: { _ in Data("not-json".utf8) },
            setObject: { _, _ in },
        )

        let store = try ContentTabPinnedRecordClient.liveValue.loadStore(invalidDefaults)

        XCTAssertEqual(store, ContentTabPinnedRecordStore())
    }

    func testPinnedRecordClient_updateStoreSerializesConcurrentMutations() async throws {
        let defaults = UserDefaultsClient.testValue
        let client = ContentTabPinnedRecordClient.liveValue
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let firstRecord = Self.pinnedRecord(
            id: firstID,
            anchor: .directory(path: "/Users/test/Documents"),
            title: "Documents",
            iconName: "folder",
        )
        let secondRecord = Self.pinnedRecord(
            id: secondID,
            anchor: .directory(path: "/Users/test/Downloads"),
            title: "Downloads",
            iconName: "folder",
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for record in [firstRecord, secondRecord] {
                group.addTask {
                    try client.updateStore(defaults) { store in
                        Thread.sleep(forTimeInterval: 0.01)
                        var records = store.records
                        records.append(record)
                        return ContentTabPinnedRecordStore(records: records)
                    }
                }
            }
            try await group.waitForAll()
        }

        let savedStore = try client.loadStore(defaults)
        XCTAssertEqual(Set(savedStore.records.map(\.id)), Set([firstID.rawValue, secondID.rawValue]))
        XCTAssertEqual(savedStore.records.count, 2)
    }

    // VOY-570 Linear AC mapping (CTM owner):
    // AC1/AC5 -> testBuiltInSeed_appendsAbsentBuiltInsWithoutReorderingExistingRecords
    // AC6 -> testBuiltInSeed_completionTrueMissingRecordIsSuppressedWithoutMutation
    // AC9 -> testBuiltInSeed_itemDecisionsAreIndependent
    // AC10 -> existing Recents/All Tags canonicalization slot-preservation tests
    // Capacity retry -> testBuiltInSeed_capacityDeferredThenLaterSeedsLatestLockedStore

    // MARK: - CTM-003-seed_built_in_pinned_content_tabs

    /// CTM-003-seed_built_in_pinned_content_tabs: 누락된 built-in은 기존 pinned record 뒤에 append한다.
    /// 최초 built-in seed가 Recents와 All Tags에 위치 우선순위를 부여하지 않는지 검증한다.
    /// - 검증 내용: 기존 상대 순서, 누락 Recents/All Tags append와 canonical page/anchor/title/icon
    /// - 사전 조건: Finder와 user record가 있고 두 built-in ensure 결과가 ready, completion은 false
    /// - 기대 결과: [finder, user, Recents, All Tags] 순서와 stable identity가 저장됨
    func testBuiltInSeed_appendsAbsentBuiltInsWithoutReorderingExistingRecords() {
        let recentsURL = URL(fileURLWithPath: "/Application Support/Voyager/Collections/BuiltIn/recents.voycoll")
        let allTagsURL = URL(fileURLWithPath: "/Application Support/Voyager/Collections/BuiltIn/all-tags.voycoll")
        let finderRecord = Self.pinnedRecord(
            id: ContentTabID(rawValue: "finder"),
            anchor: .directory(path: "/Users/test/Documents"),
            title: "Documents",
        )
        let userRecord = Self.pinnedRecord(
            id: ContentTabID(rawValue: "user"),
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/User.voycoll")),
            title: "User",
        )
        let initialStore = ContentTabPinnedRecordStore(records: [finderRecord, userRecord])

        let recentsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .recents, canonicalPackageURL: recentsURL)),
            completion: false,
            store: initialStore,
            now: Self.pinnedAt,
        )
        guard case let .seed(recentsStore) = recentsResult else {
            return XCTFail("Recents는 새 record를 seed해야 함")
        }
        let allTagsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: allTagsURL)),
            completion: false,
            store: recentsStore,
            now: Self.pinnedAt,
        )
        guard case let .seed(finalStore) = allTagsResult else {
            return XCTFail("All Tags는 새 record를 seed해야 함")
        }

        XCTAssertEqual(finalStore.records.map(\.id), [
            "finder",
            "user",
            "built-in-collection-recents",
            "built-in-collection-all-tags",
        ])
        XCTAssertEqual(finalStore.records[2].page, .collection)
        XCTAssertEqual(finalStore.records[2].anchor, .collectionFile(url: recentsURL))
        XCTAssertEqual(finalStore.records[2].title, "Recents")
        XCTAssertEqual(finalStore.records[2].iconName, "clock")
        XCTAssertEqual(finalStore.records.last?.page, .collection)
        XCTAssertEqual(finalStore.records.last?.anchor, .collectionFile(url: allTagsURL))
        XCTAssertEqual(finalStore.records.last?.title, "All Tags")
        XCTAssertEqual(finalStore.records.last?.iconName, "tag")
        XCTAssertFalse(finalStore.records.contains {
            if case .virtualCollection = $0.anchor { true } else { false }
        })
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: Recents stable ID match의 기존 상대 슬롯을 보존한다.
    /// Recents canonicalization도 첫 위치로 이동하지 않고 선택된 stable record의 상대 위치를 유지하는지 검증한다.
    /// - 검증 내용: stable ID 우선 선택, pinnedAt 보존, ID/URL 중복 제거, 선택 match의 상대 insertion position
    /// - 사전 조건: nonmatching record 사이에 canonical URL residue와 Recents stable ID record가 섞인 store
    /// - 기대 결과: [first-other, second-other, Recents, third-other]이며 stable ID record의 pinnedAt이 유지됨
    func testBuiltInSeed_recentsCanonicalizationPreservesSelectedMatchSlot() {
        let canonicalURL = URL(fileURLWithPath: "/Application Support/Voyager/Collections/BuiltIn/recents.voycoll")
        let urlDuplicate = ContentTabPinnedRecord(
            id: "legacy-recents",
            page: .collection,
            anchor: .collectionFile(url: canonicalURL),
            title: "Old Recents",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 100),
        )
        let stableDuplicate = ContentTabPinnedRecord(
            id: "built-in-collection-recents",
            page: .directory,
            anchor: .directory(path: "/stale"),
            title: "Stale",
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 200),
        )
        let firstOther = Self.pinnedRecord(
            id: ContentTabID(rawValue: "first-other"),
            anchor: .directory(path: "/first"),
        )
        let secondOther = Self.pinnedRecord(
            id: ContentTabID(rawValue: "second-other"),
            anchor: .directory(path: "/second"),
        )
        let thirdOther = Self.pinnedRecord(
            id: ContentTabID(rawValue: "third-other"),
            anchor: .directory(path: "/third"),
        )
        let store = ContentTabPinnedRecordStore(records: [
            firstOther, urlDuplicate, secondOther, stableDuplicate, thirdOther,
        ])

        let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .recents, canonicalPackageURL: canonicalURL)),
            completion: false,
            store: store,
            now: Date(timeIntervalSince1970: 999),
        )
        guard case let .alreadyPresent(finalStore) = result else {
            return XCTFail("기존 Recents match는 alreadyPresent여야 함")
        }

        XCTAssertEqual(finalStore.records.map(\.id), [
            "first-other", "second-other", "built-in-collection-recents", "third-other",
        ])
        XCTAssertEqual(finalStore.records[2].pinnedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(finalStore.records[2].anchor, .collectionFile(url: canonicalURL))
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: All Tags stable ID match의 기존 상대 슬롯을 보존한다.
    /// crash retry에서 ID/URL residue가 함께 남아도 선택된 stable record 위치에 하나만 canonicalize하는지 검증한다.
    /// - 검증 내용: stable ID 우선 선택, pinnedAt 보존, ID/URL 중복 제거, 선택 match의 상대 insertion position
    /// - 사전 조건: canonical URL duplicate 2개와 가운데 stable ID duplicate 1개가 섞인 store
    /// - 기대 결과: [first-other, All Tags, second-other]이며 stable ID record의 pinnedAt이 유지됨
    func testBuiltInSeed_deduplicatesStableIDAndCanonicalURLPreservingStableMatchTimestamp() {
        let canonicalURL = URL(fileURLWithPath: "/Application Support/Voyager/Collections/BuiltIn/all-tags.voycoll")
        let urlDuplicate = ContentTabPinnedRecord(
            id: "legacy-all-tags",
            page: .collection,
            anchor: .collectionFile(url: canonicalURL),
            title: "Old All Tags",
            iconName: "folder",
            pinnedAt: Date(timeIntervalSince1970: 100),
        )
        let stableDuplicate = ContentTabPinnedRecord(
            id: "built-in-collection-all-tags",
            page: .directory,
            anchor: .directory(path: "/stale"),
            title: "Stale",
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 200),
        )
        let secondURLDuplicate = ContentTabPinnedRecord(
            id: "second-all-tags",
            page: .collection,
            anchor: .collectionFile(url: canonicalURL),
            title: nil,
            iconName: nil,
            pinnedAt: Date(timeIntervalSince1970: 300),
        )
        let firstOther = Self.pinnedRecord(
            id: ContentTabID(rawValue: "first-other"),
            anchor: .directory(path: "/first"),
        )
        let secondOther = Self.pinnedRecord(
            id: ContentTabID(rawValue: "second-other"),
            anchor: .directory(path: "/second"),
        )
        let store = ContentTabPinnedRecordStore(records: [
            firstOther, urlDuplicate, stableDuplicate, secondOther, secondURLDuplicate,
        ])

        let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: canonicalURL)),
            completion: false,
            store: store,
            now: Date(timeIntervalSince1970: 999),
        )
        guard case let .alreadyPresent(finalStore) = result else {
            return XCTFail("기존 match는 alreadyPresent여야 함")
        }

        XCTAssertEqual(finalStore.records.map(\.id), [
            "first-other", "built-in-collection-all-tags", "second-other",
        ])
        XCTAssertEqual(finalStore.records[1].pinnedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(finalStore.records[1].anchor, .collectionFile(url: canonicalURL))
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: completion된 누락 record를 자동 복구하지 않는다.
    /// deliberate unpin suppression 이후 package가 ready여도 store 값이 바뀌지 않는지 검증한다.
    /// - 검증 내용: completion=true가 ready보다 우선해 suppressed를 반환하고 입력 store 의미 유지
    /// - 사전 조건: built-in record가 없는 store와 completion=true
    /// - 기대 결과: suppressed이며 store가 원본과 의미적으로 동일하게 유지됨
    func testBuiltInSeed_completionTrueMissingRecordIsSuppressedWithoutMutation() {
        let store = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(
                    id: ContentTabID(rawValue: "user"),
                    anchor: .directory(path: "/Users/test"),
                ),
            ],
        )
        let originalStore = store

        let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(
                identity: .recents,
                canonicalPackageURL: URL(fileURLWithPath: "/BuiltIn/recents.voycoll"),
            )),
            completion: true,
            store: store,
            now: Date(timeIntervalSince1970: 999),
        )

        XCTAssertEqual(result, .suppressed)
        XCTAssertEqual(store, originalStore)
        XCTAssertFalse(store.records.contains { $0.id == "built-in-collection-all-tags" })
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: full capacity에서 누락 built-in을 defer한다.
    /// 자동 seed가 기존 user/Finder record를 제거해 공간을 만들지 않는지 검증한다.
    /// - 검증 내용: max count 이상이고 match가 없으면 deferred 반환
    /// - 사전 조건: non-built-in record 2개, injected maxRecordCount 2
    /// - 기대 결과: deferred이며 기존 store record가 모두 유지됨
    func testBuiltInSeed_fullCapacityWithoutMatchDefersWithoutEviction() {
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "one"), anchor: .directory(path: "/one")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "two"), anchor: .directory(path: "/two")),
        ]
        let store = ContentTabPinnedRecordStore(records: records)

        let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(
                identity: .allTags,
                canonicalPackageURL: URL(fileURLWithPath: "/BuiltIn/all-tags.voycoll"),
            )),
            completion: false,
            store: store,
            now: Date(timeIntervalSince1970: 999),
            maxRecordCount: 2,
        )

        XCTAssertEqual(result, .deferred)
        XCTAssertEqual(store.records, records)
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: capacity defer는 여유가 생긴 다음 transaction에서 재시도한다.
    /// 실제 locked pinned store의 최신 값을 사용해 deferred item이 이후 seed되는지 검증한다.
    /// - 검증 내용: full store no-op, locked record 제거, 다음 locked transform의 canonical All Tags seed
    /// - 사전 조건: max count 2인 persisted store에 non-built-in record 2개와 incomplete All Tags
    /// - 기대 결과: 첫 결과는 deferred이고 이후 final store 마지막에 All Tags가 저장됨
    func testBuiltInSeed_capacityDeferredThenLaterSeedsLatestLockedStore() throws {
        let allTagsURL = URL(fileURLWithPath: "/BuiltIn/all-tags.voycoll")
        let initialStore = ContentTabPinnedRecordStore(records: [
            Self.pinnedRecord(id: ContentTabID(rawValue: "one"), anchor: .directory(path: "/one")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "two"), anchor: .directory(path: "/two")),
        ])
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: initialStore)
        let defaults = defaultsRecorder.client()
        let client = ContentTabPinnedRecordClient.liveValue
        let results = LockIsolated<[BuiltInContentTabPinnedRecordSeedPolicy.Result]>([])
        let pinnedAt = Self.pinnedAt

        let deferredStore = try client.updateStoreAndLoad(defaults) { latestStore in
            let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: allTagsURL)),
                completion: false,
                store: latestStore,
                now: pinnedAt,
                maxRecordCount: 2,
            )
            results.withValue { $0.append(result) }
            guard case let .seed(store) = result else { return latestStore }
            return store
        }
        XCTAssertEqual(results.value, [.deferred])
        XCTAssertEqual(deferredStore, initialStore)

        _ = try client.updateStoreAndLoad(defaults) { latestStore in
            ContentTabPinnedRecordStore(records: Array(latestStore.records.prefix(1)))
        }
        let seededStore = try client.updateStoreAndLoad(defaults) { latestStore in
            let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: allTagsURL)),
                completion: false,
                store: latestStore,
                now: pinnedAt,
                maxRecordCount: 2,
            )
            results.withValue { $0.append(result) }
            guard case let .seed(store) = result else { return latestStore }
            return store
        }

        guard case .seed = results.value.last else {
            return XCTFail("capacity가 생긴 최신 store에는 All Tags가 seed되어야 함")
        }
        XCTAssertEqual(seededStore.records.map(\.id), ["one", "built-in-collection-all-tags"])
        XCTAssertEqual(seededStore.records.last?.anchor, .collectionFile(url: allTagsURL))
        XCTAssertEqual(try client.loadStore(defaults), seededStore)
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: capacity가 가득 차도 기존 match는 canonicalize한다.
    /// match 교체는 record count를 늘리지 않으므로 full store에서도 허용되는지 검증한다.
    /// - 검증 내용: canonical URL match가 있으면 alreadyPresent와 기존 All Tags 상대 슬롯 반환
    /// - 사전 조건: max count 2인 store에서 legacy All Tags URL record가 user record 앞에 존재
    /// - 기대 결과: stable All Tags가 기존 첫 슬롯을 유지하고 count는 2로 유지됨
    func testBuiltInSeed_fullCapacityWithMatchCanonicalizesWithoutGrowth() {
        let canonicalURL = URL(fileURLWithPath: "/BuiltIn/all-tags.voycoll")
        let preservedPinnedAt = Date(timeIntervalSince1970: 123)
        let userRecord = Self.pinnedRecord(
            id: ContentTabID(rawValue: "user"),
            anchor: .directory(path: "/user"),
        )
        let legacyRecord = ContentTabPinnedRecord(
            id: "legacy-all-tags",
            page: .collection,
            anchor: .collectionFile(url: canonicalURL),
            title: "Tags",
            iconName: "number",
            pinnedAt: preservedPinnedAt,
        )

        let result = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: canonicalURL)),
            completion: false,
            store: ContentTabPinnedRecordStore(records: [legacyRecord, userRecord]),
            now: Date(timeIntervalSince1970: 999),
            maxRecordCount: 2,
        )
        guard case let .alreadyPresent(finalStore) = result else {
            return XCTFail("URL match는 full capacity에서도 canonicalize해야 함")
        }

        XCTAssertEqual(finalStore.records.map(\.id), ["built-in-collection-all-tags", "user"])
        XCTAssertEqual(finalStore.records.first?.pinnedAt, preservedPinnedAt)
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: built-in item 결과를 독립적으로 평가한다.
    /// 한 item의 ensure 실패가 다른 ready item의 seed 결과를 막지 않는지 검증한다.
    /// - 검증 내용: Recents failed와 All Tags seed 결과가 서로 독립적으로 유지됨
    /// - 사전 조건: 같은 initial store에 Recents failed, All Tags ready 입력
    /// - 기대 결과: Recents는 failed이고 All Tags는 canonical record로 seed됨
    func testBuiltInSeed_itemDecisionsAreIndependent() {
        let store = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(
                    id: ContentTabID(rawValue: "user"),
                    anchor: .directory(path: "/user"),
                ),
            ],
        )
        let recentsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .failed,
            completion: false,
            store: store,
            now: Self.pinnedAt,
        )
        let allTagsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(
                identity: .allTags,
                canonicalPackageURL: URL(fileURLWithPath: "/BuiltIn/all-tags.voycoll"),
            )),
            completion: false,
            store: store,
            now: Self.pinnedAt,
        )

        XCTAssertEqual(recentsResult, .failed)
        guard case let .seed(finalStore) = allTagsResult else {
            return XCTFail("다른 ready item은 seed되어야 함")
        }
        XCTAssertEqual(finalStore.records.map(\.id), ["user", "built-in-collection-all-tags"])
        XCTAssertEqual(
            BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
                ensureResult: .deferred,
                completion: false,
                store: finalStore,
                now: Self.pinnedAt,
            ),
            .deferred,
        )
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: locked API는 최신 store를 변환해 final store를 반환한다.
    /// concurrent mutation이 stale pre-read를 사용하지 않고 하나의 transaction으로 직렬화되는지 검증한다.
    /// - 검증 내용: 두 updateStoreAndLoad 결과와 최종 persisted store에 mutation 누적
    /// - 사전 조건: empty persisted store와 서로 다른 두 record의 concurrent transform
    /// - 기대 결과: 반환 count가 1/2이고 최종 store에 두 record가 모두 존재함
    func testPinnedRecordClient_updateStoreAndLoadTransformsLatestLockedStoreAndReturnsFinalStore() async throws {
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: ContentTabPinnedRecordStore())
        let defaults = defaultsRecorder.client()
        let client = ContentTabPinnedRecordClient.liveValue
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "first"), anchor: .directory(path: "/first")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "second"), anchor: .directory(path: "/second")),
        ]

        let returnedCounts = try await withThrowingTaskGroup(of: Int.self) { group in
            for record in records {
                group.addTask {
                    let finalStore = try client.updateStoreAndLoad(defaults) { store in
                        Thread.sleep(forTimeInterval: 0.01)
                        var updatedStore = store
                        updatedStore.records.append(record)
                        return updatedStore
                    }
                    return finalStore.records.count
                }
            }
            var counts: [Int] = []
            for try await count in group {
                counts.append(count)
            }
            return counts.sorted()
        }

        let finalStore = try client.loadStore(defaults)
        XCTAssertEqual(returnedCounts, [1, 2])
        XCTAssertEqual(Set(finalStore.records.map(\.id)), Set(["first", "second"]))
        XCTAssertEqual(defaultsRecorder.writeCount(), 2)
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: locked API는 no-op write를 생략한다.
    /// 동일 store transform이 UserDefaults persistence를 불필요하게 호출하지 않는지 검증한다.
    /// - 검증 내용: updateStoreAndLoad identity transform의 반환값과 setObject 호출 횟수
    /// - 사전 조건: 기존 record가 저장된 UserDefaults recorder
    /// - 기대 결과: 같은 final store를 반환하고 write count는 0임
    func testPinnedRecordClient_updateStoreAndLoadSkipsNoOpWrite() throws {
        let originalStore = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(
                    id: ContentTabID(rawValue: "existing"),
                    anchor: .directory(path: "/existing"),
                ),
            ],
        )
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: originalStore)

        let finalStore = try ContentTabPinnedRecordClient.liveValue.updateStoreAndLoad(
            defaultsRecorder.client(),
            { $0 },
        )

        XCTAssertEqual(finalStore, originalStore)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-pin_content_tab_s: app-global 동일 tab mutation은 최신 generation만 durable store에 반영한다.
    /// window scope와 무관한 generation 예약이 오래된 transform 실행과 write를 함께 차단하는지 검증한다.
    /// - 검증 내용: stale disposition/transform 미실행, latest disposition/write, 최종 persisted anchor
    /// - 사전 조건: 동일 ContentTabID에 old/new generation을 순서대로 예약
    /// - 기대 결과: old는 superseded이고 new만 applied되어 newer record 하나가 저장됨
    func testPinnedRecordClient_guardedMutationLatestGlobalGenerationWins() async throws {
        let tabID = ContentTabID(rawValue: "shared-global-generation")
        let oldRecord = Self.pinnedRecord(id: tabID, anchor: .directory(path: "/old"))
        let newRecord = Self.pinnedRecord(id: tabID, anchor: .directory(path: "/new"))
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: ContentTabPinnedRecordStore())
        let defaults = defaultsRecorder.client()
        let client = ContentTabPinnedRecordClient.liveValue
        let oldTransformCalled = LockIsolated(false)

        let oldGeneration = client.reserveMutationGeneration(tabID)
        XCTAssertTrue(client.isCurrentMutationGeneration(oldGeneration))
        let newGeneration = client.reserveMutationGeneration(tabID)
        XCTAssertFalse(client.isCurrentMutationGeneration(oldGeneration))
        XCTAssertTrue(client.isCurrentMutationGeneration(newGeneration))
        let oldDisposition = try await client.updateStoreGuarded(oldGeneration, defaults) { store in
            oldTransformCalled.withValue { $0 = true }
            return upsertPinnedRecord(oldRecord, in: store)
        }
        let newDisposition = try await client.updateStoreGuarded(newGeneration, defaults) { store in
            upsertPinnedRecord(newRecord, in: store)
        }

        XCTAssertEqual(oldDisposition, .superseded)
        XCTAssertFalse(oldTransformCalled.value)
        XCTAssertEqual(newDisposition, .applied)
        XCTAssertEqual(try client.loadStore(defaults), ContentTabPinnedRecordStore(records: [newRecord]))
        XCTAssertEqual(defaultsRecorder.writeCount(), 1)
    }

    /// CTM-003-pin_content_tab_s: superseded pin은 optimistic state를 기존 snapshot으로 복구한다.
    /// global winner가 다른 window에 있을 때 local terminal이 pending을 남기지 않는지 검증한다.
    /// - 검증 내용: superseded typed terminal과 isPinned/record/pending rollback
    /// - 사전 조건: unpinned tab의 pin effect가 guarded client에서 superseded disposition을 반환
    /// - 기대 결과: local tab은 unpinned로 복구되고 pending/error가 모두 정리됨
    func testPin_supersededGlobalMutationRollsBackLocalOptimisticState() async throws {
        let tabID = ContentTabID(rawValue: "superseded-local-pin")
        let anchor: ContentTabPageAnchor = .directory(path: "/Users/test/Superseded")
        let generation = try ContentTabPinnedRecordMutationGeneration(
            tabID: tabID,
            value: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000453")),
        )
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: anchor,
                        isPinned: false,
                        title: "Superseded",
                        iconName: "folder",
                    ),
                ],
                activeTabID: tabID,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.reserveMutationGeneration = { _ in generation }
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, _ in .superseded }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(
                id: tabID,
                anchor: anchor,
                title: "Superseded",
                iconName: "folder",
            )
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive { action in
            guard case let .pinnedRecordSaveNotApplied(receivedTabID, context, reason, _) = action else {
                return false
            }
            return receivedTabID == tabID
                && context.generation == generation
                && reason == .superseded
        } assert: {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeValue(forKey: tabID)
            $0.pendingPinnedRecordIDs.remove(tabID)
        }

        XCTAssertNil(store.state.pinnedRecordPersistenceError)
    }

    /// CTM-003-pin_content_tab_s: durable commit 전 cancellation도 local non-applied terminal을 전달한다.
    /// cancellation이 optimistic state와 pending을 고립시키지 않는지 검증한다.
    /// - 검증 내용: cancelled typed terminal과 pin rollback/pending cleanup
    /// - 사전 조건: guarded client가 durable mutation 전에 CancellationError 발생
    /// - 기대 결과: local tab은 기존 unpinned snapshot으로 복구되고 pending이 제거됨
    func testPin_cancelledBeforeCommitRollsBackLocalOptimisticState() async {
        let tabID = ContentTabID(rawValue: "cancelled-local-pin")
        let anchor: ContentTabPageAnchor = .directory(path: "/Users/test/Cancelled")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: anchor,
                        isPinned: false,
                        title: "Cancelled",
                        iconName: "folder",
                    ),
                ],
                activeTabID: tabID,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, _ in
                throw CancellationError()
            }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(
                id: tabID,
                anchor: anchor,
                title: "Cancelled",
                iconName: "folder",
            )
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive { action in
            guard case let .pinnedRecordSaveNotApplied(receivedTabID, _, reason, _) = action else {
                return false
            }
            return receivedTabID == tabID && reason == .cancelled
        } assert: {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeValue(forKey: tabID)
            $0.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: completion key는 built-in item별로 분리된다.
    /// Window bootstrap이 후속 task에서 독립 flag를 읽고 쓸 수 있도록 exact key 계약을 검증한다.
    /// - 검증 내용: Recents/All Tags SettingsKeys 문자열과 상호 distinct 여부
    /// - 사전 조건: AppPreferences SettingsKeys static constants
    /// - 기대 결과: 각 v1 key가 문서화된 exact 값과 일치함
    func testBuiltInSeed_completionKeysAreIndependent() {
        XCTAssertEqual(
            SettingsKeys.recentsPinnedSeedCompleted,
            "fileManager.builtInCollection.recentsPinnedSeed.v1",
        )
        XCTAssertEqual(
            SettingsKeys.allTagsPinnedSeedCompleted,
            "fileManager.builtInCollection.allTagsPinnedSeed.v1",
        )
        XCTAssertNotEqual(
            SettingsKeys.recentsPinnedSeedCompleted,
            SettingsKeys.allTagsPinnedSeedCompleted,
        )
    }

    // MARK: - CTM-003-pin_content_tab_s

    /// CTM-003-pin_content_tab_s: unpinned tab pin 시 pinned 상태 전환과 persistence 기록
    /// Directory tab을 pin하면 isPinned가 true가 되고 pin 시점 anchor가 frozen되며 persistence save가 완료됨을 검증한다.
    /// - 검증 내용: pin 액션 후 isPinned=true, pinnedRecords에 전체 snapshot freeze, saveSucceeded 수신
    /// - 사전 조건: unpinned Directory tab 하나
    /// - 기대 결과: isPinned=true, frozen record 저장, persistence 성공
    func testPin_directoryTabBecomesPinnedAndPersists() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: directoryAnchor,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(id: tabID, anchor: directoryAnchor)
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: Collection file tab pin 시 active tab과 persisted record 유지
    /// Collection package를 파일처럼 pin할 때 tab이 제거되거나 Home으로 대체되지 않아야 한다.
    /// - 검증 내용: collectionFile anchor tab pin 후 pinned record 저장 성공과 active tab 유지 검증
    /// - 사전 조건: active tab page == .collection, anchor == .collectionFile(url), isPinned == false
    /// - 기대 결과: 같은 tab id가 pinned로 전환되고 collection pinned record가 저장됨
    func testPin_collectionFileTabStaysActiveAndPersists() async {
        let tabID = ContentTabID()
        let collectionURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let collectionAnchor: ContentTabPageAnchor = .collectionFile(url: collectionURL)
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .collection,
                        anchor: collectionAnchor,
                        isPinned: false,
                        title: "Saved",
                        iconName: "rectangle.stack",
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(
                id: tabID,
                page: .collection,
                anchor: collectionAnchor,
                title: "Saved",
                iconName: "rectangle.stack",
            )
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()

        XCTAssertEqual(store.state.tabs.count, 1)
        XCTAssertEqual(store.state.activeTabID, tabID)
        XCTAssertEqual(store.state.tabs[id: tabID]?.anchor, collectionAnchor)
    }

    /// CTM-003-pin_content_tab_s: restore 불가 virtual collection anchor 최초 pin 차단
    /// Recents/Computer처럼 persisted restore 경로에서 안전하게 구분할 수 없는 virtual collection은 pinned record로 저장하지 않는다.
    /// - 검증 내용: pin 액션이 tab 상태와 pinnedRecords/UserDefaults store를 변경하지 않음
    /// - 사전 조건: unpinned Collection tab의 anchor == .virtualCollection(id: "Recents")
    /// - 기대 결과: isPinned=false 유지, pinned record 미생성, persistence save 미호출
    func testPin_virtualCollectionAnchorDoesNotPersistPinnedRecord() async {
        let tabID = ContentTabID()
        let recentsAnchor: ContentTabPageAnchor = .virtualCollection(id: "Recents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .collection,
                        anchor: recentsAnchor,
                        isPinned: false,
                        title: "Recents",
                        iconName: "clock",
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in
                XCTFail("restore 불가 virtual collection anchor는 최초 pin에서도 저장하지 않아야 함")
            }
        }

        await store.send(.pin(tabID))
        await store.finish()

        XCTAssertEqual(store.state.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.pinnedRecords[tabID])
    }

    /// CTM-003-pin_content_tab_s: restore 경로가 없는 AI Chat 최초 pin 차단
    /// AI Chat session은 현재 content/inspector 복원 계약이 없으므로 persisted pinned record로 저장하지 않는다.
    /// - 검증 내용: AI Chat anchor pin 시도 후 local pinned state와 UserDefaults 저장 미발생
    /// - 사전 조건: unpinned AI Chat tab의 anchor == .aiChat(sessionID:)
    /// - 기대 결과: tab은 unpinned 유지, pinnedRecords 비어 있음, updateStore 미호출
    func testPin_aiChatAnchorDoesNotPersistPinnedRecord() async {
        let tabID = ContentTabID(rawValue: "ai-chat-tab")
        let aiChatAnchor: ContentTabPageAnchor = .aiChat(sessionID: "chat-1")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .aiChat,
                        anchor: aiChatAnchor,
                        isPinned: false,
                        title: "AI Chat",
                        iconName: "bubble.right",
                    ),
                ],
                activeTabID: tabID,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in
                XCTFail("복원 경로가 없는 AI Chat anchor는 최초 pin에서도 저장하지 않아야 함")
            }
        }

        await store.send(.pin(tabID))
        await store.finish()

        XCTAssertEqual(store.state.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.pinnedRecords[tabID])
    }

    /// CTM-003-pin_content_tab_s: 이미 pinned tab에 pin은 idempotent no-op
    /// 이미 pinned 상태인 tab에 다시 pin 액션을 보내면 중복 record 생성 없이 no-op임을 검증한다.
    /// - 검증 내용: already-pinned tab pin → 상태 변화 없음, effect 없음
    /// - 사전 조건: isPinned=true인 Directory tab
    /// - 기대 결과: 아무 변화 없음
    func testPin_alreadyPinnedTabIsNoOp() async {
        let tabID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/Documents"),
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.pin(tabID))
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: 존재하지 않는 tabID pin은 no-op
    /// 잘못된 tab ID에 pin 액션을 보내면 상태 invariant가 유지됨을 검증한다.
    /// - 검증 내용: invalid ID pin → 상태 변화 없음, effect 없음
    /// - 사전 조건: active Home tab 하나, invalid ID
    /// - 기대 결과: no-op
    func testPin_invalidTabIDIsNoOp() async {
        let activeID = ContentTabID()
        let invalidID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: activeID,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: activeID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.pin(invalidID))
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: 같은 Page anchor를 가진 서로 다른 tab도 각각 pin 가능
    /// 같은 경로의 Directory anchor를 가진 별도 tab을 pin하면 기존 pinned tab과 함께 별도 record로 저장됨을 검증한다.
    /// - 검증 내용: same-anchor second tab pin → 두 tab 모두 pinned, persistence record 2개 저장
    /// - 사전 조건: 같은 경로의 Directory anchor를 가진 pinned tab + unpinned tab
    /// - 기대 결과: 두 번째 tab도 pinned 상태가 되고 record ID는 각 tabID 기준으로 분리
    func testPin_sameAnchorTabsCanBePinnedIndependently() async {
        let pinnedID = ContentTabID()
        let unpinnedID = ContentTabID()
        let sameAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let recorder = PinnedRecordStoreRecorder()
        _ = recorder.record(ContentTabPinnedRecordStore(records: [Self.pinnedRecord(id: pinnedID, anchor: sameAnchor)]))
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: pinnedID,
                        page: .directory,
                        anchor: sameAnchor,
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                    ContentTabItem(
                        id: unpinnedID,
                        page: .directory,
                        anchor: sameAnchor,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: pinnedID,
                recentlyClosed: nil,
                pinnedRecords: [pinnedID: Self.pinnedRecord(id: pinnedID, anchor: sameAnchor)],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(recorder.latestStore())
                _ = recorder.record(savedStore)
                XCTAssertEqual(savedStore.records.map(\.id), [pinnedID.rawValue, unpinnedID.rawValue])
                XCTAssertEqual(savedStore.records.map(\.anchor), [sameAnchor, sameAnchor])
            }
        }

        await store.send(.pin(unpinnedID)) {
            $0.tabs[id: unpinnedID]?.isPinned = true
            $0.pinnedRecords[unpinnedID] = Self.pinnedRecord(id: unpinnedID, anchor: sameAnchor)
            $0.pendingPinnedRecordIDs.insert(unpinnedID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(unpinnedID)
        }
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: restore 불가 anchor로 pinned record 갱신 차단
    /// Pinned Collection tab이 Recents 같은 restore 제외 anchor로 이동해도 저장된 pinned record를 오염시키지 않는다.
    /// - 검증 내용: updateActivePageAnchor가 tab UI는 갱신하지만 incompatible pinned record 저장은 생략
    /// - 사전 조건: collectionFile anchor를 가진 pinned Collection tab
    /// - 기대 결과: tab anchor는 Recents로 바뀌고 persisted pinned record는 기존 collectionFile 유지
    func testPin_pinnedTabNavigationSkipsIncompatiblePinnedRecordPersistence() async {
        let tabID = ContentTabID()
        let originalURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let originalAnchor: ContentTabPageAnchor = .collectionFile(url: originalURL)
        let recentsAnchor: ContentTabPageAnchor = .virtualCollection(id: "Recents")
        let originalRecord = Self.pinnedRecord(
            id: tabID,
            page: .collection,
            anchor: originalAnchor,
            title: "Saved",
            iconName: "rectangle.stack",
        )
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .collection,
                        anchor: originalAnchor,
                        isPinned: true,
                        title: "Saved",
                        iconName: "rectangle.stack",
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
                pinnedRecords: [tabID: originalRecord],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in
                XCTFail("restore 불가 anchor는 pinned record로 저장하지 않아야 함")
            }
        }

        await store.send(ContentTabAction.updateActivePageAnchor(tabID, recentsAnchor)) {
            $0.tabs[id: tabID]?.page = .collection
            $0.tabs[id: tabID]?.anchor = recentsAnchor
            $0.tabs[id: tabID]?.title = "Recents"
            $0.tabs[id: tabID]?.iconName = "clock"
            $0.pinnedRecordPersistenceError = nil
        }
        await store.finish()

        XCTAssertEqual(store.state.pinnedRecords[tabID], originalRecord)
    }

    /// CTM-003-pin_content_tab_s: pinned tab 내부 탐색은 runtime metadata만 갱신함
    /// 현재 session의 tab과 Sidebar는 새 경로를 표시하되 재실행 복원 원본인 durable record는 pin 시점 anchor를 유지한다.
    /// - 검증 내용: runtime tab/Sidebar 갱신, pinned record 불변, persistence 미호출
    /// - 사전 조건: `fixtures/fixtures/documents` 경로에서 생성된 pinned Directory tab
    /// - 기대 결과: session에서는 `documents/pdf`, 재실행 복원에서는 pin 시점 `documents`를 표시
    func testPinnedTabNavigation_updatesRuntimeButPreservesPinnedRecord() async throws {
        let tabID = ContentTabID()
        let fixtureRoot = try FileManagerFixtureSandbox.readOnlyDirectory(from: "fixtures/fixtures/documents")
        let originalPath = fixtureRoot.path
        let nextPath = fixtureRoot.appendingPathComponent("pdf", isDirectory: true).path
        let originalAnchor: ContentTabPageAnchor = .directory(path: originalPath)
        let originalRecord = Self.pinnedRecord(
            id: tabID,
            anchor: originalAnchor,
            title: fixtureRoot.lastPathComponent,
            iconName: "folder",
        )
        let persistenceRecorder = PinnedRecordStoreRecorder()
        let state = ContentTabTestStateBuilder.pinnedDirectoryWindowState(
            tabID: tabID,
            path: originalPath,
            record: originalRecord,
        )
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.entryLoadingClient.displayName = { URL(fileURLWithPath: $0).lastPathComponent }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(ContentTabPinnedRecordStore(records: [originalRecord]))
                _ = persistenceRecorder.record(savedStore)
            }
        }
        // store.exhaustivity = .off: window navigation composition의 내부 라우팅보다 최종 runtime/durable 상태 경계를 검증함
        store.exhaustivity = .off

        // Sidebar command routing과 같이 tab anchor가 navigation보다 먼저 갱신된 조건을 재현함
        await store.send(.contentTabs(.updateRuntimePageAnchor(tabID, .directory(path: nextPath))))
        await store.send(.navigation(.internal(.performNavigateToPath(nextPath))))
        await store.receive { action in
            guard case let .navigation(.delegate(.navigateToState(.folder(receivedPath)))) = action
            else { return false }
            return receivedPath == nextPath
        }
        await store.receive { action in
            guard case let .tabContent(
                receivedTabID,
                .internal(.applyNavigationState(.folder(receivedPath))),
            ) = action else { return false }
            return receivedTabID == tabID && receivedPath == nextPath
        }
        await store.receive(Self.pinnedRuntimeNavigationMatcher(tabID: tabID, path: nextPath))
        await store.finish()

        XCTAssertEqual(store.state.content.navigation.currentPath, nextPath)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, .directory(path: nextPath))
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.title, "pdf")
        let sidebarItem = try XCTUnwrap(store.state.sidebar.contentTabSidebarItems.first)
        XCTAssertEqual(sidebarItem.title, "pdf")
        XCTAssertEqual(sidebarItem.iconName, "folder")
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[tabID], originalRecord)
        XCTAssertTrue(persistenceRecorder.stores().isEmpty)
    }

    /// - 기대 결과: 첫 record page/anchor/title/iconName/pinnedAt이 pin 시점 값으로 유지
    func testPin_pinnedTabNavigationUpdatesPinnedRecordAndPersists() async {
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let originalAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let changedAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Desktop")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Downloads")
        let firstSnapshotAtPin = Self.pinnedRecord(
            id: firstID,
            anchor: originalAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let firstSnapshotAfterNav = Self.pinnedRecord(
            id: firstID,
            anchor: changedAnchor,
            title: "/Users/test/Desktop",
            iconName: "folder",
        )
        let secondSnapshot = Self.pinnedRecord(
            id: secondID,
            anchor: secondAnchor,
            title: "Downloads",
            iconName: "folder",
        )
        let savedStores = PinnedRecordStoreRecorder()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: firstID,
                        page: .directory,
                        anchor: originalAnchor,
                        isPinned: false,
                        title: "Documents",
                        iconName: "folder",
                    ),
                    ContentTabItem(
                        id: secondID,
                        page: .directory,
                        anchor: secondAnchor,
                        isPinned: false,
                        title: "Downloads",
                        iconName: "folder",
                    ),
                ],
                activeTabID: firstID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                // Chain stores: apply transform against latest recorded store
                let savedStore = try transform(savedStores.latestStore())
                _ = savedStores.record(savedStore)
            }
        }

        // Pin first tab → save first record
        await store.send(.pin(firstID)) {
            $0.tabs[id: firstID]?.isPinned = true
            $0.pinnedRecords[firstID] = firstSnapshotAtPin
            $0.pendingPinnedRecordIDs.insert(firstID)
            $0.pinnedRecordPersistenceError = nil
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
        XCTAssertEqual(savedStores.stores().count, 1)
        XCTAssertEqual(savedStores.stores()[0].records, [firstSnapshotAtPin])

        // Navigate within pinned tab → record should update and persist
        await store.send(.updateActivePageAnchor(firstID, changedAnchor)) {
            $0.tabs[id: firstID]?.anchor = changedAnchor
            $0.tabs[id: firstID]?.title = "/Users/test/Desktop"
            $0.tabs[id: firstID]?.iconName = "folder"
            $0.pinnedRecords[firstID] = firstSnapshotAfterNav
            $0.pendingPinnedRecordIDs.insert(firstID)
            $0.pinnedRecordPersistenceError = nil
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
        XCTAssertEqual(savedStores.stores().count, 2)
        XCTAssertEqual(savedStores.stores()[1].records, [firstSnapshotAfterNav])

        // Pin second tab → save both records (existing pinned first + new pinned second)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondSnapshot
            $0.pendingPinnedRecordIDs.insert(secondID)
            $0.pinnedRecordPersistenceError = nil
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(secondID)
        }
        XCTAssertEqual(savedStores.stores().count, 3)
        XCTAssertEqual(savedStores.stores()[2].records, [firstSnapshotAfterNav, secondSnapshot])

        await store.finish()
    }

    private struct MissingInactiveAiChatCacheFixture {
        let homeTabID: ContentTabID
        let pinnedTabID: ContentTabID
        let sessionID: AiChatSessionID
        let targetRoute: ContentPageNavigationRoute
        let durableRecord: ContentTabPinnedRecord
        let restoredSnapshot: AiChatSessionSnapshot
        let cachedSessionID: AiChatSessionID?
        let state: FileManagerFeature.State
    }

    /// CTM-003-pin_content_tab_s: cache가 없는 inactive AI Chat tab은 재활성화 시 저장 session을 복원함
    /// runtime fan-out 시 빈 Chat을 로드 완료 상태로 오인하지 않고 persisted session restore intent를 보존하는지 검증한다.
    /// - 검증 내용: deferred restore cache, 실제 session load, durable record 불변
    /// - 사전 조건: Home이 active이고 pinned tab의 content cache가 없는 상태
    /// - 기대 결과: fan-out 직후 복원 대기 상태를 저장하고 활성화 시 persisted snapshot을 적용
    func testPinnedRuntimeNavigation_restoresMissingInactiveAiChatCacheAfterReactivation() async {
        await assertDeferredAiChatRestoreFlow(makeMissingInactiveAiChatCacheFixture())
    }

    /// CTM-003-pin_content_tab_s: target runtime이 없는 inactive AI cache도 재활성화 시 저장 session을 복원함
    /// 기존 다른 Chat runtime과 background snapshot을 보존하고 활성화 경계에서 target restore로 전환하는지 검증한다.
    /// - 검증 내용: nonmatching runtime 보존, background snapshot 이후 deferred restore, persisted target 적용
    /// - 사전 조건: inactive pinned tab cache가 다른 AI session runtime을 보유
    /// - 기대 결과: cache 단계에서는 기존 runtime을 보존하고 활성화 후 target snapshot으로 교체
    func testPinnedRuntimeNavigation_restoresNonmatchingInactiveAiChatCacheAfterReactivation() async {
        let cachedSessionID = AiChatSessionID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 7)))
        await assertDeferredAiChatRestoreFlow(
            makeMissingInactiveAiChatCacheFixture(cachedSessionID: cachedSessionID),
        )
    }

    /// CTM-003-pin_content_tab_s: target runtime이 이미 있는 inactive AI cache는 그대로 보존함
    /// 동일 session fan-out과 재활성화가 persistence restore나 draft 초기화를 유발하지 않는지 검증한다.
    /// - 검증 내용: matching runtime/draft 보존, persistence load 미호출
    /// - 사전 조건: inactive pinned tab cache가 target AI session runtime을 보유
    /// - 기대 결과: cached runtime을 그대로 활성화하고 durable record를 유지
    func testPinnedRuntimeNavigation_preservesMatchingInactiveAiChatCache() async {
        let targetSessionID = AiChatSessionID(rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 8)))
        let fixture = makeMissingInactiveAiChatCacheFixture(cachedSessionID: targetSessionID)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let store = makeMissingInactiveAiChatCacheStore(fixture, loadedSessionIDs: loadedSessionIDs)

        await sendHistoryThenChatRuntimeNavigation(fixture, store: store)
        await store.send(.contentTabs(.setCurrent(fixture.pinnedTabID)))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(loadedSessionIDs.value.isEmpty)
        XCTAssertEqual(store.state.content.aiChat.sessionID, targetSessionID)
        XCTAssertEqual(store.state.content.aiChat.draftText, "cached runtime draft")
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.pinnedTabID], fixture.durableRecord)
    }

    private func assertDeferredAiChatRestoreFlow(_ fixture: MissingInactiveAiChatCacheFixture) async {
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        let store = makeMissingInactiveAiChatCacheStore(fixture, loadedSessionIDs: loadedSessionIDs)

        await sendHistoryThenChatRuntimeNavigation(fixture, store: store)
        assertDeferredAiChatCache(fixture, store: store, loadedSessionIDs: loadedSessionIDs)
        if let cachedSessionID = fixture.cachedSessionID {
            await store.send(.backgroundAiChatSnapshotPersisted(
                makeBackgroundAiChatSnapshot(sessionID: cachedSessionID),
            ))
            XCTAssertEqual(
                store.state.tabContentStates[fixture.pinnedTabID]?.aiChat.deferredChatSessionRestoreID,
                fixture.sessionID,
            )
        }

        await store.send(.contentTabs(.setCurrent(fixture.pinnedTabID)))
        await store.skipReceivedActions()
        await store.finish()
        assertRestoredAiChatCache(fixture, store: store, loadedSessionIDs: loadedSessionIDs)
    }

    private func sendHistoryThenChatRuntimeNavigation(
        _ fixture: MissingInactiveAiChatCacheFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
    ) async {
        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.pinnedTabID,
            navigationState: .aiChatSessions(fixture.sessionID.rawValue.uuidString),
        ))
        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.pinnedTabID,
            navigationState: fixture.targetRoute,
        ))
    }

    private func makeMissingInactiveAiChatCacheFixture(
        cachedSessionID: AiChatSessionID? = nil,
    ) -> MissingInactiveAiChatCacheFixture {
        let homeTabID = ContentTabID()
        let pinnedTabID = ContentTabID()
        let sessionUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 8))
        let sessionID = AiChatSessionID(rawValue: sessionUUID)
        let durableAnchor = ContentTabPageAnchor.directory(path: "/tmp/pinned-origin")
        let durableRecord = Self.pinnedRecord(
            id: pinnedTabID,
            anchor: durableAnchor,
            title: "Pinned Origin",
            iconName: "folder",
        )
        let restoredSnapshot = makeRestoredAiChatSnapshot(sessionID: sessionID)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: makeMissingInactiveAiChatTabs(
                homeTabID: homeTabID,
                pinnedTabID: pinnedTabID,
                durableAnchor: durableAnchor,
                durableRecord: durableRecord,
            ),
            activeTabID: homeTabID,
            recentlyClosed: nil,
            pinnedRecords: [pinnedTabID: durableRecord],
        )
        state.syncActiveTabContentState()
        let cachedContent = makeCachedAiChatContent(
            sessionID: cachedSessionID,
            inheritingWindowContextFrom: state.content,
        )
        state.tabContentStates[pinnedTabID] = cachedContent
        if let cachedSessionID, let cachedContent {
            state.backgroundAiChatStates[cachedSessionID] = cachedContent
        }
        state.syncContentTabSidebarItems()
        return MissingInactiveAiChatCacheFixture(
            homeTabID: homeTabID,
            pinnedTabID: pinnedTabID,
            sessionID: sessionID,
            targetRoute: .aiChat(sessionUUID.uuidString),
            durableRecord: durableRecord,
            restoredSnapshot: restoredSnapshot,
            cachedSessionID: cachedSessionID,
            state: state,
        )
    }

    private func makeRestoredAiChatSnapshot(sessionID: AiChatSessionID) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Saved pinned chat",
            provider: nil,
            model: nil,
            updatedAtMs: 608,
        )
    }

    private func makeBackgroundAiChatSnapshot(sessionID: AiChatSessionID) -> AiChatSessionSnapshot {
        AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            customTitle: "Background cached runtime",
            provider: nil,
            model: nil,
            updatedAtMs: 609,
        )
    }

    private func makeCachedAiChatContent(
        sessionID: AiChatSessionID?,
        inheritingWindowContextFrom content: FileManagerContentFeature.State,
    ) -> FileManagerContentFeature.State? {
        guard let sessionID else { return nil }
        var cachedContent = FileManagerContentFeature.State.initialContent(
            for: .aiChat(sessionID: sessionID.rawValue.uuidString),
            inheritingWindowContextFrom: content,
        )
        cachedContent.aiChat.sessionID = sessionID
        cachedContent.aiChat.mode = .chat
        cachedContent.aiChat.draftText = "cached runtime draft"
        return cachedContent
    }

    private func makeMissingInactiveAiChatTabs(
        homeTabID: ContentTabID,
        pinnedTabID: ContentTabID,
        durableAnchor: ContentTabPageAnchor,
        durableRecord: ContentTabPinnedRecord,
    ) -> IdentifiedArrayOf<ContentTabItem> {
        [
            ContentTabItem(
                id: pinnedTabID,
                page: .directory,
                anchor: durableAnchor,
                isPinned: true,
                title: durableRecord.title,
                iconName: durableRecord.iconName,
            ),
            ContentTabItem(
                id: homeTabID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
        ]
    }

    private func makeMissingInactiveAiChatCacheStore(
        _ fixture: MissingInactiveAiChatCacheFixture,
        loadedSessionIDs: LockIsolated<[AiChatSessionID]>,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let restoredSnapshot = fixture.restoredSnapshot
        let store = TestStore(initialState: fixture.state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.loadSession = { requestedSessionID in
                loadedSessionIDs.withValue { $0.append(requestedSessionID) }
                return restoredSnapshot
            }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in
                XCTFail("runtime fan-out은 durable pin을 갱신하지 않아야 함")
            }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in
                XCTFail("runtime fan-out은 durable pin을 저장하지 않아야 함")
            }
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 608))
        }
        // store.exhaustivity = .off: window tab handoff와 AI restore 내부 action보다 최종 cache/restore 계약을 검증함
        store.exhaustivity = .off
        return store
    }

    private func assertDeferredAiChatCache(
        _ fixture: MissingInactiveAiChatCacheFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        loadedSessionIDs: LockIsolated<[AiChatSessionID]>,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let cachedState = store.state.tabContentStates[fixture.pinnedTabID]
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.homeTabID, file: file, line: line)
        XCTAssertEqual(cachedState?.navigation.navigationState, fixture.targetRoute, file: file, line: line)
        XCTAssertEqual(cachedState?.aiChat.sessionID, fixture.cachedSessionID, file: file, line: line)
        XCTAssertNil(cachedState?.aiChat.restoreSessionID, file: file, line: line)
        XCTAssertEqual(cachedState?.aiChat.deferredChatSessionRestoreID, fixture.sessionID, file: file, line: line)
        XCTAssertEqual(cachedState?.aiChat.sessionList.selectedSessionID, fixture.sessionID, file: file, line: line)
        XCTAssertEqual(cachedState?.aiChat.mode, .sessions, file: file, line: line)
        if fixture.cachedSessionID != nil {
            XCTAssertEqual(cachedState?.aiChat.draftText, "cached runtime draft", file: file, line: line)
        }
        XCTAssertEqual(
            store.state.contentTabs.pinnedRecords[fixture.pinnedTabID],
            fixture.durableRecord,
            file: file,
            line: line,
        )
        XCTAssertTrue(loadedSessionIDs.value.isEmpty, file: file, line: line)
    }

    private func assertRestoredAiChatCache(
        _ fixture: MissingInactiveAiChatCacheFixture,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        loadedSessionIDs: LockIsolated<[AiChatSessionID]>,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(loadedSessionIDs.value, [fixture.sessionID], file: file, line: line)
        XCTAssertEqual(store.state.contentTabs.activeTabID, fixture.pinnedTabID, file: file, line: line)
        XCTAssertEqual(store.state.content.navigation.navigationState, fixture.targetRoute, file: file, line: line)
        XCTAssertEqual(store.state.content.aiChat.sessionID, fixture.sessionID, file: file, line: line)
        XCTAssertNil(store.state.content.aiChat.deferredChatSessionRestoreID, file: file, line: line)
        XCTAssertEqual(
            store.state.content.aiChat.sessionList.selectedSessionID,
            fixture.sessionID,
            file: file,
            line: line,
        )
        XCTAssertEqual(store.state.content.aiChat.mode, .chat, file: file, line: line)
        XCTAssertEqual(
            store.state.content.aiChat.currentSessionCustomTitle,
            fixture.restoredSnapshot.customTitle,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            store.state.contentTabs.pinnedRecords[fixture.pinnedTabID],
            fixture.durableRecord,
            file: file,
            line: line,
        )
    }

    /// CTM-003-pin_content_tab_s: clean pinned Collection은 non-Collection peer route 적용 전에 Collection 상태를 종료함
    /// peer runtime navigation도 일반 navigation과 동일한 Collection/Composer 정리 경계를 거치는지 검증한다.
    /// - 검증 내용: folder/AI route 적용, Collection/Composer 초기화, durable record 불변
    /// - 사전 조건: active pinned tab이 저장된 clean Collection 상태
    /// - 기대 결과: target route와 runtime anchor를 반영하고 stale Collection context/session을 남기지 않음
    func testPinnedRuntimeNavigation_exitsCleanCollectionForNonCollectionRoutes() async {
        let sessionID = "00000000-0000-0000-0000-000000000608"
        await assertCleanPinnedCollectionExit(
            navigationState: .folder("/tmp/peer"),
            expectedAnchor: .directory(path: "/tmp/peer"),
        )
        await assertCleanPinnedCollectionExit(
            navigationState: .aiChat(sessionID),
            expectedAnchor: .aiChat(sessionID: sessionID),
        )
    }

    /// CTM-003-pin_content_tab_s: target route가 같아도 stale Collection 상태를 정리함
    /// route/anchor가 먼저 반영된 peer에서 남은 Collection/Composer 상태를 self-healing하는지 검증한다.
    /// - 검증 내용: same-route cleanup과 durable record 불변
    /// - 사전 조건: folder route/anchor와 stale clean Collection 상태가 함께 존재
    /// - 기대 결과: route/anchor를 유지하면서 Collection/Composer metadata만 초기화
    func testPinnedRuntimeNavigation_cleansStaleCollectionStateForSameRoute() async {
        await assertCleanPinnedCollectionExit(
            navigationState: .folder("/tmp/peer"),
            expectedAnchor: .directory(path: "/tmp/peer"),
            startsAtTargetRoute: true,
        )
    }

    /// CTM-003-pin_content_tab_s: inactive clean Collection cache도 non-Collection peer route에서 정리함
    /// peer route를 반영한 cached tab을 다시 활성화해도 이전 Collection/Composer 상태를 복원하지 않는지 검증한다.
    /// - 검증 내용: inactive cache와 재활성화 content의 Collection/Composer 초기화, durable record 불변
    /// - 사전 조건: Home이 active이고 pinned tab은 저장된 clean Collection cache 상태
    /// - 기대 결과: folder route를 유지하면서 stale Collection context/session/Composer metadata를 남기지 않음
    func testPinnedRuntimeNavigation_cleansInactiveCollectionCacheBeforeReactivation() async {
        let fixture = makeDirtyPinnedCollectionFixture(isActive: false)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.voycoll")
        let cleanContext = fixture.state.tabContentStates[fixture.tabID]?
            .collection.collectionSession.metadata.baseline?.context
        var state = fixture.state
        state.tabContentStates[fixture.tabID]?.collection.collectionContext = cleanContext
        state.tabContentStates[fixture.tabID]?.collection.collectionSession.document = .init(
            url: sourceURL,
            name: "Source",
        )
        state.tabContentStates[fixture.tabID]?.composer.isCollectionMode = true
        state.tabContentStates[fixture.tabID]?.composer.collectionContext = cleanContext
        state.tabContentStates[fixture.tabID]?.composer.openedCollectionURL = sourceURL
        let store = makeDirtyPinnedCollectionStore(state)
        let targetRoute = ContentPageNavigationRoute.folder("/tmp/peer")

        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.tabID,
            navigationState: targetRoute,
        ))
        await store.skipReceivedActions()

        assertCleanCollectionState(
            store.state.tabContentStates[fixture.tabID],
            navigationState: targetRoute,
        )
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.tabID], fixture.record)

        await store.send(.contentTabs(.setCurrent(fixture.tabID)))
        await store.skipReceivedActions()
        await store.finish()

        assertCleanCollectionState(store.state.content, navigationState: targetRoute)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.tabID], fixture.record)
    }

    private func assertCleanCollectionState(
        _ contentState: FileManagerContentFeature.State?,
        navigationState: ContentPageNavigationRoute,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(contentState?.navigation.navigationState, navigationState, file: file, line: line)
        XCTAssertEqual(contentState?.entryViewLayout.isCollectionMode, false, file: file, line: line)
        XCTAssertNil(contentState?.collection.collectionContext, file: file, line: line)
        XCTAssertNil(contentState?.collection.collectionSession.document, file: file, line: line)
        XCTAssertEqual(contentState?.composer.isCollectionMode, false, file: file, line: line)
        XCTAssertNil(contentState?.composer.collectionContext, file: file, line: line)
        XCTAssertNil(contentState?.composer.openedCollectionURL, file: file, line: line)
    }

    private func assertCleanPinnedCollectionExit(
        navigationState: ContentPageNavigationRoute,
        expectedAnchor: ContentTabPageAnchor,
        startsAtTargetRoute: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) async {
        let fixture = makeDirtyPinnedCollectionFixture(isActive: true)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.voycoll")
        let cleanContext = fixture.state.content.collection.collectionSession.metadata.baseline?.context
        var state = fixture.state
        state.content.collection.collectionContext = cleanContext
        state.content.collection.collectionSession.document = .init(url: sourceURL, name: "Source")
        state.content.composer.isCollectionMode = true
        state.content.composer.collectionContext = cleanContext
        state.content.composer.openedCollectionURL = sourceURL
        if startsAtTargetRoute {
            state.content.navigation.navigationState = navigationState
            state.contentTabs.tabs[id: fixture.tabID]?.anchor = expectedAnchor
        }
        state.syncActiveTabContentState()
        XCTAssertFalse(state.content.hasUnsavedCollectionChanges, file: file, line: line)
        let store = makeDirtyPinnedCollectionStore(state)

        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.tabID,
            navigationState: navigationState,
        ))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.content.navigation.navigationState, navigationState, file: file, line: line)
        XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.tabID]?.anchor, expectedAnchor, file: file, line: line)
        XCTAssertFalse(store.state.content.entryViewLayout.isCollectionMode, file: file, line: line)
        XCTAssertNil(store.state.content.collection.collectionContext, file: file, line: line)
        XCTAssertNil(store.state.content.collection.collectionSession.document, file: file, line: line)
        XCTAssertFalse(store.state.content.composer.isCollectionMode, file: file, line: line)
        XCTAssertNil(store.state.content.composer.collectionContext, file: file, line: line)
        XCTAssertNil(store.state.content.composer.openedCollectionURL, file: file, line: line)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.tabID], fixture.record, file: file, line: line)
    }

    /// CTM-003-pin_content_tab_s: active dirty pinned Collection은 peer runtime navigation을 거부함
    /// 다른 window의 runtime route가 현재 window의 저장되지 않은 Collection draft를 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: active route/tab anchor/draft/durable record 불변
    /// - 사전 조건: active pinned tab이 dirty file-backed Collection 상태
    /// - 기대 결과: inbound folder route를 적용하지 않고 현재 Collection runtime과 draft를 유지
    func testPinnedRuntimeNavigation_preservesActiveDirtyCollection() async {
        let fixture = makeDirtyPinnedCollectionFixture(isActive: true)
        let store = makeDirtyPinnedCollectionStore(fixture.state)

        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.tabID,
            navigationState: .folder("/tmp/peer"),
        ))
        await store.finish()

        assertDirtyPinnedCollectionPreserved(fixture, state: store.state.content, store: store)
    }

    /// CTM-003-pin_content_tab_s: inactive dirty pinned Collection도 peer runtime navigation을 거부함
    /// 캐시된 dirty draft의 route와 tab anchor를 inbound fan-out이 변경하지 않는지 검증한다.
    /// - 검증 내용: cached route/tab anchor/draft/durable record 불변
    /// - 사전 조건: Home이 active이고 pinned Collection tab은 inactive dirty 상태
    /// - 기대 결과: inbound folder route를 무시하고 기존 cached Collection draft를 유지
    func testPinnedRuntimeNavigation_preservesInactiveDirtyCollectionCache() async {
        let fixture = makeDirtyPinnedCollectionFixture(isActive: false)
        let store = makeDirtyPinnedCollectionStore(fixture.state)

        await store.send(.applyPinnedContentTabRuntimeNavigation(
            tabID: fixture.tabID,
            navigationState: .folder("/tmp/peer"),
        ))
        await store.finish()

        let cachedState = store.state.tabContentStates[fixture.tabID]
        XCTAssertEqual(cachedState?.navigation.navigationState, fixture.sourceRoute)
        XCTAssertEqual(cachedState?.collection.collectionContext, fixture.dirtyContext)
        XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.tabID]?.anchor, fixture.sourceAnchor)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.tabID], fixture.record)
    }

    private func makeDirtyPinnedCollectionStore(
        _ state: FileManagerFeature.State,
    ) -> TestStore<FileManagerFeature.State, FileManagerWindowAction> {
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_608))
        }
        store.exhaustivity = .off
        return store
    }

    private func assertDirtyPinnedCollectionPreserved(
        _ fixture: DirtyPinnedCollectionFixture,
        state: FileManagerContentFeature.State,
        store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.navigation.navigationState, fixture.sourceRoute, file: file, line: line)
        XCTAssertEqual(
            store.state.contentTabs.tabs[id: fixture.tabID]?.anchor,
            fixture.sourceAnchor,
            file: file,
            line: line,
        )
        XCTAssertEqual(state.collection.collectionContext, fixture.dirtyContext, file: file, line: line)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[fixture.tabID], fixture.record, file: file, line: line)
    }

    /// CTM-003-pin_content_tab_s: persistence 실패 시 optimistic 상태 rollback
    /// saveStore가 throw하면 isPinned가 false로 복원되고 error 상태가 설정됨을 검증한다.
    /// - 검증 내용: pin 시도 후 save 실패 → isPinned=false 복원, pinnedRecordPersistenceError 설정
    /// - 사전 조건: unpinned Directory tab, saveStore가 throw하는 환경
    /// - 기대 결과: isPinned=false로 rollback, error 플래그 설정
    func testPin_persistenceFailureRollsBackOptimisticState() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: directoryAnchor,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            struct SaveError: Error {}
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(id: tabID, anchor: directoryAnchor)
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.remove(tabID)
            $0.pinnedRecordPersistenceError = "pinned_record_save_failed"
        }
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: pinned 저장 완료/실패는 active close fallback을 지우지 않음
    /// 저장 effect 완료가 tab 전환 후 늦게 도착해도 previousActiveTabID를 보존함을 검증한다.
    /// - 검증 내용: save success/failure 액션 처리 후 previousActiveTabID 유지
    /// - 사전 조건: active tab 전환으로 previousActiveTabID가 기록된 상태
    /// - 기대 결과: persistence 완료/실패는 pinned 상태/error만 갱신하고 close fallback은 보존
    func testPinnedRecordPersistenceResultsPreservePreviousActiveFallback() {
        let activeID = ContentTabID()
        let previousID = ContentTabID()
        let anchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: previousID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
                ContentTabItem(
                    id: activeID,
                    page: .directory,
                    anchor: anchor,
                    isPinned: true,
                    title: "Documents",
                    iconName: "folder",
                ),
            ],
            activeTabID: activeID,
            previousActiveTabID: previousID,
            recentlyClosed: nil,
            pinnedRecords: [activeID: Self.pinnedRecord(id: activeID, anchor: anchor)],
        )

        let feature = CTM003PinnedPersistenceHarness()
        let successIntentID = state.markLatestPinnedRecordPersistenceIntent(for: activeID)
        _ = feature.reduce(
            into: &state,
            action: .pinnedRecordSaveSucceeded(
                tabID: activeID,
                context: ContentTabPinnedRecordTerminalContext(
                    intentID: successIntentID,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: activeID),
                ),
            ),
        )
        XCTAssertEqual(state.previousActiveTabID, previousID)
        XCTAssertNil(state.pinnedRecordPersistenceError)

        let failureIntentID = state.markLatestPinnedRecordPersistenceIntent(for: activeID)
        _ = feature.reduce(
            into: &state,
            action: .pinnedRecordSaveFailed(
                tabID: activeID,
                context: ContentTabPinnedRecordTerminalContext(
                    intentID: failureIntentID,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: activeID),
                ),
                rollback: ContentTabPinnedRecordRollbackSnapshot(
                    previousIsPinned: false,
                    previousPinnedRecord: nil,
                    previousTabIndex: nil,
                ),
            ),
        )
        XCTAssertEqual(state.previousActiveTabID, previousID)
        XCTAssertEqual(state.tabs[id: activeID]?.isPinned, false)
        XCTAssertNil(state.pinnedRecords[activeID])
        XCTAssertEqual(state.pinnedRecordPersistenceError, "pinned_record_save_failed")
    }

    /// CTM-003-pin_content_tab_s: 첫 save가 in-flight인 동안 두 번째 save가 실패해도 앞선 record는 유실되지 않음
    /// 단일 cancel-in-flight 저장으로 앞선 pin 저장 요청이 취소되는 회귀를 방지한다.
    /// - 검증 내용: first pin save 대기 중 second pin save 실패 → first save success까지 수신
    /// - 사전 조건: unpinned Directory tab 2개, 첫 번째 saveStore는 대기, 두 번째 saveStore는 throw
    /// - 기대 결과: 첫 번째 tab은 pinned 상태와 persisted record를 유지하고 두 번째 tab만 rollback
    func testPin_secondPersistenceFailureDoesNotLoseFirstPinnedRecord() async {
        struct SaveError: Error {}

        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let firstAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Downloads")
        let recorder = PinnedRecordStoreRecorder()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: firstID,
                        page: .directory,
                        anchor: firstAnchor,
                        isPinned: false,
                        title: "Documents",
                        iconName: "folder",
                    ),
                    ContentTabItem(
                        id: secondID,
                        page: .directory,
                        anchor: secondAnchor,
                        isPinned: false,
                        title: "Downloads",
                        iconName: "folder",
                    ),
                ],
                activeTabID: firstID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(recorder.latestStore())
                switch recorder.record(savedStore) {
                case 2:
                    throw SaveError()
                default:
                    break
                }
            }
        }

        let firstRecord = Self.pinnedRecord(
            id: firstID,
            anchor: firstAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let secondRecord = Self.pinnedRecord(
            id: secondID,
            anchor: secondAnchor,
            title: "Downloads",
            iconName: "folder",
        )

        await store.send(.pin(firstID)) {
            $0.tabs[id: firstID]?.isPinned = true
            $0.pinnedRecords[firstID] = firstRecord
            $0.pendingPinnedRecordIDs.insert(firstID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
            $0.pendingPinnedRecordIDs.insert(secondID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.tabs[id: secondID]?.isPinned = false
            $0.pinnedRecords.removeValue(forKey: secondID)
            $0.pendingPinnedRecordIDs.remove(secondID)
            $0.pinnedRecordPersistenceError = "pinned_record_save_failed"
        }
        await store.finish()

        XCTAssertEqual(recorder.stores(), [
            ContentTabPinnedRecordStore(records: [firstRecord]),
            ContentTabPinnedRecordStore(records: [firstRecord, secondRecord]),
        ])
    }

    /// CTM-003-pin_content_tab_s: 늦게 실행된 오래된 pin 저장 transform은 최신 record를 제거하지 않음
    /// stale full-window replacement transform이 최신 persisted state를 되돌리는 회귀를 방지한다.
    /// - 검증 내용: second pin transform이 먼저 저장된 store에 first pin transform을 나중 적용
    /// - 사전 조건: unpinned Directory tab 2개, updateStore transform 실행 순서를 테스트에서 역전
    /// - 기대 결과: 늦게 적용된 first transform 후 persisted store에 두 record 모두 존재
    func testPin_delayedOlderPersistenceDoesNotRemoveNewerPinnedRecord() async {
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let firstAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Downloads")
        let firstRecord = Self.pinnedRecord(
            id: firstID,
            anchor: firstAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let secondRecord = Self.pinnedRecord(
            id: secondID,
            anchor: secondAnchor,
            title: "Downloads",
            iconName: "folder",
        )
        let recorder = PinnedRecordStoreRecorder()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: firstID,
                        page: .directory,
                        anchor: firstAnchor,
                        isPinned: false,
                        title: "Documents",
                        iconName: "folder",
                    ),
                    ContentTabItem(
                        id: secondID,
                        page: .directory,
                        anchor: secondAnchor,
                        isPinned: false,
                        title: "Downloads",
                        iconName: "folder",
                    ),
                ],
                activeTabID: firstID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let existingStore = recorder.stores().isEmpty
                    ? ContentTabPinnedRecordStore(records: [secondRecord])
                    : ContentTabPinnedRecordStore()
                _ = try recorder.record(transform(existingStore))
            }
        }

        await store.send(.pin(firstID)) {
            $0.tabs[id: firstID]?.isPinned = true
            $0.pinnedRecords[firstID] = firstRecord
            $0.pendingPinnedRecordIDs.insert(firstID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
            $0.pendingPinnedRecordIDs.insert(secondID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(secondID)
        }
        await store.finish()

        XCTAssertEqual(recorder.stores().map { $0.records.map(\.id).sorted() }, [
            [firstID.rawValue, secondID.rawValue].sorted(),
            [secondID.rawValue],
        ])
    }

    /// CTM-003-unpin_content_tab_s: 같은 tab의 이전 persistence intent는 최신 intent가 거부
    /// 빠른 Pin→Unpin에서 오래된 pin intent가 늦게 저장되어 restart restore 후보를 남기는 회귀를 방지한다.
    /// - 검증 내용: 같은 tab의 이전 intent token은 최신 token 발급 후 CancellationError
    /// - 사전 조건: 동일 ContentTabID에 연속 persistence intent 발급
    /// - 기대 결과: 오래된 intent는 거부되고 최신 intent만 통과
    func testPinThenUnpin_rejectsOlderPinPersistenceIntentForSameTab() throws {
        let tabID = ContentTabID()
        let scopeID = UUID()
        let olderIntent = PinnedRecordPersistenceIntent.markLatest(scopeID: scopeID, tabID: tabID)
        let latestIntent = PinnedRecordPersistenceIntent.markLatest(scopeID: scopeID, tabID: tabID)

        XCTAssertThrowsError(try PinnedRecordPersistenceIntent.checkCurrent(
            scopeID: scopeID,
            tabID: tabID,
            intentID: olderIntent,
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNoThrow(try PinnedRecordPersistenceIntent.checkCurrent(
            scopeID: scopeID,
            tabID: tabID,
            intentID: latestIntent,
        ))
    }

    /// CTM-003-pin_content_tab_s: 같은 tab의 stale 성공 terminal은 최신 persistence pending을 해제하지 않음
    /// 이전 intent 완료가 선택 탭 일괄 닫기 시작 gate를 조기 개방하는 경합을 방지한다.
    /// - 검증 내용: stale 성공 무시 후 pending/gate 유지, 최신 성공 후 pending 해제와 gate 복구
    /// - 사전 조건: 동일 tab에 older/latest intent가 연속 발급되고 최신 pin persistence가 pending
    /// - 기대 결과: older terminal은 상태를 바꾸지 않고 latest terminal만 pending을 정리한다.
    func testPinnedRecordSaveSucceeded_staleIntentKeepsLatestPendingAndBatchCloseGateBlocked() {
        let tabID = ContentTabID()
        var contentTabState = ContentTabState()
        contentTabState.pendingPinnedRecordIDs = [tabID]
        let olderIntent = contentTabState.markLatestPinnedRecordPersistenceIntent(for: tabID)
        let latestIntent = contentTabState.markLatestPinnedRecordPersistenceIntent(for: tabID)
        let feature = CTM003PinnedPersistenceHarness()

        _ = feature.reduce(
            into: &contentTabState,
            action: .pinnedRecordSaveSucceeded(
                tabID: tabID,
                context: ContentTabPinnedRecordTerminalContext(
                    intentID: olderIntent,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
                ),
            ),
        )

        XCTAssertEqual(contentTabState.pendingPinnedRecordIDs, [tabID])
        var windowState = FileManagerFeature.State()
        windowState.contentTabs = contentTabState
        XCTAssertFalse(windowState.canStartSelectedContentTabClose)

        _ = feature.reduce(
            into: &contentTabState,
            action: .pinnedRecordSaveSucceeded(
                tabID: tabID,
                context: ContentTabPinnedRecordTerminalContext(
                    intentID: latestIntent,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
                ),
            ),
        )

        XCTAssertTrue(contentTabState.pendingPinnedRecordIDs.isEmpty)
        windowState.contentTabs = contentTabState
        XCTAssertTrue(windowState.canStartSelectedContentTabClose)
    }

    /// CTM-003-unpin_content_tab_s: wrapper로 도착한 stale-local non-applied terminal은 완전한 no-op이다.
    /// 최신 intent의 optimistic 상태와 선택 닫기 coordinator를 오래된 rollback이 종료하지 못하게 한다.
    /// - 검증 내용: stale non-applied 처리 전후 전체 window state equality와 downstream action 부재
    /// - 사전 조건: 같은 tab의 최신 intent와 matching selected-close coordinator가 존재
    /// - 기대 결과: pending pin, batch, pending close, tab state가 모두 유지된다.
    func testSelectedClose_staleLocalNonAppliedTerminalIsIgnored() async throws {
        let operationID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000454"))
        let tabID = ContentTabID(rawValue: "stale-non-applied")
        var initialState = FileManagerFeature.State()
        initialState.contentTabs.pendingPinnedRecordIDs = [tabID]
        let staleIntent = initialState.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        _ = initialState.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        initialState.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: operationID,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
            originalActiveTabID: initialState.contentTabs.activeTabID,
            preferredFallbackIDs: initialState.contentTabs.tabs.map(\.id),
        )
        initialState.pendingContentTabClose = PendingContentTabClose(
            tabID: tabID,
            batchOperationID: operationID,
        )
        let store = TestStore(initialState: initialState) {
            CTM003FileManagerPersistenceHarness()
        }

        await store.send(.performSelectedContentTabCloseMutation(
            operationID: operationID,
            tabID: tabID,
            action: .pinnedRecordSaveNotApplied(
                tabID: tabID,
                context: ContentTabPinnedRecordTerminalContext(
                    intentID: staleIntent,
                    generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID),
                ),
                reason: .superseded,
                rollback: ContentTabPinnedRecordRollbackSnapshot(
                    previousIsPinned: true,
                    previousPinnedRecord: nil,
                    previousTabIndex: nil,
                ),
            ),
        ))

        XCTAssertEqual(store.state, initialState)
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: 다른 window의 persisted pinned record를 보존하며 현재 window pin 저장
    /// app-global pinned store 저장 시 현재 window tab 범위만 교체하고 다른 window record를 유지함을 검증한다.
    /// - 검증 내용: 기존 store에 다른 window record가 있을 때 pin 저장 결과가 other + current record로 merge
    /// - 사전 조건: 다른 window record 1개가 persisted store에 있고 현재 window에는 unpinned Directory tab 1개
    /// - 기대 결과: saveStore가 다른 window record를 보존한 merged store를 저장
    func testPin_preservesOtherWindowPinnedRecordsInGlobalStore() async {
        let otherID = ContentTabID()
        let currentID = ContentTabID()
        let otherAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Other")
        let currentAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let otherRecord = Self.pinnedRecord(
            id: otherID,
            anchor: otherAnchor,
            title: "Other",
            iconName: "folder",
        )
        let currentRecord = Self.pinnedRecord(
            id: currentID,
            anchor: currentAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let recorder = PinnedRecordStoreRecorder()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [ContentTabItem(
                    id: currentID,
                    page: .directory,
                    anchor: currentAnchor,
                    isPinned: false,
                    title: "Documents",
                    iconName: "folder",
                )],
                activeTabID: currentID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(ContentTabPinnedRecordStore(records: [otherRecord]))
                _ = recorder.record(savedStore)
            }
        }

        await store.send(.pin(currentID)) {
            $0.tabs[id: currentID]?.isPinned = true
            $0.pinnedRecords[currentID] = currentRecord
            $0.pendingPinnedRecordIDs.insert(currentID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(currentID)
        }
        await store.finish()

        XCTAssertEqual(recorder.stores(), [
            ContentTabPinnedRecordStore(records: [otherRecord, currentRecord]),
        ])
    }

    /// CTM-003-unpin_content_tab_s: 현재 window unpin 저장은 다른 window pinned record를 보존
    /// app-global pinned store에서 현재 window record만 제거하고 다른 window record는 유지함을 검증한다.
    /// - 검증 내용: 기존 store에 other + current record가 있을 때 unpin 저장 결과가 other record만 포함
    /// - 사전 조건: 현재 window pinned tab 1개와 다른 window persisted record 1개
    /// - 기대 결과: saveStore가 current record만 제거한 merged store를 저장
    func testUnpin_preservesOtherWindowPinnedRecordsInGlobalStore() async {
        let otherID = ContentTabID()
        let currentID = ContentTabID()
        let otherAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Other")
        let currentAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let otherRecord = Self.pinnedRecord(
            id: otherID,
            anchor: otherAnchor,
            title: "Other",
            iconName: "folder",
        )
        let currentRecord = Self.pinnedRecord(
            id: currentID,
            anchor: currentAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let recorder = PinnedRecordStoreRecorder()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [ContentTabItem(
                    id: currentID,
                    page: .directory,
                    anchor: currentAnchor,
                    isPinned: true,
                    title: "Documents",
                    iconName: "folder",
                )],
                activeTabID: currentID,
                recentlyClosed: nil,
                pinnedRecords: [currentID: currentRecord],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(ContentTabPinnedRecordStore(records: [otherRecord, currentRecord]))
                _ = recorder.record(savedStore)
            }
        }

        await store.send(.unpin(currentID)) {
            $0.tabs[id: currentID]?.isPinned = false
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.insert(currentID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(currentID)
        }
        await store.finish()

        XCTAssertEqual(recorder.stores(), [
            ContentTabPinnedRecordStore(records: [otherRecord]),
        ])
    }

    /// CTM-003-pin_content_tab_s: 메뉴/shortcut toggle command는 active unpinned tab을 pin함
    /// Cmd+P 메뉴 command가 Window request를 통해 active tab pin 액션으로 라우팅되는지 검증한다.
    /// - 검증 내용: .request(.toggleActiveContentTabPin) → .contentTabs(.pin(activeID)) → persistence 성공
    /// - 사전 조건: active Directory tab이 unpinned 상태
    /// - 기대 결과: active tab isPinned=true, frozen record 저장, persistence 성공
    func testToggleActiveContentTabPinCommand_pinsActiveUnpinnedTab() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: directoryAnchor,
                isPinned: false,
                title: "Documents",
                iconName: "folder",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))
        await store.receive(\.contentTabs) {
            $0.contentTabs.tabs[id: tabID]?.isPinned = true
            $0.contentTabs.pinnedRecords[tabID] = Self.pinnedRecord(
                id: tabID,
                anchor: directoryAnchor,
                title: "Documents",
                iconName: "folder",
            )
            $0.contentTabs.pendingPinnedRecordIDs.insert(tabID)
            $0.syncContentTabSidebarItems()
        }
        await store.receive(\.contentTabs.pinnedRecordPersistenceRequested)
        await store.receive(\.delegate.pinnedRecordPersistenceRequested)
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded) {
            $0.contentTabs.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: 임시 collection 화면에서는 Cmd+P pin 요청이 무시됨
    /// 저장 가능한 collectionFile anchor가 확정되기 전 이전 tab anchor를 pinned record로 영구화하지 않는지 검증한다.
    /// - 검증 내용: temporary collection active 상태에서 toggle pin command no-op
    /// - 사전 조건: active Collection tab의 현재 navigation이 temporary collection 상태
    /// - 기대 결과: tab isPinned=false 유지, pinnedRecords 미생성
    func testToggleActiveContentTabPinCommand_ignoresTemporaryCollection() async {
        let tabID = ContentTabID()
        var state = temporaryCollectionWindowState(tabID: tabID)
        state.syncContentTabSidebarItems()
        let alertRecorder = CollectionPinAlertRecorder()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alertRecorder.record(title: title, message: message)
            }
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
        XCTAssertEqual(alertRecorder.latestAlert()?.title, "Cannot Pin Collection")
        XCTAssertEqual(alertRecorder.latestAlert()?.message, "Save the collection before pinning it as a tab.")
    }

    /// CTM-003-pin_content_tab_s: directory tab에서 임시 collection UI로 전환된 상태도 pin 불가
    /// temporary collection은 tab anchor/page가 아직 directory로 남을 수 있으므로 content state 기준으로 차단한다.
    /// - 검증 내용: tab page가 .directory여도 active content가 temporary collection이면 toggle pin no-op
    /// - 사전 조건: active Directory tab, navigationState=.collection(.temporary), collection mode=true
    /// - 기대 결과: tab isPinned=false 유지, 이전 directory anchor pinned record 미생성
    func testToggleActiveContentTabPinCommand_ignoresTemporaryCollectionInDirectoryTab() async {
        let tabID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Desktop"),
                isPinned: false,
                title: "Desktop",
                iconName: "folder",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.navigation.navigationState = .collection(.init(
            kind: .temporary,
            context: .init(),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .grid,
        ))
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: 임시 collection 화면에서는 Sidebar Pin 요청이 무시됨
    /// Sidebar context menu 경로도 저장 가능한 collectionFile anchor 확정 전에는 pin을 생성하지 않음을 검증한다.
    /// - 검증 내용: temporary collection active 상태에서 Sidebar pin delegate no-op
    /// - 사전 조건: active Collection tab의 현재 navigation이 temporary collection 상태
    /// - 기대 결과: tab isPinned=false 유지, pinnedRecords 미생성
    func testSidebarPinContentTab_ignoresTemporaryCollection() async {
        let tabID = ContentTabID()
        var state = temporaryCollectionWindowState(tabID: tabID)
        state.syncContentTabSidebarItems()
        let alertRecorder = CollectionPinAlertRecorder()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alertRecorder.record(title: title, message: message)
            }
        }

        await store.send(.sidebar(.delegate(.pinContentTab(tabID))))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
        XCTAssertEqual(alertRecorder.latestAlert()?.title, "Cannot Pin Collection")
        XCTAssertEqual(alertRecorder.latestAlert()?.message, "Save the collection before pinning it as a tab.")
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 삭제된 Directory pinned tab 선택 시 피드백 표시
    /// live sync 중에는 깨진 pin을 보존하되 사용자가 선택하면 대상 없음 안내를 표시하고 자동 삭제하지 않는다.
    /// - 검증 내용: broken directory pinned tab 선택 시 unavailable alert와 record 보존 검증
    /// - 사전 조건: pinned tab anchor == .directory(deleted path), fileExistsWithIsDirectory == false
    /// - 기대 결과: Pinned Location Unavailable alert 표시, tab과 pinned record는 유지됨
    func testSelectBrokenPinnedDirectoryTabShowsFeedbackWithoutRemovingTab() async {
        let homeID = ContentTabID(rawValue: "home-tab")
        let brokenID = ContentTabID(rawValue: "broken-pin")
        let brokenAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Deleted")
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
                    id: brokenID,
                    page: .directory,
                    anchor: brokenAnchor,
                    isPinned: true,
                    title: "Deleted",
                    iconName: "folder",
                ),
            ],
            activeTabID: homeID,
            recentlyClosed: nil,
            pinnedRecords: [brokenID: Self.pinnedRecord(id: brokenID, anchor: brokenAnchor)],
        )
        state.syncContentTabSidebarItems()
        let alertRecorder = CollectionPinAlertRecorder()
        let store = TestStore(initialState: state) {
            FileManagerWindowRoutingReducer()
        } withDependencies: {
            $0.fileManagerClient.fileExistsWithIsDirectory = { _, isDirectory in
                isDirectory?.pointee = false
                return false
            }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                alertRecorder.record(title: title, message: message)
            }
        }

        // broken pinned tab 선택은 content handoff/navigation child action을 동반하므로,
        // 이 테스트는 feedback 표시와 pinned record 보존만 검증한다.
        store.exhaustivity = .off
        await store.send(.sidebar(.delegate(.selectContentTab(brokenID))))
        await store.finish()

        XCTAssertEqual(alertRecorder.latestAlert()?.title, "Pinned Location Unavailable")
        XCTAssertEqual(
            alertRecorder.latestAlert()?.message,
            "The pinned item no longer exists. Navigate to a valid location to update this pinned tab.",
        )
        XCTAssertNotNil(store.state.contentTabs.tabs[id: brokenID])
        XCTAssertEqual(store.state.contentTabs.tabs[id: brokenID]?.isPinned, true)
        XCTAssertNotNil(store.state.contentTabs.pinnedRecords[brokenID])
    }

    /// CTM-003-pin_content_tab_s: composer가 만든 미저장 collection context는 directory anchor가 남아 있어도 pin 불가
    /// 임시 collection UI가 directory처럼 보이는 중간 상태에서 오래된 directory anchor를 pinned record로 저장하지 않음을 검증한다.
    /// - 검증 내용: collectionContext != nil && openedCollectionURL == nil 상태에서 pin no-op
    /// - 사전 조건: active Collection tab, unsaved collection context, directory anchor
    /// - 기대 결과: tab isPinned=false 유지, pinnedRecords 미생성
    func testToggleActiveContentTabPinCommand_ignoresUnsavedCollectionContextWithDirectoryAnchor() async {
        let tabID = ContentTabID()
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .directory(path: "/Users/test/ComposerSource"),
                isPinned: false,
                title: "Composer Result",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = CollectionContext(
            query: "report",
            scopes: [],
            conditions: [],
        )
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: New Collection file route라도 opened document/baseline 전에는 pin 불가
    /// 화면 제목이 New Collection으로 보이는 저장 전/열림 세션 미확정 상태를 pinned record로 저장하지 않음을 검증한다.
    /// - 검증 내용: collection file navigation URL은 있지만 collectionSession document/baseline이 없으면 pin no-op
    /// - 사전 조건: active Collection tab, .collection(.file) navigation, collectionContext 있음, opened document 없음
    /// - 기대 결과: tab isPinned=false 유지, pinnedRecords 미생성
    func testToggleActiveContentTabPinCommand_ignoresNewCollectionWithoutOpenedDocument() async {
        let tabID = ContentTabID()
        let url = URL(fileURLWithPath: "/Users/test/New Collection.voyagercollection")
        let context = CollectionContext(query: "", scopes: ["/Users/test/Desktop"], conditions: [])
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .collection,
                anchor: .collectionFile(url: url),
                isPinned: false,
                title: "New Collection",
                iconName: "rectangle.stack",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
        )
        state.content.entryViewLayout.isCollectionMode = true
        state.content.collection.collectionContext = context
        state.content.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: "New Collection"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .grid,
        ))
        state.syncActiveTabContentState()
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertNil(store.state.contentTabs.pinnedRecords[tabID])
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: 메뉴/shortcut toggle command는 active pinned tab을 unpin함
    /// Cmd+P 메뉴 command가 Window request를 통해 active pinned tab unpin 액션으로 라우팅되는지 검증한다.
    /// - 검증 내용: .request(.toggleActiveContentTabPin) → .contentTabs(.unpin(activeID)) → persistence 성공
    /// - 사전 조건: active Directory tab이 pinned 상태
    /// - 기대 결과: active tab isPinned=false, frozen record 제거, persistence 성공
    func testToggleActiveContentTabPinCommand_unpinsActivePinnedTab() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID,
                page: .directory,
                anchor: directoryAnchor,
                isPinned: true,
                title: "Documents",
                iconName: "folder",
            )],
            activeTabID: tabID,
            recentlyClosed: nil,
            pinnedRecords: [tabID: Self.pinnedRecord(id: tabID, anchor: directoryAnchor)],
        )
        state.syncContentTabSidebarItems()
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))
        await store.receive(\.contentTabs) {
            $0.contentTabs.tabs[id: tabID]?.isPinned = false
            $0.contentTabs.pinnedRecords.removeAll()
            $0.contentTabs.pendingPinnedRecordIDs.insert(tabID)
            $0.syncContentTabSidebarItems()
        }
        await store.receive(\.contentTabs.pinnedRecordPersistenceRequested)
        await store.receive(\.delegate.pinnedRecordPersistenceRequested)
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded) {
            $0.contentTabs.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: pin 성공과 persistence rollback은 selection/anchor를 보존함
    /// identity를 유지하는 pin lifecycle이 runtime selection intent를 변경하지 않는지 검증한다.
    /// - 검증 내용: pin save 성공 및 실패 rollback 전후 selected IDs와 valid-unselected anchor exact equality
    /// - 사전 조건: selected pin target과 anchor-only sibling을 가진 동일한 두 초기 상태
    /// - 기대 결과: pin 상태는 성공/rollback 정책대로 변하지만 selection은 target, anchor는 sibling으로 유지됨
    func testPin_successAndPersistenceRollbackPreserveSelectionAndAnchor() async {
        struct SaveError: Error {}

        let targetID = ContentTabID(rawValue: "pin-target")
        let anchorID = ContentTabID(rawValue: "pin-anchor")
        let targetAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/PinTarget")
        let initialState = Self.selectionPreservationState(
            targetID: targetID,
            anchorID: anchorID,
            targetAnchor: targetAnchor,
            targetTitle: "Pin Target",
        )

        let successStore = TestStore(initialState: initialState) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
            }
        }
        await successStore.send(.pin(targetID)) {
            Self.expectPinnedState(&$0, targetID: targetID, targetAnchor: targetAnchor)
        }
        await successStore.receive(\.pinnedRecordPersistenceRequested)
        await successStore.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(targetID)
        }
        await successStore.finish()
        Self.assertSelection(successStore.state, targetID: targetID, anchorID: anchorID)

        let rollbackStore = TestStore(initialState: initialState) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }
        await rollbackStore.send(.pin(targetID)) {
            Self.expectPinnedState(&$0, targetID: targetID, targetAnchor: targetAnchor)
        }
        await rollbackStore.receive(\.pinnedRecordPersistenceRequested)
        await rollbackStore.receive(\.pinnedRecordSaveFailed) {
            Self.expectPinRollbackState(&$0, targetID: targetID)
        }
        await rollbackStore.finish()
        Self.assertSelection(rollbackStore.state, targetID: targetID, anchorID: anchorID)
    }

    /// CTM-003-pin_content_tab_s: PRODUCT Pin eligibility는 active/inactive 실제 content를 함께 판정한다.
    /// 단일 command와 이후 batch preflight가 같은 predicate로 Directory와 저장된 real Collection만 허용하는지 검증한다.
    /// - 검증 내용: missing/Home/AI Chat/virtual/temporary/unsaved 거부와 active/inactive Directory·saved Collection 허용
    /// - 사전 조건: 각 page/anchor와 active content 또는 inactive tabContentStates를 가진 Window state
    /// - 기대 결과: 저장 가능한 실제 위치만 true이고 존재하지 않거나 unsupported인 tab은 false
    func testPinEligibilityAllowsOnlyDirectoryAndSavedRealCollectionForActiveAndInactiveTabs() {
        assertSupportedPinEligibility()
        assertUnsupportedPagePinEligibility()
        assertUnsavedAndTemporaryCollectionPinEligibility()
    }

    /// CTM-003-pin_content_tab_s: ordinary Pin은 현재 pinned segment의 마지막에 frozen 순서로 append한다.
    /// 이후 batch가 single Pin을 순차 재사용해도 runtime tab과 durable record가 같은 pinned boundary를 유지하는지 검증한다.
    /// - 검증 내용: 두 ordinary Pin의 runtime/durable append 순서와 selection/anchor 보존
    /// - 사전 조건: All Tags, wonsik, Recents, ordinary unpinned 2개 순서와 기존 pinned records
    /// - 기대 결과: All Tags·wonsik·Recents·new1·new2 뒤에 unpinned가 남는 순서로 수렴
    func testPinOrdinaryTabsAppendAfterAllExistingPinsInFrozenProcessingOrder() async {
        let fixture = Self.ordinaryPinOrderingFixture
        let recorder = fixture.recorder
        let store = TestStore(initialState: fixture.state) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                _ = try recorder.record(transform(recorder.latestStore()))
            }
        }

        await store.send(.pin(fixture.firstID)) {
            $0.tabs[id: fixture.firstID]?.isPinned = true
            $0.pinnedRecords[fixture.firstID] = Self.pinnedRecord(
                id: fixture.firstID,
                anchor: fixture.firstAnchor,
                title: "First",
                iconName: "folder",
            )
            $0.pendingPinnedRecordIDs.insert(fixture.firstID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(fixture.firstID)
        }
        await store.send(.pin(fixture.secondID)) {
            $0.tabs[id: fixture.secondID]?.isPinned = true
            $0.pinnedRecords[fixture.secondID] = Self.pinnedRecord(
                id: fixture.secondID,
                anchor: fixture.secondAnchor,
                title: "Second",
                iconName: "folder",
            )
            $0.pendingPinnedRecordIDs.insert(fixture.secondID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(fixture.secondID)
        }
        await store.finish()

        XCTAssertEqual(store.state.tabs.map(\.id), fixture.expectedRuntimeIDs)
        XCTAssertEqual(recorder.latestStore().records.map(\.id), fixture.expectedPinnedIDs.map(\.rawValue))
        XCTAssertEqual(store.state.selectedTabIDs, [fixture.firstID, fixture.secondID])
        XCTAssertEqual(store.state.selectionAnchorID, fixture.allTagsID)
    }

    /// CTM-003-pin_content_tab_s: first/middle/last Pin persistence failure는 exact snapshot을 복원한다.
    /// ordinary unpinned segment의 모든 위치에서 optimistic pinned-boundary 이동이 원래 위치로 되돌아가는지 matrix로 검증한다.
    /// - 검증 내용: 각 위치 failed terminal의 exact tabs/pinnedRecords/selection/anchor rollback
    /// - 사전 조건: Recents·All Tags 뒤 first/middle/last unpinned target과 save failure
    /// - 기대 결과: 세 target 모두 Pin 직전 ID 배열과 record/selection snapshot으로 복구
    func testPinFailureRestoresFirstMiddleAndLastExactSnapshots() async {
        struct SaveError: Error {}

        for fixture in Self.pinFailureRollbackFixtures {
            let store = TestStore(initialState: fixture.state) {
                CTM003PinnedPersistenceHarness()
            } withDependencies: {
                $0.date = .constant(Self.pinnedAt)
                $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
            }
            // store.exhaustivity = .off: 위치별 최종 exact snapshot과 typed failure terminal에 집중함
            store.exhaustivity = .off

            await store.send(.pin(fixture.targetID))
            await store.receive(\.pinnedRecordPersistenceRequested)
            await store.receive(\.pinnedRecordSaveFailed)
            await store.finish()

            Self.assertExactRollback(store.state, fixture: fixture)
        }
    }

    /// CTM-003-pin_content_tab_s: notApplied Pin도 이동 전 exact snapshot을 복원한다.
    /// global superseded terminal이 failure와 같은 index/record/selection rollback 경계를 공유하는지 검증한다.
    /// - 검증 내용: notApplied terminal의 tab order/isPinned/record/selection/anchor rollback
    /// - 사전 조건: pinned segment 뒤 unpinned target과 guarded superseded disposition, 다중 selection 및 별도 anchor
    /// - 기대 결과: error 없이 Pin 직전 전체 ordering과 selection snapshot이 exact equality로 복구
    func testPinNotAppliedRestoresExactOriginalOrderingAndSelection() async {
        let fixture = Self.pinOrderingRollbackFixture
        let store = TestStore(initialState: fixture.state) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, _ in .superseded }
        }

        await store.send(.pin(fixture.targetID)) {
            Self.expectOptimisticOrderedPin(&$0, fixture: fixture)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveNotApplied) {
            Self.expectOrderedPinRollback(&$0, fixture: fixture, hasError: false)
        }
        await store.finish()
        Self.assertOrderedPinSnapshot(store.state, fixture: fixture)
    }

    // MARK: - CTM-003-unpin_content_tab_s

    /// CTM-003-unpin_content_tab_s: legacy unsupported pinned tabs는 PRODUCT eligibility와 무관하게 Unpin한다.
    /// Home/AI Chat/virtual/temporary Collection의 page·anchor와 Window-owned content cache를 보존하는지 compact matrix로 검증한다.
    /// - 검증 내용: 네 unsupported kind의 successful Unpin tail append와 AI owner/session/content preservation
    /// - 사전 조건: legacy pinned target, inactive cached content, AI background owner와 unpinned sibling
    /// - 기대 결과: target만 unpinned tail로 이동하고 page/anchor/cache/selection/anchor는 변경되지 않음
    func testLegacyUnsupportedPinnedTabsCanUnpinWithoutChangingOwnedContent() async throws {
        let fixtures = legacyUnsupportedUnpinFixtures

        for fixture in fixtures {
            let originalItem = try XCTUnwrap(fixture.state.contentTabs.tabs[id: fixture.targetID])
            let persistedStore = ContentTabPinnedRecordStore(
                records: Array(fixture.state.contentTabs.pinnedRecords.values),
            )
            let store = TestStore(initialState: fixture.state) {
                CTM003FileManagerPersistenceHarness()
            } withDependencies: {
                $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                    _ = try transform(persistedStore)
                }
            }
            // store.exhaustivity = .off: Window routing 내부 동기화보다 legacy owner/cache 최종 보존을 검증함
            store.exhaustivity = .off

            await store.send(.contentTabs(.unpin(fixture.targetID)))
            await store.receive(\.contentTabs.pinnedRecordSaveSucceeded)
            await store.finish()

            XCTAssertEqual(store.state.contentTabs.tabs.map(\.id), [fixture.siblingID, fixture.targetID])
            XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.targetID]?.page, originalItem.page)
            XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.targetID]?.anchor, originalItem.anchor)
            XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.targetID]?.isPinned, false)
            XCTAssertNil(store.state.contentTabs.pinnedRecords[fixture.targetID])
            XCTAssertEqual(store.state.contentTabs.selectedTabIDs, fixture.state.contentTabs.selectedTabIDs)
            XCTAssertEqual(store.state.contentTabs.selectionAnchorID, fixture.state.contentTabs.selectionAnchorID)
            XCTAssertEqual(store.state.tabContentStates, fixture.state.tabContentStates)
            XCTAssertEqual(store.state.backgroundAiChatStates, fixture.state.backgroundAiChatStates)
            if let aiSessionID = fixture.aiSessionID {
                XCTAssertEqual(store.state.tabContentStates[fixture.targetID]?.aiChat.sessionID, aiSessionID)
                XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.sessionID, aiSessionID)
                XCTAssertEqual(store.state.tabContentStates[fixture.targetID]?.aiChat.draftText, "legacy owner draft")
            }
        }
    }

    /// CTM-003-unpin_content_tab_s: legacy AI Chat Unpin failure도 owner/session/content와 exact tab snapshot을 복원한다.
    /// unsupported AI Chat의 optimistic tail 이동이 실패해도 Window-owned cache를 건드리지 않는지 검증한다.
    /// - 검증 내용: failed terminal의 exact tabs/records/selection/anchor와 AI cache/background owner 보존
    /// - 사전 조건: legacy pinned AI Chat과 persistence failure
    /// - 기대 결과: original pinned index와 record가 복구되고 AI session/content owner는 exact equality 유지
    func testLegacyAiChatUnpinFailureRestoresExactOwnedSnapshot() async throws {
        struct SaveError: Error {}
        let fixture = try XCTUnwrap(legacyUnsupportedUnpinFixtures.first { $0.aiSessionID != nil })
        let store = TestStore(initialState: fixture.state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }
        // store.exhaustivity = .off: Window routing 내부 동기화보다 rollback과 AI owner/cache exact 보존을 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.unpin(fixture.targetID)))
        await store.receive(\.contentTabs.pinnedRecordSaveFailed)
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs, fixture.state.contentTabs.tabs)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords, fixture.state.contentTabs.pinnedRecords)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, fixture.state.contentTabs.selectedTabIDs)
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, fixture.state.contentTabs.selectionAnchorID)
        XCTAssertEqual(store.state.tabContentStates, fixture.state.tabContentStates)
        XCTAssertEqual(store.state.backgroundAiChatStates, fixture.state.backgroundAiChatStates)
        let aiSessionID = try XCTUnwrap(fixture.aiSessionID)
        XCTAssertEqual(store.state.tabContentStates[fixture.targetID]?.aiChat.sessionID, aiSessionID)
        XCTAssertEqual(store.state.backgroundAiChatStates[aiSessionID]?.aiChat.sessionID, aiSessionID)
    }

    /// CTM-003-unpin_content_tab_s: first/middle/last Unpin persistence failure는 exact snapshot을 복원한다.
    /// pinned segment의 모든 위치에서 optimistic tail 이동이 원래 index로 되돌아가는지 matrix로 검증한다.
    /// - 검증 내용: 각 위치 failed terminal의 exact tabs/pinnedRecords/selection/anchor rollback
    /// - 사전 조건: first/middle/last pinned target과 unpinned tail, save failure
    /// - 기대 결과: 세 target 모두 Unpin 직전 ID 배열과 record/selection snapshot으로 복구
    func testUnpinFailureRestoresFirstMiddleAndLastExactSnapshots() async {
        struct SaveError: Error {}

        for fixture in Self.unpinFailureRollbackFixtures {
            let store = TestStore(initialState: fixture.state) {
                CTM003PinnedPersistenceHarness()
            } withDependencies: {
                $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
            }
            // store.exhaustivity = .off: 위치별 최종 exact snapshot과 typed failure terminal에 집중함
            store.exhaustivity = .off

            await store.send(.unpin(fixture.targetID))
            await store.receive(\.pinnedRecordPersistenceRequested)
            await store.receive(\.pinnedRecordSaveFailed)
            await store.finish()

            Self.assertExactRollback(store.state, fixture: fixture)
        }
    }

    /// CTM-003-unpin_content_tab_s: pinned tab unpin 시 persistence에서 제거
    /// Pinned Directory tab을 unpin하면 isPinned=false, frozen record 제거, persistence save 완료됨을 검증한다.
    /// - 검증 내용: unpin 액션 후 isPinned=false, pinnedRecords에서 제거, saveSucceeded 수신
    /// - 사전 조건: pinned Directory tab 하나 (frozen record 설정됨)
    /// - 기대 결과: isPinned=false, record 제거, persistence 성공
    func testUnpin_pinnedTabBecomesUnpinnedAndPersists() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: directoryAnchor,
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
                pinnedRecords: [tabID: Self.pinnedRecord(id: tabID, anchor: directoryAnchor)],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: pinned tab unpin 시 unpinned 영역 맨 아래로 이동
    /// Sidebar projection이 pinned/unpinned를 분리하므로 unpin된 탭을 배열 끝으로 옮겨 normal section 하단에 배치한다.
    /// - 검증 내용: unpin reducer가 pinned marker와 record를 제거하고 tab 배열 끝으로 이동하는지 검증
    /// - 사전 조건: pinned tab 1개와 unpinned tab 2개가 같은 ContentTabState에 존재
    /// - 기대 결과: unpinned tab 순서 뒤에 기존 pinned tab이 isPinned=false 상태로 append됨
    func testUnpin_movesTabToBottomOfUnpinnedTabs() async {
        let pinnedID = ContentTabID(rawValue: "pinned-tab")
        let firstUnpinnedID = ContentTabID(rawValue: "first-unpinned")
        let secondUnpinnedID = ContentTabID(rawValue: "second-unpinned")
        let pinnedAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Pinned")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: pinnedID,
                        page: .directory,
                        anchor: pinnedAnchor,
                        isPinned: true,
                        title: "Pinned",
                        iconName: "folder",
                    ),
                    ContentTabItem(
                        id: firstUnpinnedID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/First"),
                        isPinned: false,
                        title: "First",
                        iconName: "folder",
                    ),
                    ContentTabItem(
                        id: secondUnpinnedID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/Second"),
                        isPinned: false,
                        title: "Second",
                        iconName: "folder",
                    ),
                ],
                activeTabID: pinnedID,
                recentlyClosed: nil,
                pinnedRecords: [pinnedID: Self.pinnedRecord(id: pinnedID, anchor: pinnedAnchor)],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(pinnedID)) {
            var unpinnedTab = $0.tabs[id: pinnedID]!
            unpinnedTab.isPinned = false
            $0.tabs.remove(id: pinnedID)
            $0.tabs.append(unpinnedTab)
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.insert(pinnedID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(pinnedID)
        }
        await store.finish()

        XCTAssertEqual(store.state.tabs.map(\.id), [firstUnpinnedID, secondUnpinnedID, pinnedID])
        XCTAssertEqual(store.state.activeTabID, pinnedID)
        XCTAssertEqual(store.state.tabs[id: pinnedID]?.isPinned, false)
    }

    /// CTM-003-unpin_content_tab_s: 이미 unpinned tab에 unpin은 idempotent no-op
    /// 이미 unpinned 상태인 tab에 unpin 액션을 보내면 no-op임을 검증한다.
    /// - 검증 내용: already-unpinned tab unpin → 상태 변화 없음, effect 없음
    /// - 사전 조건: isPinned=false인 Directory tab
    /// - 기대 결과: 아무 변화 없음
    func testUnpin_alreadyUnpinnedTabIsNoOp() async {
        let tabID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/Documents"),
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(tabID))
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: 존재하지 않는 tabID unpin은 no-op
    /// 잘못된 tab ID에 unpin 액션을 보내면 상태가 유지됨을 검증한다.
    /// - 검증 내용: invalid ID unpin → 상태 변화 없음, effect 없음
    /// - 사전 조건: active Home tab 하나, invalid ID
    /// - 기대 결과: no-op
    func testUnpin_invalidTabIDIsNoOp() async {
        let activeID = ContentTabID()
        let invalidID = ContentTabID()
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: activeID,
                        page: .home,
                        anchor: .homeDefault,
                        isPinned: false,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: activeID,
                recentlyClosed: nil,
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(invalidID))
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: persistence 실패 시 unpin optimistic 상태 rollback
    /// unpin saveStore가 throw하면 isPinned가 true로 복원되고 frozen record가 복구됨을 검증한다.
    /// - 검증 내용: unpin 시도 후 save 실패 → isPinned=true 복원, frozen record 복구, error 설정
    /// - 사전 조건: pinned Directory tab (frozen record 설정), saveStore가 throw
    /// - 기대 결과: isPinned=true로 rollback, record 복구, error 플래그 설정
    func testUnpin_persistenceFailureRollsBackOptimisticState() async {
        let tabID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: tabID,
                        page: .directory,
                        anchor: directoryAnchor,
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: tabID,
                recentlyClosed: nil,
                pinnedRecords: [tabID: Self.pinnedRecord(id: tabID, anchor: directoryAnchor)],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            struct SaveError: Error {}
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }

        await store.send(.unpin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.pendingPinnedRecordIDs.remove(tabID)
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(id: tabID, anchor: directoryAnchor)
            $0.pinnedRecordPersistenceError = "pinned_record_save_failed"
        }
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: pinned tab close는 unpin transition으로 위임
    /// lifecycle contract의 pinned_tab_close_means_unpin 정책을 검증한다.
    /// - 검증 내용: close(pinnedID) → isPinned=false, tab 유지, recentlyClosed 미생성, saveSucceeded 수신
    /// - 사전 조건: pinned Directory tab 하나 (frozen record 설정)
    /// - 기대 결과: 탭은 남고 pinned 상태만 해제됨
    func testClose_pinnedTabDelegatesToUnpin() async {
        let pinnedID = ContentTabID()
        let directoryAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let store = TestStore(
            initialState: ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: pinnedID,
                        page: .directory,
                        anchor: directoryAnchor,
                        isPinned: true,
                        title: nil,
                        iconName: nil,
                    ),
                ],
                activeTabID: pinnedID,
                recentlyClosed: nil,
                pinnedRecords: [pinnedID: Self.pinnedRecord(id: pinnedID, anchor: directoryAnchor)],
            ),
        ) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.close(pinnedID)) {
            $0.tabs[id: pinnedID]?.isPinned = false
            $0.pinnedRecords.removeAll()
            $0.pendingPinnedRecordIDs.insert(pinnedID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(pinnedID)
        }
        await store.finish()
    }

    /// CTM-003-unpin_content_tab_s: unpin 성공과 persistence rollback은 selection/anchor를 보존함
    /// 같은 ID를 재배치하는 unpin lifecycle이 runtime selection intent를 변경하지 않는지 검증한다.
    /// - 검증 내용: unpin save 성공 및 실패 rollback 전후 selected IDs와 valid-unselected anchor exact equality
    /// - 사전 조건: selected pinned target과 anchor-only sibling, target pinned record를 가진 동일한 두 초기 상태
    /// - 기대 결과: unpin 상태는 성공/rollback 정책대로 변하지만 selection은 target, anchor는 sibling으로 유지됨
    func testUnpin_successAndPersistenceRollbackPreserveSelectionAndAnchor() async {
        struct SaveError: Error {}

        let targetID = ContentTabID(rawValue: "unpin-target")
        let anchorID = ContentTabID(rawValue: "unpin-anchor")
        let targetAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/UnpinTarget")
        let pinnedRecord = Self.pinnedRecord(id: targetID, anchor: targetAnchor, title: "Unpin Target")
        var initialState = Self.selectionPreservationState(
            targetID: targetID,
            anchorID: anchorID,
            targetAnchor: targetAnchor,
            targetTitle: "Unpin Target",
            isPinned: true,
            previousActiveTabID: anchorID,
            pinnedRecord: pinnedRecord,
        )
        initialState.activeTabID = anchorID
        initialState.selectedTabIDs = [targetID, anchorID]
        initialState.selectionAnchorID = targetID

        let successStore = TestStore(initialState: initialState) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                _ = try transform(ContentTabPinnedRecordStore(records: [pinnedRecord]))
            }
        }
        await successStore.send(.unpin(targetID)) {
            Self.expectUnpinnedState(&$0, targetID: targetID)
            $0.selectedTabIDs.insert(targetID)
            $0.selectionAnchorID = targetID
        }
        await successStore.receive(\.pinnedRecordPersistenceRequested)
        await successStore.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(targetID)
        }
        await successStore.finish()
        XCTAssertEqual(successStore.state.selectedTabIDs, [targetID, anchorID])
        XCTAssertEqual(successStore.state.selectionAnchorID, targetID)

        let rollbackStore = TestStore(initialState: initialState) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }
        await rollbackStore.send(.unpin(targetID)) {
            Self.expectUnpinnedState(&$0, targetID: targetID)
            $0.selectedTabIDs.insert(targetID)
            $0.selectionAnchorID = targetID
        }
        await rollbackStore.receive(\.pinnedRecordPersistenceRequested)
        await rollbackStore.receive(\.pinnedRecordSaveFailed) {
            $0.pendingPinnedRecordIDs.remove(targetID)
            $0.tabs.move(fromOffsets: [1], toOffset: 0)
            $0.tabs[id: targetID]?.isPinned = true
            $0.pinnedRecords[targetID] = pinnedRecord
            $0.pinnedRecordPersistenceError = "pinned_record_save_failed"
            $0.selectedTabIDs.insert(targetID)
            $0.selectionAnchorID = targetID
        }
        await rollbackStore.finish()
        XCTAssertEqual(rollbackStore.state.selectedTabIDs, [targetID, anchorID])
        XCTAssertEqual(rollbackStore.state.selectionAnchorID, targetID)
    }

    /// CTM-003-unpin_content_tab_s: persistence 실패 rollback은 원래 pinned 상대 순서를 복원함
    /// unpin optimistic 이동이 실패한 뒤 range 선택 기준이 변경되는 회귀를 방지한다.
    /// - 검증 내용: 중간 pinned tab unpin 실패 → raw/pinned-first 순서 복원 → 원래 구간 range 선택
    /// - 사전 조건: pinned tab 3개, 첫 tab이 anchor, 중간 tab 저장 실패
    /// - 기대 결과: 마지막 pinned tab을 포함하지 않고 첫 tab부터 중간 tab까지만 선택
    func testUnpin_persistenceFailureThenSelectRangeUsesOriginalPinnedRelativeOrder() async {
        struct SaveError: Error {}

        let firstPinnedID = ContentTabID(rawValue: "first-pinned")
        let rollbackTargetID = ContentTabID(rawValue: "rollback-target")
        let trailingPinnedID = ContentTabID(rawValue: "trailing-pinned")
        let firstAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/First")
        let targetAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Target")
        let trailingAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Trailing")
        let targetRecord = Self.pinnedRecord(id: rollbackTargetID, anchor: targetAnchor, title: "Target")
        var initialState = ContentTabState(
            tabs: [
                Self.pinnedItem(id: firstPinnedID, anchor: firstAnchor, title: "First"),
                Self.pinnedItem(id: rollbackTargetID, anchor: targetAnchor, title: "Target"),
                Self.pinnedItem(id: trailingPinnedID, anchor: trailingAnchor, title: "Trailing"),
            ],
            activeTabID: firstPinnedID,
            pinnedRecords: [
                firstPinnedID: Self.pinnedRecord(id: firstPinnedID, anchor: firstAnchor, title: "First"),
                rollbackTargetID: targetRecord,
                trailingPinnedID: Self.pinnedRecord(
                    id: trailingPinnedID,
                    anchor: trailingAnchor,
                    title: "Trailing",
                ),
            ],
        )
        initialState.selectedTabIDs = [firstPinnedID]
        initialState.selectionAnchorID = firstPinnedID
        let store = TestStore(initialState: initialState) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }

        await store.send(.unpin(rollbackTargetID)) {
            $0.tabs[id: rollbackTargetID]?.isPinned = false
            $0.tabs.move(fromOffsets: [1], toOffset: 3)
            $0.pinnedRecords.removeValue(forKey: rollbackTargetID)
            $0.pendingPinnedRecordIDs.insert(rollbackTargetID)
        }
        await store.receive(\.pinnedRecordPersistenceRequested)
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.pendingPinnedRecordIDs.remove(rollbackTargetID)
            $0.tabs.move(fromOffsets: [2], toOffset: 1)
            $0.tabs[id: rollbackTargetID]?.isPinned = true
            $0.pinnedRecords[rollbackTargetID] = targetRecord
            $0.pinnedRecordPersistenceError = "pinned_record_save_failed"
        }

        XCTAssertEqual(store.state.selectionOrderedTabIDs, [firstPinnedID, rollbackTargetID, trailingPinnedID])

        await store.send(.selectRange(to: rollbackTargetID)) {
            $0.selectedTabIDs = [firstPinnedID, rollbackTargetID]
        }
        await store.finish()
    }

    // MARK: - CTM-003-go_to_anchored_path_of_pinned_tab

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 전역 pinned 동기화는 unpinned tab을 보존하고 pinned 순서를 store 기준으로 교체
    /// 다른 window에서 변경된 pinned store를 적용해도 현재 window의 unpinned 작업 tab은 유지되어야 함을 검증한다.
    /// - 검증 내용: restored pinned + 기존 unpinned 병합, stale pinned content state 제거
    /// - 사전 조건: 오래된 pinned tab 1개 + unpinned tab 1개, restored pinned tab 2개
    /// - 기대 결과: restored pinned 2개가 앞에 오고 unpinned tab이 뒤에 남음
    func testApplyPinnedContentTabs_preservesUnpinnedTabsAndUsesRestoredOrder() {
        let stalePinnedID = ContentTabID(rawValue: "stale-pin")
        let unpinnedID = ContentTabID(rawValue: "working-tab")
        let firstPinnedID = ContentTabID(rawValue: "first-pin")
        let secondPinnedID = ContentTabID(rawValue: "second-pin")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: stalePinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Stale"),
                    isPinned: true,
                    title: "Stale",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: unpinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Working"),
                    isPinned: false,
                    title: "Working",
                    iconName: "folder",
                ),
            ],
            activeTabID: unpinnedID,
            pinnedRecords: [
                stalePinnedID: Self.pinnedRecord(
                    id: stalePinnedID,
                    anchor: .directory(path: "/Users/test/Stale"),
                    title: "Stale",
                    iconName: "folder",
                ),
            ],
        )
        state.tabContentStates[stalePinnedID] = .init()
        state.tabContentStates[unpinnedID] = state.content
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: firstPinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/A"),
                    isPinned: true,
                    title: "A",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: secondPinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/B"),
                    isPinned: true,
                    title: "B",
                    iconName: "folder",
                ),
            ],
            activeTabID: firstPinnedID,
            pinnedRecords: [
                firstPinnedID: Self.pinnedRecord(
                    id: firstPinnedID,
                    anchor: .directory(path: "/Users/test/A"),
                    title: "A",
                    iconName: "folder",
                ),
                secondPinnedID: Self.pinnedRecord(
                    id: secondPinnedID,
                    anchor: .directory(path: "/Users/test/B"),
                    title: "B",
                    iconName: "folder",
                ),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [firstPinnedID, secondPinnedID, unpinnedID])
        XCTAssertEqual(state.contentTabs.activeTabID, unpinnedID)
        XCTAssertNil(state.tabContentStates[stalePinnedID])
        XCTAssertEqual(Set(state.contentTabs.pinnedRecords.keys), Set([firstPinnedID, secondPinnedID]))
    }

    func testApplyPinnedContentTabsReconcilesSelectionAfterFinalMerge() {
        let survivingPinnedID = ContentTabID(rawValue: "surviving-pin")
        let removedPinnedID = ContentTabID(rawValue: "removed-pin")
        let survivingUnpinnedID = ContentTabID(rawValue: "working-tab")
        let restoredPinnedID = ContentTabID(rawValue: "restored-pin")
        let survivingAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Surviving")
        var state = Self.pinnedMergeSelectionState(
            survivingPinnedID: survivingPinnedID,
            removedPinnedID: removedPinnedID,
            survivingUnpinnedID: survivingUnpinnedID,
            survivingAnchor: survivingAnchor,
        )
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: survivingPinnedID,
                    page: .directory,
                    anchor: survivingAnchor,
                    isPinned: true,
                    title: "Surviving",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: restoredPinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Restored"),
                    isPinned: true,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: restoredPinnedID,
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.selectedTabIDs, [survivingPinnedID, survivingUnpinnedID])
        XCTAssertEqual(state.contentTabs.selectionAnchorID, survivingPinnedID)
        XCTAssertFalse(state.contentTabs.selectedTabIDs.contains(restoredPinnedID))
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: final merge에서 제거된 pinned identity anchor 정리
    /// - 검증 내용: surviving unpinned selection은 유지하고 removed pinned anchor만 nil 처리
    /// - 사전 조건: 선택된 unpinned tab과 anchor인 pinned tab이 있고 restore 결과에서 pinned tab 제거
    /// - 기대 결과: surviving selection 유지, selectionAnchorID == nil
    func testApplyPinnedContentTabsClearsAnchorForRemovedPinnedIdentity() {
        let removedPinnedID = ContentTabID(rawValue: "removed-anchor-pin")
        let survivingUnpinnedID = ContentTabID(rawValue: "surviving-unpinned")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: removedPinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Removed"),
                    isPinned: true,
                    title: "Removed",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: survivingUnpinnedID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: survivingUnpinnedID,
        )
        state.contentTabs.selectedTabIDs = [survivingUnpinnedID]
        state.contentTabs.selectionAnchorID = removedPinnedID

        state.applyPinnedContentTabs(ContentTabState())

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [survivingUnpinnedID])
        XCTAssertEqual(state.contentTabs.selectedTabIDs, [survivingUnpinnedID])
        XCTAssertNil(state.contentTabs.selectionAnchorID)
    }

    func testApplyPinnedContentTabsPreservesSelectionForSameIDAnchorReplacement() {
        let pinnedID = ContentTabID(rawValue: "same-id-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let newAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/New")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: oldAnchor,
                    isPinned: true,
                    title: "Old",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
        )
        state.contentTabs.selectedTabIDs = [pinnedID]
        state.contentTabs.selectionAnchorID = pinnedID
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: newAnchor,
                    isPinned: true,
                    title: "New",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, newAnchor)
        XCTAssertEqual(state.contentTabs.selectedTabIDs, [pinnedID])
        XCTAssertEqual(state.contentTabs.selectionAnchorID, pinnedID)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: sync 중 같은 id의 optimistic unpinned tab 중복 제거
    /// 다른 window의 store가 아직 pinned record를 보유한 동안 현재 window가 같은 id를 unpin한 경우 unique tab id 충돌을 막아야 한다.
    /// - 검증 내용: restored pinned id와 같은 current unpinned tab을 병합 전 제외
    /// - 사전 조건: 현재 window에는 same id unpinned tab이 있고 restored state에는 same id pinned tab이 있음
    /// - 기대 결과: same id tab은 pinned 항목으로 한 번만 남고 기존 다른 unpinned tab은 보존
    func testApplyPinnedContentTabs_filtersDuplicateUnpinnedTabIDsFromRestoredPinnedTabs() {
        let duplicateID = ContentTabID(rawValue: "shared-pin")
        let workingID = ContentTabID(rawValue: "working-tab")
        let restoredAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Restored")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: duplicateID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/LocalUnpinned"),
                    isPinned: false,
                    title: "Local",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: workingID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: workingID,
            pinnedRecords: [:],
        )
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: duplicateID,
                    page: .directory,
                    anchor: restoredAnchor,
                    isPinned: true,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: duplicateID,
            pinnedRecords: [
                duplicateID: Self.pinnedRecord(
                    id: duplicateID,
                    anchor: restoredAnchor,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [duplicateID, workingID])
        XCTAssertEqual(state.contentTabs.tabs[id: duplicateID]?.isPinned, true)
        XCTAssertEqual(state.contentTabs.tabs[id: duplicateID]?.anchor, restoredAnchor)
        XCTAssertEqual(state.contentTabs.activeTabID, workingID)
        XCTAssertEqual(Set(state.contentTabs.pinnedRecords.keys), Set([duplicateID]))
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 저장 대기 중인 local pinned tab은 global sync에서 보존
    /// local pin 저장 effect가 완료되기 전에 다른 window의 global store sync가 도착해도 optimistic pinned tab을 잃지 않아야 한다.
    /// - 검증 내용: restored store에 없는 pending pinned tab과 record를 병합 결과에 유지
    /// - 사전 조건: 현재 window에는 pending pinned tab이 있고 restored state에는 다른 pinned tab만 있음
    /// - 기대 결과: restored pinned 뒤에 pending pinned가 유지되고 pending set과 local pinned record가 남음
    func testApplyPinnedContentTabs_preservesPendingLocalPinnedTabMissingFromRestoredStore() {
        let restoredID = ContentTabID(rawValue: "restored-pin")
        let pendingID = ContentTabID(rawValue: "pending-pin")
        let workingID = ContentTabID(rawValue: "working-tab")
        let pendingAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Pending")
        let restoredAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Restored")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pendingID,
                    page: .directory,
                    anchor: pendingAnchor,
                    isPinned: true,
                    title: "Pending",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: workingID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: workingID,
            pinnedRecords: [
                pendingID: Self.pinnedRecord(
                    id: pendingID,
                    anchor: pendingAnchor,
                    title: "Pending",
                    iconName: "folder",
                ),
            ],
            pendingPinnedRecordIDs: [pendingID],
        )
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: restoredID,
                    page: .directory,
                    anchor: restoredAnchor,
                    isPinned: true,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: restoredID,
            pinnedRecords: [
                restoredID: Self.pinnedRecord(
                    id: restoredID,
                    anchor: restoredAnchor,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [restoredID, pendingID, workingID])
        XCTAssertEqual(state.contentTabs.tabs[id: pendingID]?.isPinned, true)
        XCTAssertEqual(state.contentTabs.tabs[id: pendingID]?.anchor, pendingAnchor)
        XCTAssertEqual(Set(state.contentTabs.pinnedRecords.keys), Set([restoredID, pendingID]))
        XCTAssertEqual(state.contentTabs.pendingPinnedRecordIDs, [pendingID])
        XCTAssertEqual(state.contentTabs.activeTabID, workingID)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: live sync 중 collection durable anchor 분리
    /// 저장소의 page 유형이 달라져도 현재 세션의 pinned tab과 content를 교체하지 않는지 검증한다.
    /// - 검증 내용: runtime Directory 유지, durable record는 collection file 반영
    /// - 사전 조건: active Directory runtime tab과 동일 ID의 collectionFile durable record
    /// - 기대 결과: 화면은 기존 Directory에 머물고 다음 복원용 record만 collection file로 갱신
    func testApplyPinnedContentTabs_preservesRuntimeWhenDurablePageChanges() {
        let pinnedID = ContentTabID(rawValue: "shared-pin")
        let runtimeAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let collectionURL = URL(fileURLWithPath: "/Users/test/Synced.voyagercollection")
        let durableAnchor: ContentTabPageAnchor = .collectionFile(url: collectionURL)
        let runtimeRecord = Self.pinnedRecord(
            id: pinnedID,
            anchor: runtimeAnchor,
            title: "Old",
            iconName: "folder",
        )
        var state = ContentTabTestStateBuilder.pinnedDirectoryWindowState(
            tabID: pinnedID,
            path: "/Users/test/Old",
            record: runtimeRecord,
        )
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .collection,
                    anchor: durableAnchor,
                    isPinned: true,
                    title: "Synced",
                    iconName: "rectangle.stack",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(
                    id: pinnedID,
                    page: .collection,
                    anchor: durableAnchor,
                    title: "Synced",
                    iconName: "rectangle.stack",
                ),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, runtimeAnchor)
        XCTAssertEqual(state.content.navigation.currentPath, "/Users/test/Old")
        XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID]?.anchor, durableAnchor)
    }

    /// VOY-566: pinned tab 동기화는 Finder Favorites 기반 Home Favorites를 변경하지 않음
    /// - 검증 내용: applyPinnedContentTabs 이후에도 독립적으로 로드된 Home Favorites projection 유지
    /// - 사전 조건: Home이 active이고 Finder Favorites 기반 shortcut이 로드된 상태
    /// - 기대 결과: pinned tab 목록만 교체되고 Home Favorites는 기존 shortcut 유지
    func testApplyPinnedContentTabsPreservesIndependentHomeFavorites() async {
        let homeID = ContentTabID(rawValue: "home-tab")
        let oldPinnedID = ContentTabID(rawValue: "old-pin")
        let newPinnedID = ContentTabID(rawValue: "new-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let newAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/New")
        let favoriteAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Favorite")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: oldPinnedID,
                    page: .directory,
                    anchor: oldAnchor,
                    isPinned: true,
                    title: "Old",
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
            pinnedRecords: [
                oldPinnedID: Self.pinnedRecord(
                    id: oldPinnedID,
                    anchor: oldAnchor,
                    title: "Old",
                    iconName: "folder",
                ),
            ],
        )
        state.syncContentTabSidebarItems()
        state.applyHomeFavoriteItems([
            FileManagerHomeFavoriteItem(
                id: ContentTabID(rawValue: "finder-favorite"),
                title: "Favorite",
                iconName: "folder",
                filePath: "/Users/test/Favorite",
                anchor: favoriteAnchor,
                page: .directory,
            ),
        ])
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: newPinnedID,
                    page: .directory,
                    anchor: newAnchor,
                    isPinned: true,
                    title: "New",
                    iconName: "folder",
                ),
            ],
            activeTabID: newPinnedID,
            pinnedRecords: [
                newPinnedID: Self.pinnedRecord(
                    id: newPinnedID,
                    anchor: newAnchor,
                    title: "New",
                    iconName: "folder",
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(restoredState))

        XCTAssertEqual(store.state.content.homeFavoriteItems.map(\.title), ["Favorite"])
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: live sync 중 active pinned tab의 runtime 위치 유지
    /// 저장소 동기화가 현재 세션의 탐색 위치를 되돌리지 않고 durable record만 갱신하는지 검증한다.
    /// - 검증 내용: active tab과 content state는 runtime anchor 유지, pinned record는 저장소 anchor 반영
    /// - 사전 조건: 동일 ID의 runtime tab과 서로 다른 durable record anchor
    /// - 기대 결과: 화면은 기존 runtime 위치를 유지하고 다음 복원은 새 durable record를 사용
    func testApplyPinnedContentTabs_preservesActiveRuntimeAnchor() {
        let pinnedID = ContentTabID(rawValue: "shared-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let newAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/New")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: oldAnchor,
                    isPinned: true,
                    title: "Old",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(id: pinnedID, anchor: oldAnchor, title: "Old", iconName: "folder"),
            ],
        )
        state.content.navigation.seedInitialFolderPath("/Users/test/Old")
        state.syncActiveTabContentState()
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: newAnchor,
                    isPinned: true,
                    title: "New",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(id: pinnedID, anchor: newAnchor, title: "New", iconName: "folder"),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.activeTabID, pinnedID)
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, oldAnchor)
        XCTAssertEqual(state.content.navigation.currentPath, "/Users/test/Old")
        XCTAssertEqual(state.tabContentStates[pinnedID]?.navigation.currentPath, "/Users/test/Old")
        XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID]?.anchor, newAnchor)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: live sync 중 inactive pinned tab의 runtime 위치 유지
    /// 다른 창의 저장 이벤트가 비활성 pinned tab의 세션 상태를 초기화하지 않는지 검증한다.
    /// - 검증 내용: inactive tab과 저장된 content state는 runtime anchor 유지, pinned record는 저장소 anchor 반영
    /// - 사전 조건: 동일 ID의 inactive runtime tab과 서로 다른 durable record anchor
    /// - 기대 결과: tab 전환 시 기존 runtime 위치가 유지되고 다음 복원은 새 durable record를 사용
    func testApplyPinnedContentTabs_preservesInactiveRuntimeAnchor() {
        let homeID = ContentTabID(rawValue: "home-tab")
        let pinnedID = ContentTabID(rawValue: "shared-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let newAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/New")
        let oldRecord = Self.pinnedRecord(
            id: pinnedID,
            anchor: oldAnchor,
            title: "Old",
            iconName: "folder",
        )
        var state = ContentTabTestStateBuilder.pinnedDirectoryWindowState(
            tabID: pinnedID,
            path: "/Users/test/Old",
            record: oldRecord,
        )
        state.contentTabs.tabs.append(ContentTabItem(
            id: homeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        ))
        state.contentTabs.activeTabID = homeID
        state.content = .initialContent(for: .homeDefault)
        state.syncActiveTabContentState()
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: newAnchor,
                    isPinned: true,
                    title: "New",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(id: pinnedID, anchor: newAnchor, title: "New", iconName: "folder"),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        XCTAssertEqual(state.contentTabs.activeTabID, homeID)
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, oldAnchor)
        XCTAssertEqual(state.tabContentStates[pinnedID]?.navigation.currentPath, "/Users/test/Old")
        XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID]?.anchor, newAnchor)
    }

    func testApplyPinnedContentTabs_createsHomeFallbackWhenNoTabsRemain() throws {
        let pinnedID = ContentTabID(rawValue: "removed-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Removed")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: oldAnchor,
                    isPinned: true,
                    title: "Removed",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(id: pinnedID, anchor: oldAnchor, title: "Removed", iconName: "folder"),
            ],
        )
        state.content.navigation.seedInitialFolderPath("/Users/test/Removed")
        state.syncActiveTabContentState()
        state.contentTabs.selectedTabIDs = [pinnedID]
        state.contentTabs.selectionAnchorID = pinnedID
        let restoredState = ContentTabState(tabs: [], activeTabID: nil, pinnedRecords: [:])

        state.applyPinnedContentTabs(restoredState)

        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs[id: activeTabID]?.page, .home)
        XCTAssertFalse(state.contentTabs.tabs[id: activeTabID]?.isPinned ?? true)
        XCTAssertEqual(state.content.navigation.currentPath, "Home")
        XCTAssertEqual(state.contentTabs.selectedTabIDs, [])
        XCTAssertNil(state.contentTabs.selectionAnchorID)
        XCTAssertNil(state.tabContentStates[pinnedID])
        XCTAssertEqual(state.tabContentStates[activeTabID]?.navigation.currentPath, "Home")
    }

    func testApplyPinnedContentTabs_preservesRecentlyClosedSnapshot() {
        let pinnedID = ContentTabID(rawValue: "pinned-dir")
        let homeID = ContentTabID(rawValue: "home-tab")
        let closedAnchor = ContentTabPageAnchor.directory(path: "/Users/test/ClosedDir")
        let pinnedAnchor = ContentTabPageAnchor.directory(path: "/Users/test/PinnedDir")
        let restoredAnchor = ContentTabPageAnchor.directory(path: "/Users/test/RestoredDir")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: pinnedAnchor,
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
            recentlyClosed: ClosedContentTabSnapshot(
                page: .directory,
                anchor: closedAnchor,
                wasPinned: false,
                closedAt: Date(timeIntervalSince1970: 1000),
            ),
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(
                    id: pinnedID,
                    anchor: pinnedAnchor,
                    title: "Pinned",
                    iconName: "folder",
                ),
            ],
        )
        let restoredState = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: pinnedID,
                    page: .directory,
                    anchor: restoredAnchor,
                    isPinned: true,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
            activeTabID: pinnedID,
            pinnedRecords: [
                pinnedID: Self.pinnedRecord(
                    id: pinnedID,
                    anchor: restoredAnchor,
                    title: "Restored",
                    iconName: "folder",
                ),
            ],
        )

        state.applyPinnedContentTabs(restoredState)

        // recentlyClosed 보존 검증
        XCTAssertEqual(state.contentTabs.recentlyClosed?.page, .directory)
        XCTAssertEqual(state.contentTabs.recentlyClosed?.anchor, closedAnchor)
        XCTAssertNotNil(state.contentTabs.recentlyClosed?.closedAt)

        // pinned tab runtime 및 durable record 분리 검증
        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [pinnedID, homeID])
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, pinnedAnchor)
        XCTAssertEqual(state.contentTabs.pinnedRecords[pinnedID]?.anchor, restoredAnchor)

        // unpinned tab 보존 검증
        XCTAssertEqual(state.contentTabs.tabs[id: homeID]?.isPinned, false)

        // active tab 유지 검증
        XCTAssertEqual(state.contentTabs.activeTabID, homeID)
    }

    func testPinnedRecordRestore_rehydratesPinnedTabs() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "home-1",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.count, 3)
        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["home-1", "dir-1"])
        XCTAssertEqual(result.state.pinnedRecords.count, 2)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.isPinned, false)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 빈 store로 restore 시 withHomeTab()과 동일한 구조
    /// 빈 store로 복원하면 withHomeTab()과 같은 초기 상태가 반환됨을 검증한다.
    /// - 검증 내용: tabs 1개, active, isPinned false, home page
    /// - 사전 조건: 빈 store
    /// - 기대 결과: withHomeTab()과 동일한 구조의 기본 상태
    func testPinnedRecordRestore_emptyStoreFallsBackToHome() {
        let store = ContentTabPinnedRecordStore(records: [])
        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.count, 1)
        XCTAssertEqual(result.state.activeTabID, result.state.tabs.first?.id)
        XCTAssertEqual(result.state.tabs.first?.isPinned, false)
        XCTAssertEqual(result.state.tabs.first?.page, .home)
        XCTAssertEqual(result.state.tabs.first?.anchor, .homeDefault)
        XCTAssertFalse(result.didCompact)
        XCTAssertEqual(result.droppedCount, 0)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 호환되지 않는 page/anchor 조합 record 필터링
    /// 올바르지 않은 page/anchor 조합을 가진 record가 restore 과정에서 제외됨을 검증한다.
    /// - 검증 내용: invalid record 3개 제외, valid record 2개만 복원
    /// - 사전 조건: 2 valid + 3 invalid (home+directory, directory+homeDefault, aiChat+homeDefault)
    /// - 기대 결과: 2개만 복원, droppedCount 3
    func testPinnedRecordRestore_filtersInvalidRecords() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "valid-1",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "invalid-1",
                page: .home,
                anchor: .directory(path: "/test"),
                title: nil,
                iconName: nil,
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "invalid-2",
                page: .directory,
                anchor: .homeDefault,
                title: nil,
                iconName: nil,
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "invalid-3",
                page: .aiChat,
                anchor: .homeDefault,
                title: nil,
                iconName: nil,
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "valid-2",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.count, 3)
        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["valid-1", "valid-2"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.isPinned, false)
        XCTAssertEqual(result.droppedCount, 3)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 복원 불가능한 anchor record 필터링
    /// WindowManager가 파일 존재 검증을 주입하면 삭제된 Directory/Collection file record가 제외됨을 검증한다.
    /// - 검증 내용: isRestorableAnchor == false인 record 제외, didCompact true
    /// - 사전 조건: valid 1개 + inaccessible directory 1개 + inaccessible collection file 1개
    /// - 기대 결과: valid record만 복원되고 droppedCount 2
    func testPinnedRecordRestore_filtersUnrestorableAnchors() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "valid-dir",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "deleted-dir",
                page: .directory,
                anchor: .directory(path: "/Users/test/Deleted"),
                title: "Deleted",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "deleted-collection",
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Deleted.voyagercollection")),
                title: "Deleted Collection",
                iconName: "rectangle.stack",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store) { anchor in
            anchor == .directory(path: "/Users/test/Documents")
        }

        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["valid-dir"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.droppedCount, 2)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: maxTabs 초과 record 제외
    /// maxTabs(1)을 초과하는 3개 record 중 첫 1개만 복원되고 나머지는 dropped됨을 검증한다.
    /// - 검증 내용: 첫 1개만 복원, 나머지 2개 dropped
    /// - 사전 조건: 3개 valid record, maxTabs=1
    /// - 기대 결과: 1개만 복원, droppedCount 2
    func testPinnedRecordRestore_excludesExcessRecordsOverMaxTabs() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "rec-1",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "rec-2",
                page: .directory,
                anchor: .directory(path: "/test/1"),
                title: "Dir 1",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "rec-3",
                page: .directory,
                anchor: .directory(path: "/test/2"),
                title: "Dir 2",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store, maxTabs: 1)

        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["rec-1"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertEqual(result.droppedCount, 2)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 중복 record id는 제외
    /// 동일한 id를 가진 record 중 첫 번째만 유지되고 중복은 제외됨을 검증한다.
    /// - 검증 내용: 중복 제외 후 첫 번째만 유지, didCompact true
    /// - 사전 조건: 동일 id("same-id")를 가진 2개 record
    /// - 기대 결과: 1개만 복원, didCompact true, droppedCount 1
    func testPinnedRecordRestore_excludesDuplicateRecordIds() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "same-id",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "same-id",
                page: .directory,
                anchor: .directory(path: "/test"),
                title: "Dir",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["same-id"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.droppedCount, 1)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: restore 불가 lightweight record 제외
    /// Recents/Computer virtual collection과 AI Chat처럼 content 복원 경로가 없는 record는 보존 대상에서 제외한다.
    /// - 검증 내용: virtualCollection/aiChat record 제외, collectionFile + home record 유지
    /// - 사전 조건: collectionFile, virtualCollection("Recents"), virtualCollection("Wonsik Mac"), aiChat, home record
    /// - 기대 결과: 복원 가능한 2개만 유지, droppedCount 3
    func testPinnedRecordRestore_skipsVirtualCollectionAndAIChatRecords() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "valid-1",
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/test")),
                title: "Collection",
                iconName: "rectangle.stack",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "skip-1",
                page: .collection,
                anchor: .virtualCollection(id: "Recents"),
                title: "Recents",
                iconName: "clock",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "skip-2",
                page: .collection,
                anchor: .virtualCollection(id: "Wonsik Mac"),
                title: "Wonsik Mac",
                iconName: "desktopcomputer",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "skip-ai",
                page: .aiChat,
                anchor: .aiChat(sessionID: "chat-1"),
                title: "AI Chat",
                iconName: "bubble.right",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "valid-2",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["valid-1", "valid-2"])
        XCTAssertEqual(result.state.tabs[0].anchor, .collectionFile(url: URL(fileURLWithPath: "/test")))
        XCTAssertEqual(result.state.tabs[1].page, .home)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.isPinned, false)
        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.droppedCount, 3)
    }

    /// VOY-566: Home Favorites projection은 Finder Favorites의 Directory/Collection만 노출함
    func testHomeFavoritesProjectionMapsFinderFavoritesAndExcludesUnsupportedFiles() {
        let directoryURL = URL(fileURLWithPath: "/Users/test/Documents")
        let collectionURL = URL(fileURLWithPath: "/Users/test/Photos.voycoll")
        let fileURL = URL(fileURLWithPath: "/Users/test/notes.txt")
        let favorites = [
            SidebarItems.FavoriteItem(name: "Documents", url: directoryURL, iconName: "folder"),
            SidebarItems.FavoriteItem(name: "Photos", url: collectionURL, iconName: "rectangle.stack"),
            SidebarItems.FavoriteItem(name: "notes.txt", url: fileURL, iconName: "doc"),
        ]

        let projected = FileManagerHomeDashboardProjection.homeFavorites(
            from: favorites,
            fileExistsWithIsDirectory: { path, isDirectory in
                guard [directoryURL.path, collectionURL.path, fileURL.path].contains(path) else { return false }
                isDirectory?.pointee = ObjCBool(path != fileURL.path)
                return true
            },
        )

        XCTAssertEqual(projected.map(\.title), ["Documents", "Photos"])
        XCTAssertEqual(projected.map(\.anchor), [
            .directory(path: directoryURL.path),
            .collectionFile(url: collectionURL),
        ])
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: record 순서와 메타데이터 보존
    /// Directory와 Collection record가 입력 순서대로 복원되고
    /// title/iconName/pinnedAt 메타데이터가 보존됨을 검증한다.
    /// - 검증 내용: 3개 record 순서 유지, 메타데이터 일치
    /// - 사전 조건: 3개 record (directory 2개, collection 1개)
    /// - 기대 결과: 순서 및 메타데이터 보존
    func testPinnedRecordRestore_preservesRecordOrderAndMetadata() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "col-1",
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Photos")),
                title: "Photos",
                iconName: "rectangle.stack",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "dir-2",
                page: .directory,
                anchor: .directory(path: "/Users/test/Downloads"),
                title: "Downloads",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.count, 4)
        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["dir-1", "col-1", "dir-2"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.isPinned, false)

        // Directory (첫 번째)
        let firstID = result.state.tabs[0].id
        XCTAssertEqual(result.state.tabs[0].page, .directory)
        XCTAssertEqual(result.state.tabs[0].anchor, .directory(path: "/Users/test/Documents"))
        XCTAssertEqual(result.state.tabs[0].title, "Documents")
        XCTAssertEqual(result.state.tabs[0].iconName, "folder")
        XCTAssertEqual(result.state.pinnedRecords[firstID]?.pinnedAt, pinnedAt)

        // Collection (두 번째)
        let secondID = result.state.tabs[1].id
        XCTAssertEqual(result.state.tabs[1].page, .collection)
        XCTAssertEqual(result.state.tabs[1].anchor, .collectionFile(url: URL(fileURLWithPath: "/Users/test/Photos")))
        XCTAssertEqual(result.state.tabs[1].title, "Photos")
        XCTAssertEqual(result.state.tabs[1].iconName, "rectangle.stack")
        XCTAssertEqual(result.state.pinnedRecords[secondID]?.pinnedAt, pinnedAt)

        // Directory (세 번째)
        let thirdID = result.state.tabs[2].id
        XCTAssertEqual(result.state.tabs[2].page, .directory)
        XCTAssertEqual(result.state.tabs[2].anchor, .directory(path: "/Users/test/Downloads"))
        XCTAssertEqual(result.state.tabs[2].title, "Downloads")
        XCTAssertEqual(result.state.tabs[2].iconName, "folder")
        XCTAssertEqual(result.state.pinnedRecords[thirdID]?.pinnedAt, pinnedAt)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 기존 pinned record 갱신 시 저장 순서 보존
    /// pinned tab에서 이동이 발생해 record가 갱신되어도 새 창 restore 순서가 아래로 밀리지 않음을 검증한다.
    /// - 검증 내용: 기존 id 갱신은 원래 index를 유지, 신규 id만 끝에 추가
    /// - 사전 조건: 3개 record 중 두 번째 record 갱신, 이후 신규 record 추가
    /// - 기대 결과: 갱신 record는 두 번째 위치 유지, 신규 record는 마지막 위치
    func testUpsertPinnedRecord_preservesExistingRecordOrder() {
        let pinnedAt = Self.pinnedAt
        let existingStore = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "col-1",
                page: .collection,
                anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Photos")),
                title: "Photos",
                iconName: "rectangle.stack",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "ai-1",
                page: .aiChat,
                anchor: .aiChat(sessionID: "chat-1"),
                title: "AI Chat",
                iconName: "bubble.right",
                pinnedAt: pinnedAt,
            ),
        ])
        let updatedCollection = ContentTabPinnedRecord(
            id: "col-1",
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/UpdatedPhotos")),
            title: "Updated Photos",
            iconName: "rectangle.stack",
            pinnedAt: pinnedAt.addingTimeInterval(10),
        )
        let newDirectory = ContentTabPinnedRecord(
            id: "dir-2",
            page: .directory,
            anchor: .directory(path: "/Users/test/Downloads"),
            title: "Downloads",
            iconName: "folder",
            pinnedAt: pinnedAt.addingTimeInterval(20),
        )

        let updatedStore = upsertPinnedRecord(updatedCollection, in: existingStore)
        let appendedStore = upsertPinnedRecord(newDirectory, in: updatedStore)

        XCTAssertEqual(updatedStore.records.map(\.id), ["dir-1", "col-1", "ai-1"])
        XCTAssertEqual(
            updatedStore.records[1].anchor,
            .collectionFile(url: URL(fileURLWithPath: "/Users/test/UpdatedPhotos")),
        )
        XCTAssertEqual(appendedStore.records.map(\.id), ["dir-1", "col-1", "ai-1", "dir-2"])
    }

    // MARK: - CTM-003-pinned_record_restore_compaction

    /// CTM-003-pinned_record_restore_compaction: 중복 ID compaction 후 유효 record만 남고 didCompact가 true
    /// 동일한 id를 가진 record가 있는 store에서 restore를 수행하면
    /// 중복이 제거되고 didCompact=true, 유효 record만 복원됨을 검증한다.
    /// - 검증 내용: 중복 ID 제거 후 첫 번째 record만 유지, didCompact true, droppedCount 1
    /// - 사전 조건: 동일 id("dup-id")를 가진 2개 record
    /// - 기대 결과: 1개 record만 복원, didCompact true, droppedCount 1
    func testPinnedRecordRestoreCompactsDuplicateIds() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dup-id",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "dup-id",
                page: .directory,
                anchor: .directory(path: "/test"),
                title: "Dir",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let result = ContentTabState.restoringPinnedRecords(from: store)

        XCTAssertEqual(result.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["dup-id"])
        XCTAssertEqual(result.state.tabs[id: result.state.activeTabID ?? ContentTabID(rawValue: "")]?.page, .home)
        XCTAssertTrue(result.didCompact)
        XCTAssertEqual(result.droppedCount, 1)
        // 유일하게 남은 record는 첫 번째 record의 메타데이터 유지
        XCTAssertEqual(result.state.tabs[0].page, .home)
        XCTAssertEqual(result.state.tabs[0].anchor, .homeDefault)
        XCTAssertEqual(result.state.tabs[0].title, "Home")
    }

    /// CTM-003-pinned_record_restore_compaction: compaction save 실패해도 복원된 state는 유지됨
    /// saveStore가 throw해도 makeInitial(path: nil, contentTabs:)에 전달된 복원 state는
    /// 유지됨을 FileManager feature state 레벨에서 검증한다.
    /// - 검증 내용: 중복 ID store → restore 결과를 makeInitial에 전달 → pinned tab 포함
    /// - 사전 조건: 중복 ID 1개 포함 store (2중 1개만 유효)
    /// - 기대 결과: makeInitial 결과에 1개 pinned tab 존재, pinnedRecords에 entry 존재
    func testPinnedRecordRestoreCompactionFailureStillRestoresValidTabs() {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "dup-id",
                page: .home,
                anchor: .homeDefault,
                title: "Home",
                iconName: "house",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "dup-id",
                page: .directory,
                anchor: .directory(path: "/test"),
                title: "Dir",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
        ])

        let restoreResult = ContentTabState.restoringPinnedRecords(from: store)
        XCTAssertTrue(restoreResult.didCompact)
        XCTAssertEqual(restoreResult.state.tabs.filter(\.isPinned).map(\.id.rawValue), ["dup-id"])

        // saveStore가 throw해도 makeInitial은 계속됨을 확인
        // (실제 WindowManager에서는 try? saveStore로 처리되므로 실패해도 흐름은 유지됨)
        let windowState = FileManagerFeature.State.makeInitial(
            path: nil,
            contentTabs: restoreResult.state,
        )

        // 복원된 pinned tab이 window state에 포함되어야 함
        // (makeInitial의 bootstrapping이 pinnedRecords를 보존하므로
        // pinnedRecords dict도 함께 유지됨)
        XCTAssertEqual(windowState.contentTabs.tabs.filter(\.isPinned).map(\.id.rawValue), ["dup-id"])
        XCTAssertEqual(
            windowState.contentTabs.tabs[id: windowState.contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?.page,
            .home,
        )
        XCTAssertEqual(
            windowState.contentTabs.tabs[id: windowState.contentTabs.activeTabID ?? ContentTabID(rawValue: "")]?
                .isPinned,
            false,
        )
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: restore 후 unpin이 원래 persisted record ID를 사용함
    /// restoringPinnedRecords로 복원된 pinned tab을 unpin하면
    /// 원래 persisted store의 record ID가 제거됨을 검증한다.
    /// - 검증 내용: restore된 tab unpin 시 updateStore가 record ID를 정확히 제거
    /// - 사전 조건: 2개 record restore 후 unpin
    /// - 기대 결과: saveStore에 unpin한 record ID가 없음
    func testPinnedRecordRestore_unpinUsesOriginalPersistedRecordId() async {
        let pinnedAt = Self.pinnedAt
        let store = ContentTabPinnedRecordStore(records: [
            ContentTabPinnedRecord(
                id: "orig-dir-1",
                page: .directory,
                anchor: .directory(path: "/Users/test/Documents"),
                title: "Documents",
                iconName: "folder",
                pinnedAt: pinnedAt,
            ),
            ContentTabPinnedRecord(
                id: "orig-dir-2",
                page: .directory,
                anchor: .directory(path: "/Users/test/Downloads"),
                title: "Downloads",
                iconName: "arrow.down",
                pinnedAt: pinnedAt,
            ),
        ])

        let restore = ContentTabState.restoringPinnedRecords(from: store)
        let tabID = restore.state.tabs[0].id

        // tab[0]의 id.rawValue가 원래 persisted ID여야 함 (새 UUID가 아님)
        XCTAssertEqual(tabID.rawValue, "orig-dir-1")

        let recorder = PinnedRecordStoreRecorder()
        // updateStore가 참조할 기존 persisted store에 2개 record가 있다고 가정
        _ = recorder.record(store)

        let testStore = TestStore(initialState: restore.state) {
            CTM003PinnedPersistenceHarness()
        } withDependencies: {
            $0.date = DateGenerator { pinnedAt }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let result = try transform(recorder.latestStore())
                _ = recorder.record(result)
            }
        }

        // restore된 pinned tab unpin
        await testStore.send(.unpin(tabID)) { state in
            var unpinnedTab = state.tabs[id: tabID]!
            unpinnedTab.isPinned = false
            state.tabs.remove(id: tabID)
            state.tabs.append(unpinnedTab)
            state.pinnedRecords[tabID] = nil
            state.pendingPinnedRecordIDs.insert(tabID)
        }
        await testStore.receive(\.pinnedRecordPersistenceRequested)
        await testStore.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(tabID)
        }

        // saveStore 결과에 orig-dir-1 record가 없어야 함 (unpin으로 제거됨)
        let ids = recorder.stores().last?.records.map(\.id) ?? []
        XCTAssertFalse(ids.contains("orig-dir-1"), "unpin한 record ID가 persistence에 남아 있으면 안 됨")
        XCTAssertTrue(ids.contains("orig-dir-2"), "unpin하지 않은 record ID는 persistence에 유지되어야 함")
    }

    // MARK: - CTM-003-unpin_selected_content_tabs

    /// CTM-003-unpin_selected_content_tabs: selected pinned clicked row는 bulk Unpin presentation을 노출한다.
    /// clicked row의 현재 pinned 상태가 전체 선택의 target을 unpinned로 결정하는 메뉴 계약을 검증한다.
    /// - 검증 내용: exact title, accessibility identifier, enabled state, command와 delegate target
    /// - 사전 조건: clicked pinned row가 normalized live selection 2개에 포함되고 start gate가 열려 있음
    /// - 기대 결과: `Unpin 2 Tabs`, unique identifier, enabled, target `.unpinned`
    func testSelectedPinnedRowPresentsBulkUnpinCommand() {
        let clickedID = ContentTabID(rawValue: "selected-pinned")
        let presentation = ContentTabPinPresentation(
            clickedTabID: clickedID,
            isPinned: true,
            validSelectedTabIDs: [clickedID, ContentTabID(rawValue: "selected-peer")],
            isPinMutationEnabled: true,
            isSingleUnpinEnabled: true,
        )

        XCTAssertEqual(presentation.title, "Unpin 2 Tabs")
        XCTAssertEqual(presentation.accessibilityIdentifier, "unpin-selected-content-tabs")
        XCTAssertTrue(presentation.isEnabled)
        guard case let .setSelectedContentTabsPinned(target) = presentation.command else {
            return XCTFail("selected pinned row should keep the bulk Unpin command")
        }
        XCTAssertEqual(target, .unpinned)
        guard case let .setSelectedContentTabsPinned(delegateTarget) = presentation.viewAction else {
            return XCTFail("bulk Unpin should map to the semantic Sidebar View action")
        }
        XCTAssertEqual(delegateTarget, .unpinned)
    }

    /// CTM-003-unpin_selected_content_tabs: Sidebar View pin 계열 intent는 기존 Delegate로 각각 한 번 relay한다.
    /// View가 Window 경계 action을 직접 만들지 않고 Sidebar reducer가 semantic outward event를 소유하는지 검증한다.
    /// - 검증 내용: single Pin, single Unpin, selected bulk target별 View -> Delegate 1:1 routing과 state 불변
    /// - 사전 조건: 기본 Sidebar state와 세 pin 계열 View action
    /// - 기대 결과: 각 action마다 대응 Delegate 하나만 receive하고 추가 action이나 state 변경이 없다.
    func testSidebarPinViewActionsRelayExactlyOnceToDelegate() async {
        let tabID = ContentTabID(rawValue: "sidebar-view-pin-route")
        let routes: [FileManagerSidebarAction.View] = [
            .pinContentTab(tabID),
            .unpinContentTab(tabID),
            .setSelectedContentTabsPinned(target: .pinned),
            .setSelectedContentTabsPinned(target: .unpinned),
        ]

        for (index, viewAction) in routes.enumerated() {
            let initialState = FileManagerSidebarFeature.State()
            let store = TestStore(initialState: initialState) {
                FileManagerSidebarFeature()
            }

            await store.send(.view(viewAction))
            await store.receive { action in
                switch (index, action) {
                case (0, .delegate(.pinContentTab(tabID))),
                     (1, .delegate(.unpinContentTab(tabID))):
                    tabID == ContentTabID(rawValue: "sidebar-view-pin-route")
                case (2, .delegate(.setSelectedContentTabsPinned(target: .pinned))),
                     (3, .delegate(.setSelectedContentTabsPinned(target: .unpinned))):
                    true
                default:
                    false
                }
            }
            XCTAssertEqual(store.state, initialState)
            await store.finish()
        }
    }

    /// CTM-003-unpin_selected_content_tabs: Sidebar bulk Unpin delegate는 Window request를 정확히 한 번 전달한다.
    /// presentation의 target payload가 coordinator request 경계에서 변환되거나 중복되지 않는지 검증한다.
    /// - 검증 내용: Sidebar delegate에서 `.requestSelectedContentTabPinMutation(target:)` 단일 effect
    /// - 사전 조건: target `.unpinned`와 normalized count가 2 미만인 no-start Window state
    /// - 기대 결과: payload `.unpinned` request를 한 번 receive하고 추가 action 없음
    func testBulkUnpinDelegateRoutesExactlyOneWindowRequest() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.setSelectedContentTabsPinned(target: .unpinned))))
        await store.receive(\.requestSelectedContentTabPinMutation, .unpinned)
        await store.finish()
    }

    // MARK: - CTM-003-pin_selected_content_tabs

    /// CTM-003-pin_selected_content_tabs: selected unpinned clicked row는 bulk Pin presentation을 노출한다.
    /// clicked row의 현재 unpinned 상태가 전체 선택의 target을 pinned로 결정하는 메뉴 계약을 검증한다.
    /// - 검증 내용: exact title, accessibility identifier, enabled state, command와 delegate target
    /// - 사전 조건: clicked unpinned row가 normalized live selection 2개에 포함되고 start gate가 열려 있음
    /// - 기대 결과: `Pin 2 Tabs`, unique identifier, enabled, target `.pinned`
    func testSelectedUnpinnedRowPresentsBulkPinCommand() {
        let clickedID = ContentTabID(rawValue: "selected-unpinned")
        let presentation = ContentTabPinPresentation(
            clickedTabID: clickedID,
            isPinned: false,
            validSelectedTabIDs: [clickedID, ContentTabID(rawValue: "selected-peer")],
            isPinMutationEnabled: true,
            isSingleUnpinEnabled: true,
        )

        XCTAssertEqual(presentation.title, "Pin 2 Tabs")
        XCTAssertEqual(presentation.accessibilityIdentifier, "pin-selected-content-tabs")
        XCTAssertTrue(presentation.isEnabled)
        guard case let .setSelectedContentTabsPinned(target) = presentation.command else {
            return XCTFail("selected unpinned row should keep the bulk Pin command")
        }
        XCTAssertEqual(target, .pinned)
        guard case let .setSelectedContentTabsPinned(delegateTarget) = presentation.viewAction else {
            return XCTFail("bulk Pin should map to the semantic Sidebar View action")
        }
        XCTAssertEqual(delegateTarget, .pinned)
    }

    /// CTM-003-pin_selected_content_tabs: unselected row와 normalized count 0/1은 exact single Pin/Unpin으로 fallback한다.
    /// bulk eligibility가 없을 때 기존 clicked-row command와 identifier를 그대로 보존하는지 검증한다.
    /// - 검증 내용: unselected/count 0/1의 title, identifier, enabled state, single View payload
    /// - 사전 조건: 2-selection 밖 unpinned row, empty selection unpinned row, 1-selection pinned row
    /// - 기대 결과: row별 `Pin`/`Unpin`과 tab ID 기반 single View action이 유지됨
    func testPinPresentationFallsBackToExistingSingleCommands() {
        let clickedID = ContentTabID(rawValue: "single-clicked")
        let unselected = ContentTabPinPresentation(
            clickedTabID: clickedID,
            isPinned: false,
            validSelectedTabIDs: [
                ContentTabID(rawValue: "selected-a"),
                ContentTabID(rawValue: "selected-b"),
            ],
            isPinMutationEnabled: false,
            isSingleUnpinEnabled: false,
        )
        let empty = ContentTabPinPresentation(
            clickedTabID: clickedID,
            isPinned: false,
            validSelectedTabIDs: [],
            isPinMutationEnabled: false,
            isSingleUnpinEnabled: false,
        )
        let countOnePinned = ContentTabPinPresentation(
            clickedTabID: clickedID,
            isPinned: true,
            validSelectedTabIDs: [clickedID],
            isPinMutationEnabled: false,
            isSingleUnpinEnabled: true,
        )

        for presentation in [unselected, empty] {
            XCTAssertEqual(presentation.title, "Pin")
            XCTAssertEqual(presentation.accessibilityIdentifier, "pin-content-tab-\(clickedID)")
            XCTAssertTrue(presentation.isEnabled)
            guard case let .pinContentTab(tabID) = presentation.viewAction else {
                return XCTFail("unpinned single fallback should retain pinContentTab")
            }
            XCTAssertEqual(tabID, clickedID)
        }
        XCTAssertEqual(countOnePinned.title, "Unpin")
        XCTAssertEqual(countOnePinned.accessibilityIdentifier, "unpin-content-tab-\(clickedID)")
        XCTAssertTrue(countOnePinned.isEnabled)
        guard case let .unpinContentTab(tabID) = countOnePinned.viewAction else {
            return XCTFail("pinned single fallback should retain unpinContentTab")
        }
        XCTAssertEqual(tabID, clickedID)
    }

    /// CTM-003-pin_selected_content_tabs: busy bulk는 disabled bulk intent를 유지하고 single로 우회하지 않는다.
    /// stale UI enablement와 무관하게 reducer gate가 authoritative인 동안 presentation도 bulk identity를 보존하는지 검증한다.
    /// - 검증 내용: 양 target의 exact bulk title, identifier, disabled state, selected View payload
    /// - 사전 조건: clicked row가 normalized 2-selection에 포함되고 `canStartSelectedContentTabPinMutation == false`
    /// - 기대 결과: `Pin 2 Tabs`/`Unpin 2 Tabs` bulk command가 disabled이며 single command가 생성되지 않음
    func testBusyBulkPinPresentationRemainsBulkAndDisabled() {
        let clickedID = ContentTabID(rawValue: "busy-clicked")
        let selectedIDs: Set<ContentTabID> = [clickedID, ContentTabID(rawValue: "busy-peer")]
        let presentations = [
            ContentTabPinPresentation(
                clickedTabID: clickedID,
                isPinned: false,
                validSelectedTabIDs: selectedIDs,
                isPinMutationEnabled: false,
                isSingleUnpinEnabled: true,
            ),
            ContentTabPinPresentation(
                clickedTabID: clickedID,
                isPinned: true,
                validSelectedTabIDs: selectedIDs,
                isPinMutationEnabled: false,
                isSingleUnpinEnabled: true,
            ),
        ]

        XCTAssertEqual(presentations.map(\.title), ["Pin 2 Tabs", "Unpin 2 Tabs"])
        XCTAssertEqual(
            presentations.map(\.accessibilityIdentifier),
            ["pin-selected-content-tabs", "unpin-selected-content-tabs"],
        )
        XCTAssertTrue(presentations.allSatisfy { !$0.isEnabled })
        for (presentation, expectedTarget) in zip(
            presentations,
            [SelectedContentTabPinMutationTargetState.pinned, .unpinned],
        ) {
            guard case let .setSelectedContentTabsPinned(target) = presentation.viewAction else {
                return XCTFail("busy bulk must not fall back to a single View action")
            }
            XCTAssertEqual(target, expectedTarget)
        }
    }

    /// CTM-003-pin_selected_content_tabs: bulk Pin과 single Unpin은 각자의 authoritative gate를 사용한다.
    /// close gate와 pin-mutation gate가 달라도 row presentation이 command별 source를 혼동하지 않는지 검증한다.
    /// - 검증 내용: bulk는 `isPinMutationEnabled`, single Unpin은 `isCloseEnabled`만 반영
    /// - 사전 조건: 두 gate 값을 서로 반대로 구성한 interaction surface
    /// - 기대 결과: bulk enablement는 close gate와 무관하고 single Unpin은 pin gate와 무관함
    func testPinPresentationUsesDedicatedPinMutationGateAndSeparateSingleUnpinGate() {
        let clickedID = ContentTabID(rawValue: "gate-clicked")
        let selectedIDs: Set<ContentTabID> = [clickedID, ContentTabID(rawValue: "gate-peer")]
        let disabledBulk = makePinPresentation(
            clickedTabID: clickedID,
            validSelectedTabIDs: selectedIDs,
            isPinned: false,
            isCloseEnabled: true,
            isPinMutationEnabled: false,
        )
        let enabledBulk = makePinPresentation(
            clickedTabID: clickedID,
            validSelectedTabIDs: selectedIDs,
            isPinned: true,
            isCloseEnabled: false,
            isPinMutationEnabled: true,
        )
        let singleUnpin = makePinPresentation(
            clickedTabID: clickedID,
            validSelectedTabIDs: [clickedID],
            isPinned: true,
            isCloseEnabled: false,
            isPinMutationEnabled: true,
        )

        XCTAssertFalse(disabledBulk.isEnabled)
        guard case .setSelectedContentTabsPinned = disabledBulk.command else {
            return XCTFail("disabled dedicated pin gate must retain bulk command")
        }
        XCTAssertTrue(enabledBulk.isEnabled)
        guard case .setSelectedContentTabsPinned = enabledBulk.command else {
            return XCTFail("enabled dedicated pin gate must retain bulk command")
        }
        XCTAssertFalse(singleUnpin.isEnabled)
        guard case .unpinContentTab = singleUnpin.command else {
            return XCTFail("count-one fallback must retain single Unpin and close gate")
        }
    }

    /// CTM-003-pin_selected_content_tabs: Sidebar bulk Pin delegate는 Window request를 정확히 한 번 전달한다.
    /// presentation의 target payload가 coordinator request 경계에서 변환되거나 중복되지 않는지 검증한다.
    /// - 검증 내용: Sidebar delegate에서 `.requestSelectedContentTabPinMutation(target:)` 단일 effect
    /// - 사전 조건: target `.pinned`와 normalized count가 2 미만인 no-start Window state
    /// - 기대 결과: payload `.pinned` request를 한 번 receive하고 추가 action 없음
    func testBulkPinDelegateRoutesExactlyOneWindowRequest() async {
        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerWindowRoutingReducer()
        }

        await store.send(.sidebar(.delegate(.setSelectedContentTabsPinned(target: .pinned))))
        await store.receive(\.requestSelectedContentTabPinMutation, .pinned)
        await store.finish()
    }

    /// CTM-003-pin_selected_content_tabs: 실행 시점 live selection을 pinned-first 순서로 동결한다.
    /// stale selection identity를 제거하고 same-state와 unsupported live tab도 total에 유지하는 시작 계약을 검증한다.
    /// - 검증 내용: request의 target state, frozen ordered IDs, cursor/current/count 초기값
    /// - 사전 조건: pinned 1개, unpinned Directory 1개, unsupported Home 1개와 stale selected ID
    /// - 기대 결과: stale ID만 제외한 pinned-first 3개가 coordinator total로 동결됨
    func testPinSelectedRequestFreezesNormalizedPinnedFirstTargets() async {
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 1))
        let fixture = selectedPinMutationFixture()
        var initialState = fixture.state
        initialState.contentTabs.selectedTabIDs.insert(ContentTabID(rawValue: "stale-selected"))
        let store = TestStore(initialState: initialState) {
            CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: request 순간 frozen coordinator와 전체 완료 결과에 집중함
        store.exhaustivity = .off

        await store.send(.requestSelectedContentTabPinMutation(target: .pinned)) {
            $0.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
                operationID: operationID,
                target: .pinned,
                orderedTargetIDs: [fixture.pinnedID, fixture.unpinnedID, fixture.unsupportedID],
            )
        }
        await store.skipReceivedActions()
        await store.finish()
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
    }

    /// CTM-003-pin_selected_content_tabs: all-unpinned Pin을 기존 single persistence terminal로 직렬 완료한다.
    /// wrapper가 child reducer를 한 번씩 실행하고 정상 completion count invariant와 state preservation을 지키는지 검증한다.
    /// - 검증 내용: 두 Pin success, total=count invariant, aggregate sync 없음, selection/owner snapshot 보존
    /// - 사전 조건: selected Directory 2개와 deterministic applied persistence
    /// - 기대 결과: 두 tab만 pinned, success=2, failure/remaining=0이며 batch coordinator가 정리됨
    func testPinSelectedSerializesSinglePinTerminalsAndPreservesWindowState() async {
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2))
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let originalContent = fixture.state.content
        let originalInspector = fixture.state.inspector
        let originalTabContentStates = fixture.state.tabContentStates
        let originalSelection = fixture.state.contentTabs.selectedTabIDs
        let originalAnchor = fixture.state.contentTabs.selectionAnchorID
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: fixture.state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .selectedPinMutationBatchCompleted(result) = action {
                    completedResults.withValue { $0.append(result) }
                }
                return CTM003FileManagerPersistenceHarness().reduce(into: &state, action: action)
            }
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: correlated child terminal의 동적 intent/generation보다 최종 직렬 결과와 보존 계약을 검증함
        store.exhaustivity = .off

        await store.send(.requestSelectedContentTabPinMutation(target: .pinned))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        XCTAssertTrue(fixture.orderedIDs.allSatisfy { store.state.contentTabs.tabs[id: $0]?.isPinned == true })
        XCTAssertEqual(completedResults.value, [
            .init(
                operationID: operationID,
                target: .pinned,
                totalCount: 2,
                successCount: 2,
                failureCount: 0,
                remainingCount: 0,
            ),
        ])
        XCTAssertEqual(store.state.content, originalContent)
        XCTAssertEqual(store.state.inspector, originalInspector)
        XCTAssertEqual(store.state.tabContentStates, originalTabContentStates)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, originalSelection)
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, originalAnchor)
    }

    // MARK: - CTM-003-unpin_selected_content_tabs

    /// CTM-003-unpin_selected_content_tabs: all-pinned Unpin을 frozen 순서대로 직렬 완료한다.
    /// legacy-compatible single Unpin terminal을 재사용하면서 active/previous active와 live selection을 보존하는지 검증한다.
    /// - 검증 내용: 두 Unpin success와 unpinned tail processing order, coordinator cleanup
    /// - 사전 조건: selected pinned Directory 2개와 applied persistence
    /// - 기대 결과: 두 tab이 frozen 순서의 unpinned tail이 되고 selection/active identity는 유지됨
    func testUnpinSelectedSerializesAllPinnedTargetsAndPreservesSelection() async {
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 8))
        let fixture = allPinnedSelectedPinMutationFixture()
        let originalSelection = fixture.state.contentTabs.selectedTabIDs
        let originalAnchor = fixture.state.contentTabs.selectionAnchorID
        let originalActive = fixture.state.contentTabs.activeTabID
        let originalPrevious = fixture.state.contentTabs.previousActiveTabID
        let persistedStore = ContentTabPinnedRecordStore(
            records: fixture.orderedIDs.compactMap { fixture.state.contentTabs.pinnedRecords[$0] },
        )
        let store = TestStore(initialState: fixture.state) { CTM003FileManagerPersistenceHarness() } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(persistedStore)
                return .applied
            }
        }
        // store.exhaustivity = .off: 동적 terminal context보다 최종 직렬 Unpin ordering과 보존 상태를 검증함
        store.exhaustivity = .off

        await store.send(.requestSelectedContentTabPinMutation(target: .unpinned))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        XCTAssertEqual(store.state.contentTabs.tabs.map(\.id), fixture.orderedIDs)
        XCTAssertTrue(fixture.orderedIDs.allSatisfy { store.state.contentTabs.tabs[id: $0]?.isPinned == false })
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, originalSelection)
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, originalAnchor)
        XCTAssertEqual(store.state.contentTabs.activeTabID, originalActive)
        XCTAssertEqual(store.state.contentTabs.previousActiveTabID, originalPrevious)
    }

    // MARK: - CTM-003-pin_selected_content_tabs

    /// CTM-003-pin_selected_content_tabs: global-stale success는 local child cleanup 후 remaining으로 집계한다.
    /// wrapper success terminal을 보존하면서 app-global generation이 stale인 경우 success로 세지 않는 계약을 검증한다.
    /// - 검증 내용: local pending cleanup, remaining increment, success zero
    /// - 사전 조건: locally-current optimistic Pin과 globally-stale generation
    /// - 기대 결과: child terminal은 한 번 reduce되고 item outcome은 remaining
    func testPinSelectedGlobalStaleSuccessCompletesAsRemainingAfterLocalCleanup() async throws {
        let fixture = try globalStaleSelectedPinMutationFixture()
        let operationID = fixture.operationID
        let tabID = fixture.tabID
        let context = fixture.context
        let store = TestStore(initialState: fixture.state) { CTM003FileManagerPersistenceHarness() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentMutationGeneration = { _ in false }
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
        }

        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: tabID,
            action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
        )) {
            $0.contentTabs.pendingPinnedRecordIDs.remove(tabID)
        }
        await store.receive { action in
            guard case let .selectedPinMutationItemCompleted(
                receivedOperationID,
                receivedTabID,
                outcome,
            ) = action else { return false }
            return receivedOperationID == operationID && receivedTabID == tabID && outcome == .remaining
        } assert: {
            $0.pendingSelectedContentTabPinMutation?.cursor = 1
            $0.pendingSelectedContentTabPinMutation?.currentTabID = nil
            $0.pendingSelectedContentTabPinMutation?.remainingCount = 1
        }
        await store.receive(\.processNextSelectedContentTabPinMutation, operationID) {
            $0.pendingSelectedContentTabPinMutation = nil
        }
        await store.receive(\.selectedPinMutationBatchCompleted, .init(
            operationID: operationID,
            target: .pinned,
            totalCount: 1,
            successCount: 0,
            failureCount: 0,
            remainingCount: 1,
        ))
        await store.finish()
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
    }

    /// CTM-003-pin_selected_content_tabs: start gate는 normalized count와 pending operation 상호 배제를 적용한다.
    /// selected-close/single-close/teardown/pin persistence가 존재하면 새 coordinator가 시작되지 않는지 검증한다.
    /// - 검증 내용: 각 busy gate와 count 1 request의 exact no-op
    /// - 사전 조건: 동일 2-selection fixture에 busy state를 하나씩 주입
    /// - 기대 결과: 모든 busy state의 canStart가 false이고 count 1 request도 coordinator를 만들지 않음
    func testPinSelectedStartGateRejectsMutuallyExclusivePendingOperationsAndCountOne() async {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        var states: [FileManagerFeature.State] = []

        var selectedClose = fixture.state
        selectedClose.pendingSelectedContentTabClose = PendingSelectedContentTabClose(
            operationID: UUID(),
            orderedTargetIDs: fixture.orderedIDs,
            originalActiveTabID: fixture.orderedIDs[0],
            preferredFallbackIDs: [],
        )
        states.append(selectedClose)
        var singleClose = fixture.state
        singleClose.pendingContentTabClose = PendingContentTabClose(tabID: fixture.orderedIDs[0])
        states.append(singleClose)
        var teardown = fixture.state
        teardown.pendingContentTabTeardown = PendingContentTabTeardown(
            requestID: UUID(),
            tabID: fixture.orderedIDs[0],
            ownerID: UUID(),
        )
        states.append(teardown)
        var persistence = fixture.state
        persistence.contentTabs.pendingPinnedRecordIDs.insert(fixture.orderedIDs[0])
        states.append(persistence)
        var closing = fixture.state
        closing.isClosing = true
        states.append(closing)

        XCTAssertTrue(states.allSatisfy { !$0.canStartSelectedContentTabPinMutation })

        var countOne = fixture.state
        countOne.contentTabs.selectedTabIDs = [fixture.orderedIDs[0]]
        let store = TestStore(initialState: countOne) { CTM003FileManagerPersistenceHarness() }
        await store.send(.requestSelectedContentTabPinMutation(target: .pinned))
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
    }

    /// CTM-003-pin_selected_content_tabs: wrong operation/current tab과 stale-local terminal을 완전히 무시한다.
    /// correlation guard가 child rollback, count, cursor, projection을 모두 차단하는지 검증한다.
    /// - 검증 내용: wrapper pre-reduction operation/current/local-intent validation
    /// - 사전 조건: 첫 item 처리 중인 coordinator와 다른 operation/tab 및 stale intent terminal
    /// - 기대 결과: 세 wrapper 모두 Window/ContentTab/sidebar state를 전혀 변경하지 않음
    func testPinSelectedWrapperRejectsWrongCorrelationAndStaleLocalTerminal() async {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3))
        let wrongOperationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 4))
        var initialState = fixture.state
        initialState.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: fixture.orderedIDs,
            currentTabID: fixture.orderedIDs[0],
        )
        let staleContext = ContentTabPinnedRecordTerminalContext(
            intentID: UUID(),
            generation: ContentTabPinnedRecordMutationGeneration(tabID: fixture.orderedIDs[0], value: UUID()),
        )
        let rollback = ContentTabPinnedRecordRollbackSnapshot(
            previousIsPinned: false,
            previousPinnedRecord: nil,
            previousTabIndex: 0,
        )
        let store = TestStore(initialState: initialState) { CTM003FileManagerPersistenceHarness() }
        let originalState = store.state

        await store.send(.performSelectedContentTabPinMutation(
            operationID: wrongOperationID,
            tabID: fixture.orderedIDs[0],
            action: .pin(fixture.orderedIDs[0]),
        ))
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: fixture.orderedIDs[1],
            action: .pin(fixture.orderedIDs[1]),
        ))
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: fixture.orderedIDs[0],
            action: .pinnedRecordSaveFailed(
                tabID: fixture.orderedIDs[0],
                context: staleContext,
                rollback: rollback,
            ),
        ))

        XCTAssertEqual(store.state, originalState)
    }

    /// CTM-003-pin_selected_content_tabs: active batch 동안 direct single Pin/Unpin과 중복 process를 차단한다.
    /// reducer boundary가 wrapper 외 mutation 우회와 cursor 중복 진행을 허용하지 않는지 검증한다.
    /// - 검증 내용: direct `.contentTabs(.pin/.unpin)` 및 current item 존재 중 process no-op
    /// - 사전 조건: 첫 selected Pin item이 current인 coordinator
    /// - 기대 결과: tab state, counts, cursor, sidebar projection이 exact equality 유지
    func testPinSelectedBatchBlocksDirectSingleMutationAndDuplicateProcess() async {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5))
        var initialState = fixture.state
        initialState.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: fixture.orderedIDs,
            currentTabID: fixture.orderedIDs[0],
        )
        let store = TestStore(initialState: initialState) { CTM003FileManagerPersistenceHarness() }
        let originalState = store.state

        await store.send(.contentTabs(.pin(fixture.orderedIDs[1])))
        await store.send(.contentTabs(.unpin(fixture.orderedIDs[0])))
        await store.send(.processNextSelectedContentTabPinMutation(operationID: operationID))

        XCTAssertEqual(store.state, originalState)
    }

    /// CTM-003-pin_selected_content_tabs: active current Unpin 동안 direct close mutation을 모두 차단한다.
    /// optimistic Unpin으로 current tab이 unpinned여도 routing teardown/commit이 batch 경계를 우회하지 않는지 검증한다.
    /// - 검증 내용: requestClose/close/commitClose의 exact state no-op과 teardown effect 0회, 정상 terminal 완료
    /// - 사전 조건: active tab이 optimistic Unpin된 one-item selected coordinator
    /// - 기대 결과: close/undo/coordinator/selection 상태가 유지되고 wrapped success로 batch가 완료됨
    func testUnpinSelectedCurrentTabBlocksQueuedDirectCloseMutationsAndCompletesBatch() async {
        let fixture = currentOptimisticSelectedUnpinFixture()
        let invalidationCount = LockIsolated(0)
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: fixture.state) {
            selectedPinMatrixReducer(completedResults: completedResults)
        } withDependencies: {
            $0.uuid = .constant(matrixOperationID(group: 8, offset: 5))
            $0.undoManagerClient.invalidateOwner = { _, _ in
                invalidationCount.withValue { $0 += 1 }
                return .init(succeeded: true, availability: .init())
            }
        }
        // store.exhaustivity = .off: direct close effect 부재와 terminal 이후 aggregate completion을 함께 검증함
        store.exhaustivity = .off
        let expectedBoundary = store.state

        for action in directCloseActions(tabID: fixture.tabID) {
            await store.send(.contentTabs(action))
            assertSelectedPinCloseBoundary(
                store.state,
                equals: expectedBoundary,
                invalidationCount: invalidationCount.value,
            )
        }

        await store.send(.performSelectedContentTabPinMutation(
            operationID: fixture.operationID,
            tabID: fixture.tabID,
            action: .pinnedRecordSaveSucceeded(tabID: fixture.tabID, context: fixture.context),
        ))
        await store.skipReceivedActions()
        await store.finish()

        assertSelectedPinCompletion(completedResults, total: 1)
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        XCTAssertEqual(store.state.contentTabs.tabs[id: fixture.tabID]?.isPinned, false)
    }

    /// CTM-003-pin_selected_content_tabs: current Pin item 중 non-current unpinned tab의 queued close를 차단한다.
    /// child reduction 뒤 routing reducer가 requestClose teardown이나 close commit을 시작하지 않는지 검증한다.
    /// - 검증 내용: 세 direct close 액션의 exact boundary no-op, teardown effect 0회, frozen batch continuation
    /// - 사전 조건: 첫 item이 optimistic Pin current이고 두 번째 unpinned selected tab이 non-current
    /// - 기대 결과: queued target이 보존되고 정상 terminal 뒤 frozen 3-item batch가 모두 완료됨
    func testPinSelectedCurrentItemBlocksNonCurrentUnpinnedQueuedCloseAndContinuesBatch() async {
        let fixture = selectedPinBatchMatrixFixture()
        let operationID = matrixOperationID(group: 8, offset: 0)
        let currentTabID = fixture.orderedIDs[0]
        let queuedCloseTabID = fixture.orderedIDs[1]
        var initialState = fixture.state
        let context = prepareCurrentOptimisticSelectedPin(
            state: &initialState,
            operationID: operationID,
            orderedTargetIDs: fixture.orderedIDs,
            currentTabID: currentTabID,
        )
        initialState.windowID = matrixOperationID(group: 8, offset: 1)
        let invalidationCount = LockIsolated(0)
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: initialState) {
            selectedPinMatrixReducer(completedResults: completedResults)
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
            $0.undoManagerClient.invalidateOwner = { _, _ in
                invalidationCount.withValue { $0 += 1 }
                return .init(succeeded: true, availability: .init())
            }
        }
        // store.exhaustivity = .off: direct close effect 부재와 남은 실제 persistence chain의 완료를 검증함
        store.exhaustivity = .off
        let expectedBoundary = store.state

        for action in directCloseActions(tabID: queuedCloseTabID) {
            await store.send(.contentTabs(action))
            assertSelectedPinCloseBoundary(
                store.state,
                equals: expectedBoundary,
                invalidationCount: invalidationCount.value,
            )
        }

        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: currentTabID,
            action: .pinnedRecordSaveSucceeded(tabID: currentTabID, context: context),
        ))
        await store.skipReceivedActions()
        await store.finish()

        assertSelectedPinCompletion(completedResults, total: fixture.orderedIDs.count)
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        XCTAssertTrue(fixture.orderedIDs.allSatisfy { store.state.contentTabs.tabs[id: $0]?.isPinned == true })
    }

    /// CTM-003-pin_selected_content_tabs: current item의 anchor persistence 교체도 batch wrapper가 종결한다.
    /// navigation이 optimistic Pin intent를 교체해도 coordinator가 stale terminal을 기다리며 멈추지 않는지 검증한다.
    /// - 검증 내용: direct updateActivePageAnchor의 wrapper 재라우팅과 replacement terminal completion
    /// - 사전 조건: selected Pin current item이 pinned/pending 상태이고 같은 tab anchor가 변경됨
    /// - 기대 결과: 새 terminal이 success로 집계되고 coordinator와 pending persistence가 모두 정리됨
    func testPinSelectedCurrentAnchorPersistenceReplacementCompletesBatch() async throws {
        let fixture = try selectedPinPersistenceReplacementFixture()
        let tabID = fixture.tabID
        let changedAnchor = fixture.changedAnchor
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: fixture.state) {
            Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                if case let .selectedPinMutationBatchCompleted(result) = action {
                    completedResults.withValue { $0.append(result) }
                    return .none
                }
                return CTM003FileManagerPersistenceHarness().reduce(into: &state, action: action)
            }
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: 동적 terminal context보다 replacement intent의 최종 batch 정산을 검증함
        store.exhaustivity = .off

        let optimisticContentTabs = store.state.contentTabs
        let optimisticCoordinator = store.state.pendingSelectedContentTabPinMutation
        await store.send(.closeContentTabRequested(tabID))
        await store.send(.contentTabs(.requestClose(tabID)))
        await store.send(.contentTabs(.close(tabID)))
        await store.send(.contentTabs(.commitClose(tabID)))
        XCTAssertEqual(store.state.contentTabs, optimisticContentTabs)
        XCTAssertEqual(store.state.pendingSelectedContentTabPinMutation, optimisticCoordinator)
        XCTAssertNil(store.state.pendingContentTabClose)

        await store.send(.contentTabs(.updateActivePageAnchor(tabID, changedAnchor)))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, changedAnchor)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[tabID]?.anchor, changedAnchor)
        XCTAssertTrue(store.state.contentTabs.pendingPinnedRecordIDs.isEmpty)
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        guard let result = completedResults.value.first else {
            return XCTFail("replacement persistence completion missing")
        }
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertEqual(result.remainingCount, 0)
    }

    /// CTM-003-pin_selected_content_tabs: anchor replacement 실패 계열은 current item의 Pin 변경만 rollback한다.
    /// persistence 대기 중 발생한 active/selection/content 변경을 failed/superseded/cancelled가 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: item-scoped Pin/order/record rollback, live content/inspector/active/selection 보존, deferred replay
    /// - 사전 조건: optimistic selected Pin current item, empty authoritative snapshot, terminal 전 peer 전환과 target deselect
    /// - 기대 결과: target만 unpinned 상태로 복구되고 최신 window runtime과 anchor는 보존된다.
    func testPinSelectedAnchorReplacementRollbackReplaysEmptyAuthoritativeSnapshot() async throws {
        for terminal in SelectedPinReplacementTerminal.allCases {
            let fixture = try selectedPinPersistenceReplacementFixture()
            let rollback = try XCTUnwrap(
                fixture.state.pendingSelectedContentTabPinMutation?.currentItemRollbackSnapshot,
            )
            let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
            let store = TestStore(initialState: fixture.state) {
                Reduce<FileManagerFeature.State, FileManagerFeature.Action> { state, action in
                    if case let .selectedPinMutationBatchCompleted(result) = action {
                        completedResults.withValue { $0.append(result) }
                    }
                    return CTM003FileManagerPersistenceHarness().reduce(into: &state, action: action)
                }
            } withDependencies: {
                $0.date = .constant(Self.pinnedAt)
                $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, _ in
                    switch terminal {
                    case .failed:
                        throw SelectedPinMatrixError.persistenceFailed
                    case .superseded:
                        return .superseded
                    case .cancelled:
                        throw CancellationError()
                    }
                }
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            }
            // store.exhaustivity = .off: replacement terminal context보다 최종 rollback/replay snapshot을 검증함
            store.exhaustivity = .off

            let empty = ContentTabState.restoringPinnedRecords(from: ContentTabPinnedRecordStore()).state
            await store.send(.applyAuthoritativePinnedContentTabs(empty))
            await store.send(.contentTabs(.setCurrent(fixture.peerID)))
            await store.skipReceivedActions()
            await store.send(.contentTabs(.toggleSelection(fixture.tabID)))
            let liveContent = store.state.content
            let liveTabContentStates = store.state.tabContentStates
            let liveInspector = store.state.inspector
            let liveTabInspectorStates = store.state.tabInspectorStates
            await store.send(.contentTabs(.updateActivePageAnchor(fixture.tabID, fixture.changedAnchor)))
            await store.skipReceivedActions()
            await store.finish()

            let label = "replacement-\(terminal)"
            guard let result = completedResults.value.first else {
                return XCTFail("missing replacement completion: \(label)")
            }
            assertSelectedPinReplacementRollback(
                state: store.state,
                expectation: SelectedPinReplacementRollbackExpectation(
                    rollback: rollback,
                    fixture: fixture,
                    liveContent: liveContent,
                    liveTabContentStates: liveTabContentStates,
                    liveInspector: liveInspector,
                    liveTabInspectorStates: liveTabInspectorStates,
                ),
                terminal: terminal,
                result: result,
                label: label,
            )
        }
    }

    private struct SelectedPinReplacementRollbackExpectation {
        let rollback: ContentTabPinnedRecordRollbackSnapshot
        let fixture: SelectedPinPersistenceReplacementFixture
        let liveContent: FileManagerContentFeature.State
        let liveTabContentStates: [ContentTabID: FileManagerContentFeature.State]
        let liveInspector: FileManagerInspectorFeature.State
        let liveTabInspectorStates: [ContentTabID: FileManagerInspectorFeature.State]
    }

    private func assertSelectedPinReplacementRollback(
        state: FileManagerFeature.State,
        expectation: SelectedPinReplacementRollbackExpectation,
        terminal: SelectedPinReplacementTerminal,
        result: SelectedContentTabPinMutationResult,
        label: String,
    ) {
        let rollback = expectation.rollback
        let fixture = expectation.fixture
        XCTAssertNil(state.pendingSelectedContentTabPinMutation, label)
        XCTAssertNil(state.deferredPinnedContentTabs, label)
        XCTAssertNil(state.deferredPinnedContentTabsMode, label)
        XCTAssertEqual(state.contentTabs.tabs[id: fixture.tabID]?.isPinned, rollback.previousIsPinned, label)
        XCTAssertEqual(state.contentTabs.pinnedRecords[fixture.tabID], rollback.previousPinnedRecord, label)
        XCTAssertEqual(state.contentTabs.tabs.index(id: fixture.tabID), rollback.previousTabIndex, label)
        XCTAssertEqual(state.contentTabs.pendingPinnedRecordIDs, [], label)
        XCTAssertEqual(state.contentTabs.activeTabID, fixture.peerID, label)
        XCTAssertEqual(state.contentTabs.selectedTabIDs, [fixture.peerID], label)
        XCTAssertEqual(state.contentTabs.selectionAnchorID, fixture.tabID, label)
        XCTAssertEqual(state.contentTabs.tabs[id: fixture.tabID]?.anchor, fixture.changedAnchor, label)
        XCTAssertEqual(
            state.contentTabs.pinnedRecordPersistenceError,
            terminal == .failed ? "pinned_record_save_failed" : nil,
            label,
        )
        XCTAssertEqual(state.content, expectation.liveContent, label)
        XCTAssertEqual(state.tabContentStates, expectation.liveTabContentStates, label)
        XCTAssertEqual(state.inspector, expectation.liveInspector, label)
        XCTAssertEqual(state.tabInspectorStates, expectation.liveTabInspectorStates, label)
        XCTAssertEqual(result.failureCount, terminal == .failed ? 1 : 0, label)
        XCTAssertEqual(result.remainingCount, terminal == .failed ? 0 : 1, label)
    }

    /// CTM-003-pin_selected_content_tabs: onDisappear가 operation을 정리하고 late terminal을 무시한다.
    /// window teardown 이후 wrapper terminal이 coordinator나 child state를 부활시키지 않는지 검증한다.
    /// - 검증 내용: coordinator clear/cancel과 late wrapped success zero mutation
    /// - 사전 조건: optimistic Pin persistence가 pending인 current item
    /// - 기대 결과: isClosing=true, coordinator=nil이며 late terminal 전후 state가 동일함
    func testPinSelectedOnDisappearClearsCoordinatorAndIgnoresLateTerminal() async {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 6))
        let tabID = fixture.orderedIDs[0]
        var initialState = fixture.state
        initialState.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: fixture.orderedIDs,
            currentTabID: tabID,
        )
        let intentID = initialState.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        initialState.contentTabs.pendingPinnedRecordIDs.insert(tabID)
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: intentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID, value: UUID()),
        )
        let store = TestStore(initialState: initialState) { CTM003FileManagerPersistenceHarness() }
        // store.exhaustivity = .off: cancellation effect 자체보다 teardown 후 late terminal의 zero mutation을 검증함
        store.exhaustivity = .off

        await store.send(.onDisappear)
        await store.finish()
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
        let disappearedState = store.state
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: tabID,
            action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
        ))
        XCTAssertEqual(store.state, disappearedState)
    }

    /// CTM-003-pin_selected_content_tabs: preflight remaining 분기를 first/middle/last에서 모두 집계한다.
    /// missing, same-state, ineligible target이 frozen total을 유지하면서 다음 item으로 계속 진행하는지 검증한다.
    /// - 검증 내용: 9개 위치/사유 조합의 exact count invariant, process continuation, coordinator cleanup
    /// - 사전 조건: selected Directory 3개와 위치별 preflight remaining 조건
    /// - 기대 결과: total=3, success=2, failure=0, remaining=1이며 process 4회 후 coordinator=nil
    func testPinSelectedPreflightMatrixCoversFirstMiddleLastMissingSameStateAndIneligible() async throws {
        for targetOffset in 0 ..< 3 {
            for reason in SelectedPinPreflightReason.allCases {
                try await assertSelectedPinPreflightCase(targetOffset: targetOffset, reason: reason)
            }
        }
    }

    /// CTM-003-pin_selected_content_tabs: correlated failed/notApplied terminal을 first/middle/last에서 모두 처리한다.
    /// 실제 single Pin persistence terminal wrapper가 target만 rollback하고 이후 frozen item을 계속 처리하는지 검증한다.
    /// - 검증 내용: 6개 terminal matrix의 exact rollback/order/record/count/continuation
    /// - 사전 조건: selected unpinned Directory 3개와 위치별 failure 또는 superseded persistence
    /// - 기대 결과: affected tab은 원래 unpinned snapshot, 나머지는 pinned이며 coordinator=nil
    func testPinSelectedTerminalMatrixCoversFirstMiddleLastFailedAndNotAppliedRollback() async {
        for targetOffset in 0 ..< 3 {
            for terminal in SelectedPinMatrixTerminal.allCases {
                await assertSelectedPinTerminalCase(targetOffset: targetOffset, terminal: terminal)
            }
        }
    }

    /// CTM-003-pin_selected_content_tabs: active coordinator의 duplicate request와 duplicate terminal은 no-op이다.
    /// 첫 correlated success를 한 번 집계한 뒤 같은 wrapper terminal을 다시 보내도 state/count가 변하지 않는지 검증한다.
    /// - 검증 내용: duplicate request zero mutation, duplicate terminal zero mutation, single final success
    /// - 사전 조건: optimistic Pin이 current인 one-item coordinator
    /// - 기대 결과: cursor는 한 번만 증가하고 total=success=1로 coordinator가 정리됨
    func testPinSelectedDuplicateRequestAndDuplicateTerminalAreNoOps() async {
        let fixture = selectedPinBatchMatrixFixture()
        let operationID = matrixOperationID(group: 4, offset: 0)
        let tabID = fixture.orderedIDs[0]
        var initialState = fixture.state
        let context = prepareCurrentOptimisticSelectedPin(
            state: &initialState,
            operationID: operationID,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
        )
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: initialState) {
            selectedPinMatrixReducer(completedResults: completedResults)
        }
        // store.exhaustivity = .off: 첫 terminal completion chain 뒤 duplicate wrapper의 zero mutation을 검증함
        store.exhaustivity = .off

        await store.send(.requestSelectedContentTabPinMutation(target: .pinned))
        XCTAssertEqual(store.state, initialState)
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: tabID,
            action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
        ))
        await store.skipReceivedActions()
        await store.finish()

        let completedState = store.state
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: tabID,
            action: .pinnedRecordSaveSucceeded(tabID: tabID, context: context),
        ))
        XCTAssertEqual(store.state, completedState)

        guard let result = completedResults.withValue({ $0.first }) else {
            return XCTFail("missing duplicate completion")
        }
        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertEqual(result.remainingCount, 0)
        XCTAssertEqual(result.totalCount, result.successCount + result.failureCount + result.remainingCount)
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
    }

    /// CTM-003-pin_selected_content_tabs: mid-batch live selection/anchor 변경을 completion이 덮어쓰지 않는다.
    /// frozen orderedTargetIDs는 유지되어 deselected target도 처리하지만 live membership과 anchor는 그대로 보존되는지 검증한다.
    /// - 검증 내용: live toggle 이후 frozen IDs 불변, exact final selection/anchor/count
    /// - 사전 조건: 첫 item optimistic Pin 중인 selected Directory 3개
    /// - 기대 결과: frozen 3개 모두 success이고 live selection은 2개, anchor는 deselected third로 유지됨
    func testPinSelectedPreservesLiveSelectionAndAnchorWhileFrozenTargetsContinue() async {
        let fixture = selectedPinBatchMatrixFixture()
        let operationID = matrixOperationID(group: 5, offset: 0)
        let firstID = fixture.orderedIDs[0]
        let changedAnchorID = fixture.orderedIDs[2]
        var initialState = fixture.state
        let context = prepareCurrentOptimisticSelectedPin(
            state: &initialState,
            operationID: operationID,
            orderedTargetIDs: fixture.orderedIDs,
            currentTabID: firstID,
        )
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let store = TestStore(initialState: initialState) {
            selectedPinMatrixReducer(completedResults: completedResults)
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: 첫 terminal 이후 실제 persistence chain을 소비하고 live/frozen 최종 상태를 검증함
        store.exhaustivity = .off

        await store.send(.contentTabs(.toggleSelection(changedAnchorID))) {
            $0.contentTabs.selectedTabIDs.remove(changedAnchorID)
            $0.contentTabs.selectionAnchorID = changedAnchorID
        }
        XCTAssertEqual(
            store.state.pendingSelectedContentTabPinMutation?.orderedTargetIDs,
            fixture.orderedIDs,
        )
        await store.send(.performSelectedContentTabPinMutation(
            operationID: operationID,
            tabID: firstID,
            action: .pinnedRecordSaveSucceeded(tabID: firstID, context: context),
        ))
        await store.skipReceivedActions()
        await store.finish()

        guard let result = completedResults.withValue({ $0.first }) else {
            return XCTFail("missing preservation completion")
        }
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertEqual(result.remainingCount, 0)
        XCTAssertEqual(result.totalCount, result.successCount + result.failureCount + result.remainingCount)
        XCTAssertEqual(store.state.contentTabs.selectedTabIDs, Set(fixture.orderedIDs.prefix(2)))
        XCTAssertEqual(store.state.contentTabs.selectionAnchorID, changedAnchorID)
        XCTAssertTrue(fixture.orderedIDs.allSatisfy { store.state.contentTabs.tabs[id: $0]?.isPinned == true })
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation)
    }

    /// CTM-003-pin_selected_content_tabs: aggregate feedback의 silent/failure/remaining 세 분기를 정확히 소유한다.
    /// item completion은 alert를 만들지 않고 batch completion만 branch별 최대 한 번 호출하는지 검증한다.
    /// - 검증 내용: all-success 0회, failure summary 1회, remaining-only summary 1회, per-item 0회
    /// - 사전 조건: 세 가지 completed result와 coordinator 없는 item completion
    /// - 기대 결과: branch별 exact call count와 title이 일치함
    func testPinSelectedFeedbackCoversSilentFailureAndRemainingSummariesWithoutPerItemAlerts() async {
        let cases = selectedPinFeedbackCases()

        for testCase in cases {
            let recorder = CollectionPinAlertRecorder()
            let store = TestStore(initialState: FileManagerFeature.State()) { CTM003FileManagerPersistenceHarness()
            } withDependencies: {
                $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                    recorder.record(title: title, message: message)
                }
            }
            await store.send(.selectedPinMutationItemCompleted(
                operationID: testCase.result.operationID,
                tabID: ContentTabID(rawValue: "feedback-item"),
                outcome: .failure,
            ))
            XCTAssertEqual(recorder.alertCount(), 0)
            await store.send(.selectedPinMutationBatchCompleted(testCase.result))
            await store.finish()
            XCTAssertEqual(recorder.alertCount(), testCase.count)
            XCTAssertEqual(recorder.latestAlert()?.title, testCase.title)
        }
    }

    /// CTM-003-pin_selected_content_tabs: failure feedback가 remaining 정보보다 우선하고 한 번만 표시된다.
    /// aggregate completion만 사용자 feedback을 소유하며 item별 alert를 만들지 않는지 검증한다.
    /// - 검증 내용: failure/remaining 혼합 result의 정확한 alert 호출 수와 failure title
    /// - 사전 조건: success 0, failure 1, remaining 1인 completed result
    /// - 기대 결과: failure summary alert 정확히 1회, informational alert 0회
    func testPinSelectedFeedbackUsesFailurePrecedenceWithoutPerItemAlerts() async {
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 7))
        let recorder = CollectionPinAlertRecorder()
        let store = TestStore(initialState: FileManagerFeature.State()) { CTM003FileManagerPersistenceHarness()
        } withDependencies: {
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { title, message in
                recorder.record(title: title, message: message)
            }
        }

        await store.send(.selectedPinMutationBatchCompleted(.init(
            operationID: operationID,
            target: .pinned,
            totalCount: 2,
            successCount: 0,
            failureCount: 1,
            remainingCount: 1,
        )))
        await store.finish()

        XCTAssertEqual(recorder.alertCount(), 1)
        XCTAssertEqual(recorder.latestAlert()?.title, "Some Tabs Couldn’t Be Pinned")
    }

    private func directCloseActions(tabID: ContentTabID) -> [ContentTabAction] {
        [.requestClose(tabID), .close(tabID), .commitClose(tabID)]
    }

    private func assertSelectedPinCloseBoundary(
        _ state: FileManagerFeature.State,
        equals expected: FileManagerFeature.State,
        invalidationCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.contentTabs.tabs.map(\.id), expected.contentTabs.tabs.map(\.id), file: file, line: line)
        XCTAssertEqual(state.contentTabs.tabs, expected.contentTabs.tabs, file: file, line: line)
        XCTAssertEqual(state.contentTabs, expected.contentTabs, file: file, line: line)
        XCTAssertEqual(state.pendingContentTabClose, expected.pendingContentTabClose, file: file, line: line)
        XCTAssertEqual(state.pendingContentTabTeardown, expected.pendingContentTabTeardown, file: file, line: line)
        XCTAssertEqual(state.undoRedoPhase, expected.undoRedoPhase, file: file, line: line)
        XCTAssertEqual(state.undoManagerAvailability, expected.undoManagerAvailability, file: file, line: line)
        XCTAssertEqual(
            state.pendingSelectedContentTabPinMutation?.currentTabID,
            expected.pendingSelectedContentTabPinMutation?.currentTabID,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.pendingSelectedContentTabPinMutation?.cursor,
            expected.pendingSelectedContentTabPinMutation?.cursor,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.pendingSelectedContentTabPinMutation?.successCount,
            expected.pendingSelectedContentTabPinMutation?.successCount,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.pendingSelectedContentTabPinMutation?.failureCount,
            expected.pendingSelectedContentTabPinMutation?.failureCount,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.pendingSelectedContentTabPinMutation?.remainingCount,
            expected.pendingSelectedContentTabPinMutation?.remainingCount,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.contentTabs.selectedTabIDs,
            expected.contentTabs.selectedTabIDs,
            file: file,
            line: line,
        )
        XCTAssertEqual(
            state.contentTabs.selectionAnchorID,
            expected.contentTabs.selectionAnchorID,
            file: file,
            line: line,
        )
        XCTAssertEqual(invalidationCount, 0, file: file, line: line)
    }

    private func assertSelectedPinCompletion(
        _ results: LockIsolated<[SelectedContentTabPinMutationResult]>,
        total: Int,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard let result = results.withValue({ $0.first }) else {
            return XCTFail("missing selected Pin/Unpin completion", file: file, line: line)
        }
        XCTAssertEqual(result.totalCount, total, file: file, line: line)
        XCTAssertEqual(result.successCount, total, file: file, line: line)
        XCTAssertEqual(result.failureCount, 0, file: file, line: line)
        XCTAssertEqual(result.remainingCount, 0, file: file, line: line)
    }

    private struct SelectedPinFeedbackCase {
        let result: SelectedContentTabPinMutationResult
        let count: Int
        let title: String?
    }

    private func selectedPinFeedbackCases() -> [SelectedPinFeedbackCase] {
        [
            .init(
                result: .init(
                    operationID: matrixOperationID(group: 6, offset: 0),
                    target: .pinned,
                    totalCount: 3,
                    successCount: 3,
                    failureCount: 0,
                    remainingCount: 0,
                ),
                count: 0,
                title: nil,
            ),
            .init(
                result: .init(
                    operationID: matrixOperationID(group: 6, offset: 1),
                    target: .pinned,
                    totalCount: 3,
                    successCount: 1,
                    failureCount: 1,
                    remainingCount: 1,
                ),
                count: 1,
                title: "Some Tabs Couldn’t Be Pinned",
            ),
            .init(
                result: .init(
                    operationID: matrixOperationID(group: 6, offset: 2),
                    target: .unpinned,
                    totalCount: 3,
                    successCount: 2,
                    failureCount: 0,
                    remainingCount: 1,
                ),
                count: 1,
                title: "Some Tabs Remained Pinned",
            ),
        ]
    }

    private func assertSelectedPinPreflightCase(
        targetOffset: Int,
        reason: SelectedPinPreflightReason,
    ) async throws {
        let fixture = selectedPinBatchMatrixFixture()
        let operationID = matrixOperationID(group: 1, offset: targetOffset * 3 + reason.rawValue)
        let initialState = try selectedPinPreflightState(
            fixture: fixture,
            operationID: operationID,
            targetOffset: targetOffset,
            reason: reason,
        )
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let processCount = LockIsolated(0)
        let store = TestStore(initialState: initialState) {
            selectedPinMatrixReducer(completedResults: completedResults, processCount: processCount)
        } withDependencies: {
            $0.date = .constant(Self.pinnedAt)
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: matrix의 동적 persistence context 대신 final count와 continuation을 검증함
        store.exhaustivity = .off

        await store.send(.processNextSelectedContentTabPinMutation(operationID: operationID))
        await store.skipReceivedActions()
        await store.finish()

        let label = "\(reason)-\(targetOffset)"
        assertSelectedPinResult(completedResults, success: 2, failure: 0, remaining: 1, label: label)
        XCTAssertEqual(processCount.value, 4, label)
        XCTAssertNil(store.state.pendingSelectedContentTabPinMutation, label)
    }

    private func selectedPinPreflightState(
        fixture: SelectedPinBatchMatrixFixture,
        operationID: UUID,
        targetOffset: Int,
        reason: SelectedPinPreflightReason,
    ) throws -> FileManagerFeature.State {
        let targetID = fixture.orderedIDs[targetOffset]
        var state = fixture.state
        switch reason {
        case .missing:
            state.contentTabs.tabs.remove(id: targetID)
        case .sameState:
            state.contentTabs.tabs[id: targetID]?.isPinned = true
            state.contentTabs.pinnedRecords[targetID] = try Self.pinnedRecord(
                id: targetID,
                anchor: XCTUnwrap(state.contentTabs.tabs[id: targetID]?.anchor),
                title: XCTUnwrap(state.contentTabs.tabs[id: targetID]?.title),
                iconName: "folder",
            )
        case .ineligible:
            state.contentTabs.tabs[id: targetID]?.page = .home
            state.contentTabs.tabs[id: targetID]?.anchor = .homeDefault
        }
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: fixture.orderedIDs,
        )
        state.syncContentTabSidebarItems()
        return state
    }

    private func assertSelectedPinTerminalCase(
        targetOffset: Int,
        terminal: SelectedPinMatrixTerminal,
    ) async {
        let fixture = selectedPinBatchMatrixFixture()
        let operationID = matrixOperationID(group: 2 + terminal.rawValue, offset: targetOffset)
        let completedResults = LockIsolated<[SelectedContentTabPinMutationResult]>([])
        let processCount = LockIsolated(0)
        let persistenceCallCount = LockIsolated(0)
        let store = TestStore(initialState: fixture.state) {
            selectedPinMatrixReducer(completedResults: completedResults, processCount: processCount)
        } withDependencies: {
            $0.uuid = .constant(operationID)
            $0.date = .constant(Self.pinnedAt)
            $0.collectionAlertClient.showCollectionOpenErrorAlert = { _, _ in }
            $0.contentTabPinnedRecordClient.guardedUpdateStore = { _, _, transform in
                let callIndex = persistenceCallCount.withValue { value in
                    defer { value += 1 }
                    return value
                }
                if callIndex == targetOffset {
                    switch terminal {
                    case .failed:
                        throw SelectedPinMatrixError.persistenceFailed
                    case .superseded:
                        return .superseded
                    case .cancelled:
                        throw CancellationError()
                    }
                }
                _ = try transform(ContentTabPinnedRecordStore())
                return .applied
            }
        }
        // store.exhaustivity = .off: 실제 wrapper terminal의 동적 context를 소비하고 final rollback matrix를 검증함
        store.exhaustivity = .off

        await store.send(.requestSelectedContentTabPinMutation(target: .pinned))
        await store.skipReceivedActions()
        await store.finish()

        let label = "\(terminal)-\(targetOffset)"
        assertSelectedPinTerminalResult(completedResults, terminal: terminal, label: label)
        assertSelectedPinTerminalState(store.state, fixture: fixture, targetOffset: targetOffset, label: label)
        XCTAssertEqual(processCount.value, 4, label)
        XCTAssertEqual(persistenceCallCount.value, 3, label)
    }

    private func assertSelectedPinResult(
        _ results: LockIsolated<[SelectedContentTabPinMutationResult]>,
        success: Int,
        failure: Int,
        remaining: Int,
        label: String,
    ) {
        guard let result = results.withValue({ $0.first }) else {
            return XCTFail("missing completion: \(label)")
        }
        XCTAssertEqual(result.totalCount, 3, label)
        XCTAssertEqual(result.successCount, success, label)
        XCTAssertEqual(result.failureCount, failure, label)
        XCTAssertEqual(result.remainingCount, remaining, label)
        XCTAssertEqual(result.totalCount, result.successCount + result.failureCount + result.remainingCount, label)
    }

    private func assertSelectedPinTerminalResult(
        _ results: LockIsolated<[SelectedContentTabPinMutationResult]>,
        terminal: SelectedPinMatrixTerminal,
        label: String,
    ) {
        assertSelectedPinResult(
            results,
            success: 2,
            failure: terminal == .failed ? 1 : 0,
            remaining: terminal == .failed ? 0 : 1,
            label: label,
        )
    }

    private func assertSelectedPinTerminalState(
        _ state: FileManagerFeature.State,
        fixture: SelectedPinBatchMatrixFixture,
        targetOffset: Int,
        label: String,
    ) {
        let targetID = fixture.orderedIDs[targetOffset]
        XCTAssertNil(state.pendingSelectedContentTabPinMutation, label)
        XCTAssertEqual(state.content, fixture.state.content, label)
        XCTAssertEqual(state.tabContentStates, fixture.state.tabContentStates, label)
        XCTAssertEqual(state.inspector, fixture.state.inspector, label)
        XCTAssertEqual(state.tabInspectorStates, fixture.state.tabInspectorStates, label)
        XCTAssertEqual(state.contentTabs.activeTabID, fixture.state.contentTabs.activeTabID, label)
        XCTAssertEqual(state.contentTabs.selectedTabIDs, fixture.state.contentTabs.selectedTabIDs, label)
        XCTAssertEqual(state.contentTabs.selectionAnchorID, fixture.state.contentTabs.selectionAnchorID, label)
        XCTAssertEqual(
            state.contentTabs.tabs.map(\.id),
            fixture.orderedIDs.filter { $0 != targetID } + [targetID],
            label,
        )
        XCTAssertEqual(state.contentTabs.tabs[id: targetID]?.isPinned, false, label)
        XCTAssertNil(state.contentTabs.pinnedRecords[targetID], label)
        for successfulID in fixture.orderedIDs where successfulID != targetID {
            XCTAssertEqual(state.contentTabs.tabs[id: successfulID]?.isPinned, true, label)
            XCTAssertNotNil(state.contentTabs.pinnedRecords[successfulID], label)
        }
    }

    private enum SelectedPinPreflightReason: Int, CaseIterable {
        case missing
        case sameState
        case ineligible
    }

    private enum SelectedPinMatrixTerminal: Int, CaseIterable {
        case failed
        case superseded
        case cancelled
    }

    private enum SelectedPinReplacementTerminal: CaseIterable {
        case failed
        case superseded
        case cancelled
    }

    private enum SelectedPinMatrixError: Error {
        case persistenceFailed
    }

    private struct SelectedPinBatchMatrixFixture {
        let state: FileManagerFeature.State
        let orderedIDs: [ContentTabID]
    }

    private func selectedPinBatchMatrixFixture() -> SelectedPinBatchMatrixFixture {
        let orderedIDs = ["first", "middle", "last"].map {
            ContentTabID(rawValue: "selected-pin-matrix-\($0)")
        }
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: orderedIDs.enumerated().map { offset, id in
                ContentTabItem(
                    id: id,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/SelectedMatrix/\(offset)"),
                    isPinned: false,
                    title: "Matrix \(offset)",
                    iconName: "folder",
                )
            }),
            activeTabID: orderedIDs[0],
            previousActiveTabID: orderedIDs[2],
        )
        state.contentTabs.selectedTabIDs = Set(orderedIDs)
        state.contentTabs.selectionAnchorID = orderedIDs[1]
        state.syncContentTabSidebarItems()
        return SelectedPinBatchMatrixFixture(state: state, orderedIDs: orderedIDs)
    }

    private func selectedPinMatrixReducer(
        completedResults: LockIsolated<[SelectedContentTabPinMutationResult]>,
        processCount: LockIsolated<Int>? = nil,
    ) -> Reduce<FileManagerFeature.State, FileManagerFeature.Action> {
        Reduce { state, action in
            if case .processNextSelectedContentTabPinMutation = action {
                processCount?.withValue { $0 += 1 }
            }
            if case let .selectedPinMutationBatchCompleted(result) = action {
                completedResults.withValue { $0.append(result) }
            }
            return CTM003FileManagerPersistenceHarness().reduce(into: &state, action: action)
        }
    }

    private func prepareCurrentOptimisticSelectedPin(
        state: inout FileManagerFeature.State,
        operationID: UUID,
        orderedTargetIDs: [ContentTabID],
        currentTabID: ContentTabID,
    ) -> ContentTabPinnedRecordTerminalContext {
        state.contentTabs.tabs[id: currentTabID]?.isPinned = true
        guard let tab = state.contentTabs.tabs[id: currentTabID] else {
            preconditionFailure("Current matrix tab must exist")
        }
        state.contentTabs.pinnedRecords[currentTabID] = Self.pinnedRecord(
            id: currentTabID,
            anchor: tab.anchor,
            title: tab.title,
            iconName: tab.iconName,
        )
        state.contentTabs.pendingPinnedRecordIDs.insert(currentTabID)
        let intentID = state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: currentTabID)
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: orderedTargetIDs,
            currentTabID: currentTabID,
        )
        state.syncContentTabSidebarItems()
        return ContentTabPinnedRecordTerminalContext(
            intentID: intentID,
            generation: ContentTabPinnedRecordMutationGeneration(
                tabID: currentTabID,
                value: matrixOperationID(group: 7, offset: orderedTargetIDs.count),
            ),
        )
    }

    private struct CurrentOptimisticSelectedUnpinFixture {
        let state: FileManagerFeature.State
        let operationID: UUID
        let tabID: ContentTabID
        let context: ContentTabPinnedRecordTerminalContext
    }

    private func currentOptimisticSelectedUnpinFixture() -> CurrentOptimisticSelectedUnpinFixture {
        let fixture = allPinnedSelectedPinMutationFixture()
        let operationID = matrixOperationID(group: 8, offset: 2)
        let tabID = fixture.orderedIDs[0]
        var state = fixture.state
        guard var currentTab = state.contentTabs.tabs[id: tabID] else {
            preconditionFailure("Current selected Unpin tab must exist")
        }
        state.contentTabs.tabs.remove(id: tabID)
        currentTab.isPinned = false
        state.contentTabs.tabs.append(currentTab)
        state.contentTabs.pinnedRecords.removeValue(forKey: tabID)
        state.contentTabs.pendingPinnedRecordIDs.remove(tabID)
        let intentID = state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .unpinned,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
        )
        state.windowID = matrixOperationID(group: 8, offset: 3)
        state.syncContentTabSidebarItems()
        return CurrentOptimisticSelectedUnpinFixture(
            state: state,
            operationID: operationID,
            tabID: tabID,
            context: ContentTabPinnedRecordTerminalContext(
                intentID: intentID,
                generation: ContentTabPinnedRecordMutationGeneration(
                    tabID: tabID,
                    value: matrixOperationID(group: 8, offset: 4),
                ),
            ),
        )
    }

    private func matrixOperationID(group: Int, offset: Int) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            UInt8(group), UInt8(offset), UInt8(group * 16 + offset),
        ))
    }

    private struct GlobalStaleSelectedPinMutationFixture {
        let state: FileManagerFeature.State
        let operationID: UUID
        let tabID: ContentTabID
        let context: ContentTabPinnedRecordTerminalContext
    }

    private func globalStaleSelectedPinMutationFixture() throws -> GlobalStaleSelectedPinMutationFixture {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 9))
        let tabID = fixture.orderedIDs[0]
        var state = fixture.state
        state.contentTabs.tabs[id: tabID]?.isPinned = true
        state.contentTabs.pinnedRecords[tabID] = Self.pinnedRecord(
            id: tabID,
            anchor: .directory(path: "/Users/test/Selected/First"),
            title: "First",
            iconName: "folder",
        )
        state.contentTabs.pendingPinnedRecordIDs.insert(tabID)
        state.syncContentTabSidebarItems()
        let intentID = state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
        )
        let context = ContentTabPinnedRecordTerminalContext(
            intentID: intentID,
            generation: ContentTabPinnedRecordMutationGeneration(tabID: tabID, value: UUID()),
        )
        return GlobalStaleSelectedPinMutationFixture(
            state: state,
            operationID: operationID,
            tabID: tabID,
            context: context,
        )
    }

    private struct SelectedPinPersistenceReplacementFixture {
        let state: FileManagerFeature.State
        let tabID: ContentTabID
        let peerID: ContentTabID
        let changedAnchor: ContentTabPageAnchor
    }

    private func selectedPinPersistenceReplacementFixture() throws -> SelectedPinPersistenceReplacementFixture {
        let fixture = allUnpinnedSelectedPinMutationFixture()
        let operationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 7))
        let tabID = fixture.orderedIDs[0]
        var state = fixture.state
        let rollbackSnapshot = ContentTabPinnedRecordRollbackSnapshot(
            previousIsPinned: state.contentTabs.tabs[id: tabID]?.isPinned ?? false,
            previousPinnedRecord: state.contentTabs.pinnedRecords[tabID],
            previousTabIndex: state.contentTabs.tabs.index(id: tabID),
        )
        state.contentTabs.tabs[id: tabID]?.isPinned = true
        state.contentTabs.pinnedRecords[tabID] = try Self.pinnedRecord(
            id: tabID,
            anchor: XCTUnwrap(state.contentTabs.tabs[id: tabID]?.anchor),
            title: XCTUnwrap(state.contentTabs.tabs[id: tabID]?.title),
            iconName: "folder",
        )
        state.contentTabs.pendingPinnedRecordIDs.insert(tabID)
        _ = state.contentTabs.markLatestPinnedRecordPersistenceIntent(for: tabID)
        state.pendingSelectedContentTabPinMutation = PendingSelectedContentTabPinMutation(
            operationID: operationID,
            target: .pinned,
            orderedTargetIDs: [tabID],
            currentTabID: tabID,
            currentItemRollbackSnapshot: rollbackSnapshot,
        )
        return SelectedPinPersistenceReplacementFixture(
            state: state,
            tabID: tabID,
            peerID: fixture.orderedIDs[1],
            changedAnchor: .directory(path: "/Users/test/replaced-anchor"),
        )
    }

    private struct SelectedPinMutationFixture {
        let state: FileManagerFeature.State
        let orderedIDs: [ContentTabID]
        let pinnedID: ContentTabID
        let unpinnedID: ContentTabID
        let unsupportedID: ContentTabID
    }

    private func selectedPinMutationFixture() -> SelectedPinMutationFixture {
        let pinnedID = ContentTabID(rawValue: "selected-pin-pinned")
        let unpinnedID = ContentTabID(rawValue: "selected-pin-unpinned")
        let unsupportedID = ContentTabID(rawValue: "selected-pin-home")
        let record = Self.pinnedRecord(
            id: pinnedID,
            anchor: .directory(path: "/Users/test/Selected/Pinned"),
            title: "Pinned",
            iconName: "folder",
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: .init(uniqueElements: selectedPinMutationTabs(
                pinnedID: pinnedID,
                unpinnedID: unpinnedID,
                unsupportedID: unsupportedID,
            )),
            activeTabID: unpinnedID,
            previousActiveTabID: pinnedID,
            pinnedRecords: [pinnedID: record],
        )
        state.contentTabs.selectedTabIDs = [pinnedID, unpinnedID, unsupportedID]
        state.contentTabs.selectionAnchorID = unsupportedID
        state.tabContentStates[pinnedID] = .initialContent(
            for: .directory(path: "/Users/test/Selected/Pinned"),
            inheritingWindowContextFrom: state.content,
        )
        state.syncContentTabSidebarItems()
        return SelectedPinMutationFixture(
            state: state,
            orderedIDs: [pinnedID, unpinnedID, unsupportedID],
            pinnedID: pinnedID,
            unpinnedID: unpinnedID,
            unsupportedID: unsupportedID,
        )
    }

    private func selectedPinMutationTabs(
        pinnedID: ContentTabID,
        unpinnedID: ContentTabID,
        unsupportedID: ContentTabID,
    ) -> [ContentTabItem] {
        [
            Self.pinnedItem(
                id: pinnedID,
                anchor: .directory(path: "/Users/test/Selected/Pinned"),
                title: "Pinned",
            ),
            ContentTabItem(
                id: unpinnedID,
                page: .directory,
                anchor: .directory(path: "/Users/test/Selected/Unpinned"),
                isPinned: false,
                title: "Unpinned",
                iconName: "folder",
            ),
            ContentTabItem(
                id: unsupportedID,
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
        ]
    }

    private func allPinnedSelectedPinMutationFixture() -> SelectedPinMutationFixture {
        let firstID = ContentTabID(rawValue: "selected-unpin-first")
        let secondID = ContentTabID(rawValue: "selected-unpin-second")
        let firstAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Selected/UnpinFirst")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Selected/UnpinSecond")
        let records = [
            firstID: Self.pinnedRecord(id: firstID, anchor: firstAnchor, title: "First", iconName: "folder"),
            secondID: Self.pinnedRecord(id: secondID, anchor: secondAnchor, title: "Second", iconName: "folder"),
        ]
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                Self.pinnedItem(id: firstID, anchor: firstAnchor, title: "First"),
                Self.pinnedItem(id: secondID, anchor: secondAnchor, title: "Second"),
            ],
            activeTabID: firstID,
            previousActiveTabID: secondID,
            pinnedRecords: records,
        )
        state.contentTabs.selectedTabIDs = [firstID, secondID]
        state.contentTabs.selectionAnchorID = secondID
        state.tabContentStates[secondID] = .initialContent(
            for: secondAnchor,
            inheritingWindowContextFrom: state.content,
        )
        state.syncContentTabSidebarItems()
        return SelectedPinMutationFixture(
            state: state,
            orderedIDs: [firstID, secondID],
            pinnedID: firstID,
            unpinnedID: secondID,
            unsupportedID: secondID,
        )
    }

    private func allUnpinnedSelectedPinMutationFixture() -> SelectedPinMutationFixture {
        let firstID = ContentTabID(rawValue: "selected-pin-first")
        let secondID = ContentTabID(rawValue: "selected-pin-second")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: firstID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Selected/First"),
                    isPinned: false,
                    title: "First",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: secondID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Selected/Second"),
                    isPinned: false,
                    title: "Second",
                    iconName: "folder",
                ),
            ],
            activeTabID: firstID,
            previousActiveTabID: secondID,
        )
        state.contentTabs.selectedTabIDs = [firstID, secondID]
        state.contentTabs.selectionAnchorID = secondID
        state.tabContentStates[secondID] = .initialContent(
            for: .directory(path: "/Users/test/Selected/Second"),
            inheritingWindowContextFrom: state.content,
        )
        state.syncContentTabSidebarItems()
        return SelectedPinMutationFixture(
            state: state,
            orderedIDs: [firstID, secondID],
            pinnedID: firstID,
            unpinnedID: secondID,
            unsupportedID: secondID,
        )
    }

    private struct RollbackMatrixFixture {
        let name: String
        let state: ContentTabState
        let targetID: ContentTabID
    }

    private struct LegacyUnsupportedUnpinFixture {
        let name: String
        let state: FileManagerFeature.State
        let targetID: ContentTabID
        let siblingID: ContentTabID
        let aiSessionID: AiChatSessionID?
    }

    private struct LegacyUnsupportedTabCase {
        let name: String
        let page: ContentTabPage
        let anchor: ContentTabPageAnchor
        let aiSessionID: AiChatSessionID?
    }

    private static var pinFailureRollbackFixtures: [RollbackMatrixFixture] {
        let recentsID = ContentTabID(rawValue: "pin-matrix-recents")
        let allTagsID = ContentTabID(rawValue: "built-in-collection-all-tags")
        let recentsRecord = pinnedRecord(
            id: recentsID,
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Matrix Recents.voycollection")),
            title: "Recents",
            iconName: "clock",
        )
        let allTagsRecord = pinnedRecord(
            id: allTagsID,
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Matrix All Tags.voycollection")),
            title: "All Tags",
            iconName: "tag",
        )
        let positions = ["first", "middle", "last"]
        return positions.enumerated().map { targetOffset, name in
            let unpinnedItems = positions.map { position in
                ContentTabItem(
                    id: ContentTabID(rawValue: "pin-matrix-\(position)"),
                    page: .directory,
                    anchor: .directory(path: "/Users/test/PinMatrix/\(position)"),
                    isPinned: false,
                    title: position,
                    iconName: "folder",
                )
            }
            let targetID = unpinnedItems[targetOffset].id
            var state = ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: recentsID,
                        page: .collection,
                        anchor: recentsRecord.anchor,
                        isPinned: true,
                        title: "Recents",
                        iconName: "clock",
                    ),
                    ContentTabItem(
                        id: allTagsID,
                        page: .collection,
                        anchor: allTagsRecord.anchor,
                        isPinned: true,
                        title: "All Tags",
                        iconName: "tag",
                    ),
                ] + unpinnedItems,
                activeTabID: targetID,
                pinnedRecords: [recentsID: recentsRecord, allTagsID: allTagsRecord],
            )
            state.selectedTabIDs = [targetID, unpinnedItems[(targetOffset + 1) % unpinnedItems.count].id]
            state.selectionAnchorID = allTagsID
            return RollbackMatrixFixture(name: name, state: state, targetID: targetID)
        }
    }

    private static var unpinFailureRollbackFixtures: [RollbackMatrixFixture] {
        let positions = ["first", "middle", "last"]
        return positions.enumerated().map { targetOffset, name in
            let pinnedItems = positions.map { position in
                pinnedItem(
                    id: ContentTabID(rawValue: "unpin-matrix-\(position)"),
                    anchor: .directory(path: "/Users/test/UnpinMatrix/\(position)"),
                    title: position,
                )
            }
            let records = Dictionary(uniqueKeysWithValues: pinnedItems.map { item in
                (item.id, pinnedRecord(id: item.id, anchor: item.anchor, title: item.title, iconName: item.iconName))
            })
            let tailID = ContentTabID(rawValue: "unpin-matrix-tail")
            let targetID = pinnedItems[targetOffset].id
            var state = ContentTabState(
                tabs: pinnedItems + [
                    ContentTabItem(
                        id: tailID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/UnpinMatrix/tail"),
                        isPinned: false,
                        title: "tail",
                        iconName: "folder",
                    ),
                ],
                activeTabID: targetID,
                pinnedRecords: records,
            )
            state.selectedTabIDs = [targetID, tailID]
            state.selectionAnchorID = pinnedItems[(targetOffset + 1) % pinnedItems.count].id
            return RollbackMatrixFixture(name: name, state: state, targetID: targetID)
        }
    }

    private static func assertExactRollback(
        _ state: ContentTabState,
        fixture: RollbackMatrixFixture,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.tabs.map(\.id), fixture.state.tabs.map(\.id), fixture.name, file: file, line: line)
        XCTAssertEqual(state.tabs, fixture.state.tabs, fixture.name, file: file, line: line)
        XCTAssertEqual(state.pinnedRecords, fixture.state.pinnedRecords, fixture.name, file: file, line: line)
        XCTAssertEqual(state.selectedTabIDs, fixture.state.selectedTabIDs, fixture.name, file: file, line: line)
        XCTAssertEqual(state.selectionAnchorID, fixture.state.selectionAnchorID, fixture.name, file: file, line: line)
    }

    private var legacyUnsupportedUnpinFixtures: [LegacyUnsupportedUnpinFixture] {
        let aiSessionID = AiChatSessionID(
            rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 1)),
        )
        let temporaryURL = URL(fileURLWithPath: "/Users/test/Legacy Temporary.voycollection")
        let cases = [
            LegacyUnsupportedTabCase(name: "home", page: .home, anchor: .homeDefault, aiSessionID: nil),
            LegacyUnsupportedTabCase(
                name: "ai-chat",
                page: .aiChat,
                anchor: .aiChat(sessionID: aiSessionID.rawValue.uuidString),
                aiSessionID: aiSessionID,
            ),
            LegacyUnsupportedTabCase(
                name: "virtual",
                page: .collection,
                anchor: .virtualCollection(id: "Legacy Recents"),
                aiSessionID: nil,
            ),
            LegacyUnsupportedTabCase(
                name: "temporary",
                page: .collection,
                anchor: .collectionFile(url: temporaryURL),
                aiSessionID: nil,
            ),
        ]
        return cases.map { tabCase in
            let name = tabCase.name
            let targetID = ContentTabID(rawValue: "legacy-unpin-\(name)")
            let siblingID = ContentTabID(rawValue: "legacy-unpin-\(name)-sibling")
            let record = Self.pinnedRecord(
                id: targetID,
                page: tabCase.page,
                anchor: tabCase.anchor,
                title: name,
                iconName: tabCase.page == .aiChat ? "bubble.right" : "folder",
            )
            var state = FileManagerFeature.State()
            state.contentTabs = ContentTabState(
                tabs: [
                    ContentTabItem(
                        id: targetID,
                        page: tabCase.page,
                        anchor: tabCase.anchor,
                        isPinned: true,
                        title: name,
                        iconName: record.iconName,
                    ),
                    ContentTabItem(
                        id: siblingID,
                        page: .directory,
                        anchor: .directory(path: "/Users/test/LegacySibling/\(name)"),
                        isPinned: false,
                        title: "Sibling",
                        iconName: "folder",
                    ),
                ],
                activeTabID: siblingID,
                pinnedRecords: [targetID: record],
            )
            state.contentTabs.selectedTabIDs = [targetID, siblingID]
            state.contentTabs.selectionAnchorID = siblingID
            var cachedContent = FileManagerContentFeature.State()
            if let sessionID = tabCase.aiSessionID {
                cachedContent = .initialContent(
                    for: .aiChat(sessionID: sessionID.rawValue.uuidString),
                    inheritingWindowContextFrom: state.content,
                )
                cachedContent.aiChat.sessionID = sessionID
                cachedContent.aiChat.mode = .chat
                cachedContent.aiChat.draftText = "legacy owner draft"
                state.backgroundAiChatStates[sessionID] = cachedContent
            } else if name == "temporary" {
                cachedContent.entryViewLayout.isCollectionMode = true
                cachedContent.navigation.navigationState = .collection(.init(
                    kind: .temporary,
                    context: .init(),
                    sortKey: .name,
                    sortOrder: .ascending,
                    viewLayout: .list,
                ))
            }
            state.tabContentStates[targetID] = cachedContent
            state.syncContentTabSidebarItems()
            return LegacyUnsupportedUnpinFixture(
                name: name,
                state: state,
                targetID: targetID,
                siblingID: siblingID,
                aiSessionID: tabCase.aiSessionID,
            )
        }
    }

    private struct PinOrderingRollbackFixture {
        let state: ContentTabState
        let targetID: ContentTabID
        let originalIDs: [ContentTabID]
        let originalPinnedRecords: [ContentTabID: ContentTabPinnedRecord]
        let selectedTabIDs: Set<ContentTabID>
        let selectionAnchorID: ContentTabID
    }

    private struct OrdinaryPinOrderingFixture {
        let state: ContentTabState
        let recorder: PinnedRecordStoreRecorder
        let firstID: ContentTabID
        let secondID: ContentTabID
        let allTagsID: ContentTabID
        let firstAnchor: ContentTabPageAnchor
        let secondAnchor: ContentTabPageAnchor
        let expectedRuntimeIDs: [ContentTabID]
        let expectedPinnedIDs: [ContentTabID]
    }

    private static var ordinaryPinOrderingFixture: OrdinaryPinOrderingFixture {
        let recentsID = ContentTabID(rawValue: "built-in-collection-recents")
        let ordinaryID = ContentTabID(rawValue: "wonsik")
        let allTagsID = ContentTabID(rawValue: "built-in-collection-all-tags")
        let firstID = ContentTabID(rawValue: "first-new-pin")
        let secondID = ContentTabID(rawValue: "second-new-pin")
        let trailingID = ContentTabID(rawValue: "remaining-unpinned")
        let recentsURL = URL(fileURLWithPath: "/Users/test/Recents.voycollection")
        let allTagsURL = URL(fileURLWithPath: "/Users/test/All Tags.voycollection")
        let firstAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/First")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Second")
        let recentsRecord = pinnedRecord(
            id: recentsID,
            page: .collection,
            anchor: .collectionFile(url: recentsURL),
            title: "Recents",
            iconName: "clock",
        )
        let ordinaryRecord = pinnedRecord(
            id: ordinaryID,
            anchor: .directory(path: "/Users/test/wonsik"),
            title: "wonsik",
        )
        let allTagsRecord = pinnedRecord(
            id: allTagsID,
            page: .collection,
            anchor: .collectionFile(url: allTagsURL),
            title: "All Tags",
            iconName: "tag",
        )
        let recorder = PinnedRecordStoreRecorder()
        _ = recorder.record(ContentTabPinnedRecordStore(records: [allTagsRecord, ordinaryRecord, recentsRecord]))
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: allTagsID,
                    page: .collection,
                    anchor: .collectionFile(url: allTagsURL),
                    isPinned: true,
                    title: "All Tags",
                    iconName: "tag",
                ),
                pinnedItem(
                    id: ordinaryID,
                    anchor: .directory(path: "/Users/test/wonsik"),
                    title: "wonsik",
                ),
                ContentTabItem(
                    id: recentsID,
                    page: .collection,
                    anchor: .collectionFile(url: recentsURL),
                    isPinned: true,
                    title: "Recents",
                    iconName: "clock",
                ),
                ContentTabItem(
                    id: firstID,
                    page: .directory,
                    anchor: firstAnchor,
                    isPinned: false,
                    title: "First",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: secondID,
                    page: .directory,
                    anchor: secondAnchor,
                    isPinned: false,
                    title: "Second",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: trailingID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Remaining"),
                    isPinned: false,
                    title: "Remaining",
                    iconName: "folder",
                ),
            ],
            activeTabID: firstID,
            pinnedRecords: [recentsID: recentsRecord, ordinaryID: ordinaryRecord, allTagsID: allTagsRecord],
        )
        state.selectedTabIDs = [firstID, secondID]
        state.selectionAnchorID = allTagsID
        return OrdinaryPinOrderingFixture(
            state: state,
            recorder: recorder,
            firstID: firstID,
            secondID: secondID,
            allTagsID: allTagsID,
            firstAnchor: firstAnchor,
            secondAnchor: secondAnchor,
            expectedRuntimeIDs: [allTagsID, ordinaryID, recentsID, firstID, secondID, trailingID],
            expectedPinnedIDs: [allTagsID, ordinaryID, recentsID, firstID, secondID],
        )
    }

    private func assertSupportedPinEligibility() {
        let directoryTab = ContentTabItem(
            id: ContentTabID(rawValue: "directory"),
            page: .directory,
            anchor: .directory(path: "/Users/test/Documents"),
            isPinned: false,
            title: "Documents",
            iconName: "folder",
        )
        XCTAssertTrue(pinEligibilityWindowState(tab: directoryTab, isActive: true).canPinContentTab(directoryTab.id))
        XCTAssertTrue(pinEligibilityWindowState(tab: directoryTab, isActive: false).canPinContentTab(directoryTab.id))

        let savedURL = URL(fileURLWithPath: "/Users/test/Saved.voyagercollection")
        let savedTab = ContentTabItem(
            id: ContentTabID(rawValue: "saved-collection"),
            page: .collection,
            anchor: .collectionFile(url: savedURL),
            isPinned: false,
            title: "Saved",
            iconName: "rectangle.stack",
        )
        let savedContent = savedCollectionContent(url: savedURL)
        XCTAssertTrue(
            pinEligibilityWindowState(tab: savedTab, isActive: true, content: savedContent)
                .canPinContentTab(savedTab.id),
        )
        XCTAssertTrue(
            pinEligibilityWindowState(tab: savedTab, isActive: false, content: savedContent)
                .canPinContentTab(savedTab.id),
        )
    }

    private func assertUnsupportedPagePinEligibility() {
        var missingState = FileManagerFeature.State()
        missingState.contentTabs = ContentTabState(tabs: [], activeTabID: nil)
        XCTAssertFalse(missingState.canPinContentTab(ContentTabID(rawValue: "missing")))

        let cases: [ContentTabItem] = [
            .init(
                id: ContentTabID(rawValue: "home"),
                page: .home,
                anchor: .homeDefault,
                isPinned: false,
                title: "Home",
                iconName: "house",
            ),
            .init(
                id: ContentTabID(rawValue: "ai-chat"),
                page: .aiChat,
                anchor: .aiChat(sessionID: "session"),
                isPinned: false,
                title: "AI Chat",
                iconName: "bubble.right",
            ),
            .init(
                id: ContentTabID(rawValue: "virtual"),
                page: .collection,
                anchor: .virtualCollection(id: "Recents"),
                isPinned: false,
                title: "Recents",
                iconName: "clock",
            ),
        ]
        for (index, tab) in cases.enumerated() {
            XCTAssertFalse(pinEligibilityWindowState(tab: tab, isActive: index != 1).canPinContentTab(tab.id))
        }
    }

    private func assertUnsavedAndTemporaryCollectionPinEligibility() {
        let temporaryState = temporaryCollectionWindowState(tabID: ContentTabID(rawValue: "temporary"))
        let temporaryTab = temporaryState.contentTabs.tabs[0]
        XCTAssertFalse(temporaryState.canPinContentTab(temporaryTab.id))
        XCTAssertFalse(
            pinEligibilityWindowState(tab: temporaryTab, isActive: false, content: temporaryState.content)
                .canPinContentTab(temporaryTab.id),
        )

        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = CollectionContext(query: "draft", scopes: [], conditions: [])
        let tab = ContentTabItem(
            id: ContentTabID(rawValue: "unsaved"),
            page: .collection,
            anchor: .collectionFile(url: URL(fileURLWithPath: "/Users/test/Unsaved.voyagercollection")),
            isPinned: false,
            title: "Unsaved",
            iconName: "rectangle.stack",
        )
        XCTAssertFalse(pinEligibilityWindowState(tab: tab, isActive: true, content: content).canPinContentTab(tab.id))
        XCTAssertFalse(pinEligibilityWindowState(tab: tab, isActive: false, content: content).canPinContentTab(tab.id))
    }

    private func pinEligibilityWindowState(
        tab: ContentTabItem,
        isActive: Bool,
        content: FileManagerContentFeature.State? = nil,
    ) -> FileManagerFeature.State {
        let activeID = isActive ? tab.id : ContentTabID(rawValue: "eligibility-home")
        let homeTab = ContentTabItem(
            id: activeID,
            page: .home,
            anchor: .homeDefault,
            isPinned: false,
            title: "Home",
            iconName: "house",
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: isActive ? [tab] : [homeTab, tab],
            activeTabID: activeID,
        )
        if let content {
            if isActive {
                state.content = content
            } else {
                state.tabContentStates[tab.id] = content
            }
        }
        return state
    }

    private func savedCollectionContent(url: URL) -> FileManagerContentFeature.State {
        let context = CollectionContext(query: "saved", scopes: ["/Users/test"], conditions: [])
        var content = FileManagerContentFeature.State()
        content.entryViewLayout.isCollectionMode = true
        content.collection.collectionContext = context
        content.collection.collectionSession.document = .init(url: url, name: "Saved")
        content.collection.collectionSession.metadata.baseline = .init(context: context)
        content.navigation.navigationState = .collection(.init(
            kind: .file(url: url, name: "Saved"),
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        ))
        return content
    }

    private static var pinOrderingRollbackFixture: PinOrderingRollbackFixture {
        let recentsID = ContentTabID(rawValue: "built-in-collection-recents")
        let allTagsID = ContentTabID(rawValue: "built-in-collection-all-tags")
        let leadingID = ContentTabID(rawValue: "rollback-pin-leading")
        let targetID = ContentTabID(rawValue: "rollback-pin-target")
        let trailingID = ContentTabID(rawValue: "rollback-pin-trailing")
        let recentsURL = URL(fileURLWithPath: "/Users/test/Recents.voycollection")
        let allTagsURL = URL(fileURLWithPath: "/Users/test/All Tags.voycollection")
        let targetAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Target")
        let recentsRecord = pinnedRecord(
            id: recentsID,
            page: .collection,
            anchor: .collectionFile(url: recentsURL),
            title: "Recents",
            iconName: "clock",
        )
        let allTagsRecord = pinnedRecord(
            id: allTagsID,
            page: .collection,
            anchor: .collectionFile(url: allTagsURL),
            title: "All Tags",
            iconName: "tag",
        )
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: recentsID,
                    page: .collection,
                    anchor: .collectionFile(url: recentsURL),
                    isPinned: true,
                    title: "Recents",
                    iconName: "clock",
                ),
                ContentTabItem(
                    id: allTagsID,
                    page: .collection,
                    anchor: .collectionFile(url: allTagsURL),
                    isPinned: true,
                    title: "All Tags",
                    iconName: "tag",
                ),
                ContentTabItem(
                    id: leadingID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Leading"),
                    isPinned: false,
                    title: "Leading",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: targetID,
                    page: .directory,
                    anchor: targetAnchor,
                    isPinned: false,
                    title: "Target",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: trailingID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Trailing"),
                    isPinned: false,
                    title: "Trailing",
                    iconName: "folder",
                ),
            ],
            activeTabID: targetID,
            pinnedRecords: [recentsID: recentsRecord, allTagsID: allTagsRecord],
        )
        let selectedTabIDs: Set<ContentTabID> = [targetID, trailingID]
        state.selectedTabIDs = selectedTabIDs
        state.selectionAnchorID = allTagsID
        return PinOrderingRollbackFixture(
            state: state,
            targetID: targetID,
            originalIDs: state.tabs.map(\.id),
            originalPinnedRecords: state.pinnedRecords,
            selectedTabIDs: selectedTabIDs,
            selectionAnchorID: allTagsID,
        )
    }

    private static func expectOptimisticOrderedPin(
        _ state: inout ContentTabState,
        fixture: PinOrderingRollbackFixture,
    ) {
        state.tabs[id: fixture.targetID]?.isPinned = true
        state.tabs.move(fromOffsets: [3], toOffset: 2)
        state.pinnedRecords[fixture.targetID] = pinnedRecord(
            id: fixture.targetID,
            anchor: .directory(path: "/Users/test/Target"),
            title: "Target",
            iconName: "folder",
        )
        state.pendingPinnedRecordIDs.insert(fixture.targetID)
    }

    private static func expectOrderedPinRollback(
        _ state: inout ContentTabState,
        fixture: PinOrderingRollbackFixture,
        hasError: Bool,
    ) {
        state.tabs.move(fromOffsets: [2], toOffset: 4)
        state.tabs[id: fixture.targetID]?.isPinned = false
        state.pinnedRecords = fixture.originalPinnedRecords
        state.pendingPinnedRecordIDs.remove(fixture.targetID)
        state.pinnedRecordPersistenceError = hasError ? "pinned_record_save_failed" : nil
    }

    private static func assertOrderedPinSnapshot(
        _ state: ContentTabState,
        fixture: PinOrderingRollbackFixture,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.tabs.map(\.id), fixture.originalIDs, file: file, line: line)
        XCTAssertEqual(state.tabs[id: fixture.targetID]?.isPinned, false, file: file, line: line)
        XCTAssertEqual(state.pinnedRecords, fixture.originalPinnedRecords, file: file, line: line)
        XCTAssertEqual(state.selectedTabIDs, fixture.selectedTabIDs, file: file, line: line)
        XCTAssertEqual(state.selectionAnchorID, fixture.selectionAnchorID, file: file, line: line)
    }

    private static func selectionPreservationState(
        targetID: ContentTabID,
        anchorID: ContentTabID,
        targetAnchor: ContentTabPageAnchor,
        targetTitle: String,
        isPinned: Bool = false,
        previousActiveTabID: ContentTabID? = nil,
        pinnedRecord: ContentTabPinnedRecord? = nil,
    ) -> ContentTabState {
        var state = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: targetID,
                    page: .directory,
                    anchor: targetAnchor,
                    isPinned: isPinned,
                    title: targetTitle,
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: anchorID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: targetID,
            previousActiveTabID: previousActiveTabID,
        )
        if let pinnedRecord {
            state.pinnedRecords[targetID] = pinnedRecord
        }
        state.selectedTabIDs = [targetID]
        state.selectionAnchorID = anchorID
        return state
    }

    private static func expectPinnedState(
        _ state: inout ContentTabState,
        targetID: ContentTabID,
        targetAnchor: ContentTabPageAnchor,
    ) {
        state.tabs[id: targetID]?.isPinned = true
        state.pinnedRecords[targetID] = pinnedRecord(
            id: targetID,
            anchor: targetAnchor,
            title: "Pin Target",
            iconName: "folder",
        )
        state.pendingPinnedRecordIDs.insert(targetID)
    }

    private func makePinPresentation(
        clickedTabID: ContentTabID,
        validSelectedTabIDs: Set<ContentTabID>,
        isPinned: Bool,
        isCloseEnabled: Bool,
        isPinMutationEnabled: Bool,
    ) -> ContentTabPinPresentation {
        let surface = ContentTabRowInteractionSurface(
            currentTabIDs: Array(validSelectedTabIDs),
            validSelectedTabIDs: validSelectedTabIDs,
            isCloseEnabled: isCloseEnabled,
            isPinMutationEnabled: isPinMutationEnabled,
        )
        return ContentTabPinPresentation(
            clickedTabID: clickedTabID,
            isPinned: isPinned,
            validSelectedTabIDs: surface.validSelectedTabIDs,
            isPinMutationEnabled: surface.isPinMutationEnabled,
            isSingleUnpinEnabled: surface.isCloseEnabled,
        )
    }

    private static func expectPinRollbackState(
        _ state: inout ContentTabState,
        targetID: ContentTabID,
    ) {
        state.tabs[id: targetID]?.isPinned = false
        state.pinnedRecords.removeAll()
        state.pendingPinnedRecordIDs.remove(targetID)
        state.pinnedRecordPersistenceError = "pinned_record_save_failed"
    }

    private static func expectUnpinnedState(
        _ state: inout ContentTabState,
        targetID: ContentTabID,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        guard var unpinnedTab = state.tabs[id: targetID] else {
            XCTFail("Expected target tab before unpin", file: file, line: line)
            return
        }
        state.previousActiveTabID = nil
        unpinnedTab.isPinned = false
        state.tabs.remove(id: targetID)
        state.tabs.append(unpinnedTab)
        state.pinnedRecords.removeAll()
        state.pendingPinnedRecordIDs.insert(targetID)
    }

    private static func assertSelection(
        _ state: ContentTabState,
        targetID: ContentTabID,
        anchorID: ContentTabID,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertEqual(state.selectedTabIDs, [targetID], file: file, line: line)
        XCTAssertEqual(state.selectionAnchorID, anchorID, file: file, line: line)
    }

    private static func pinnedMergeSelectionState(
        survivingPinnedID: ContentTabID,
        removedPinnedID: ContentTabID,
        survivingUnpinnedID: ContentTabID,
        survivingAnchor: ContentTabPageAnchor,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: survivingPinnedID,
                    page: .directory,
                    anchor: survivingAnchor,
                    isPinned: true,
                    title: "Surviving",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: removedPinnedID,
                    page: .directory,
                    anchor: .directory(path: "/Users/test/Removed"),
                    isPinned: true,
                    title: "Removed",
                    iconName: "folder",
                ),
                ContentTabItem(
                    id: survivingUnpinnedID,
                    page: .home,
                    anchor: .homeDefault,
                    isPinned: false,
                    title: "Home",
                    iconName: "house",
                ),
            ],
            activeTabID: survivingUnpinnedID,
        )
        state.contentTabs.selectedTabIDs = [survivingPinnedID, removedPinnedID, survivingUnpinnedID]
        state.contentTabs.selectionAnchorID = survivingPinnedID
        return state
    }
}
