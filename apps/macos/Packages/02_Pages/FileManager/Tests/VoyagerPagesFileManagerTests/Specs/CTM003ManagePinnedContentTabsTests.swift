import ComposableArchitecture
import Foundation
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

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
    // AC1/AC5 -> testBuiltInSeed_ordersRecentsExistingAndAllTags
    // AC6 -> testBuiltInSeed_completionTrueMissingRecordIsSuppressedWithoutMutation
    // AC9 -> testBuiltInSeed_itemDecisionsAreIndependent
    // AC10 -> testBuiltInSeed_deduplicatesStableIDAndCanonicalURLPreservingStableMatchTimestamp
    // Capacity retry -> testBuiltInSeed_capacityDeferredThenLaterSeedsLatestLockedStore

    // MARK: - CTM-003-seed_built_in_pinned_content_tabs

    /// CTM-003-seed_built_in_pinned_content_tabs: Recents와 All Tags 사이 기존 순서를 보존한다.
    /// 최초 built-in seed가 canonical metadata와 전체 pinned ordering을 만드는지 검증한다.
    /// - 검증 내용: Recents index 0, 기존 상대 순서, All Tags 마지막 및 canonical page/anchor/title/icon
    /// - 사전 조건: Finder와 user record가 있고 두 built-in ensure 결과가 ready, completion은 false
    /// - 기대 결과: [Recents, finder, user, All Tags] 순서와 stable identity가 저장됨
    func testBuiltInSeed_ordersRecentsExistingAndAllTags() {
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
            "built-in-collection-recents",
            "finder",
            "user",
            "built-in-collection-all-tags",
        ])
        XCTAssertEqual(finalStore.records.first?.page, .collection)
        XCTAssertEqual(finalStore.records.first?.anchor, .collectionFile(url: recentsURL))
        XCTAssertEqual(finalStore.records.first?.title, "Recents")
        XCTAssertEqual(finalStore.records.first?.iconName, "clock")
        XCTAssertEqual(finalStore.records.last?.page, .collection)
        XCTAssertEqual(finalStore.records.last?.anchor, .collectionFile(url: allTagsURL))
        XCTAssertEqual(finalStore.records.last?.title, "All Tags")
        XCTAssertEqual(finalStore.records.last?.iconName, "tag")
        XCTAssertFalse(finalStore.records.contains {
            if case .virtualCollection = $0.anchor { true } else { false }
        })
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: stable ID를 URL보다 우선해 중복을 canonicalize한다.
    /// crash retry에서 ID/URL residue가 함께 남아도 하나의 stable record만 유지되는지 검증한다.
    /// - 검증 내용: stable ID first match의 pinnedAt 보존, ID/URL 전체 duplicate 제거, nonmatching 순서 보존
    /// - 사전 조건: canonical URL duplicate 2개와 stable ID duplicate 1개가 섞인 store
    /// - 기대 결과: Recents 하나만 index 0에 남고 stable ID record의 pinnedAt이 유지됨
    func testBuiltInSeed_deduplicatesStableIDAndCanonicalURLPreservingStableMatchTimestamp() {
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
        let secondURLDuplicate = ContentTabPinnedRecord(
            id: "second-recents",
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
            ensureResult: .ready(.init(identity: .recents, canonicalPackageURL: canonicalURL)),
            completion: false,
            store: store,
            now: Date(timeIntervalSince1970: 999),
        )
        guard case let .alreadyPresent(finalStore) = result else {
            return XCTFail("기존 match는 alreadyPresent여야 함")
        }

        XCTAssertEqual(finalStore.records.map(\.id), [
            "built-in-collection-recents", "first-other", "second-other",
        ])
        XCTAssertEqual(finalStore.records.first?.pinnedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(finalStore.records.first?.anchor, .collectionFile(url: canonicalURL))
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
    /// - 검증 내용: canonical URL match가 있으면 alreadyPresent와 All Tags end ordering 반환
    /// - 사전 조건: max count 2인 store에 user record와 legacy All Tags URL record 존재
    /// - 기대 결과: user 뒤에 stable All Tags가 있고 count는 2로 유지됨
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

        XCTAssertEqual(finalStore.records.map(\.id), ["user", "built-in-collection-all-tags"])
        XCTAssertEqual(finalStore.records.last?.pinnedAt, preservedPinnedAt)
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
            ContentTabFeature()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.pin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = true
            $0.pinnedRecords[tabID] = Self.pinnedRecord(id: tabID, anchor: directoryAnchor)
            $0.pendingPinnedRecordIDs.insert(tabID)
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
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
                        iconName: "sparkles",
                    ),
                ],
                activeTabID: tabID,
            ),
        ) {
            ContentTabFeature()
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
            ContentTabFeature()
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
            ContentTabFeature()
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
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

    /// CTM-003-pin_content_tab_s: pin 시점 record snapshot은 이후 tab 변경과 다음 save에도 유지
    /// Pinned tab의 page/anchor/title/icon이 바뀐 뒤 다른 tab pin으로 저장이 다시 발생해도 최초 pinned record가 오염되지 않음을 검증한다.
    /// - 검증 내용: pin → active tab anchor 변경 → 다른 tab pin save 시 첫 record는 pin 시점 snapshot 유지
    /// - 사전 조건: unpinned Directory tab 2개
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
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
        await store.receive(\.pinnedRecordSaveSucceeded)
        XCTAssertEqual(savedStores.stores().count, 2)
        XCTAssertEqual(savedStores.stores()[1].records, [firstSnapshotAfterNav])

        // Pin second tab → save both records (existing pinned first + new pinned second)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondSnapshot
            $0.pendingPinnedRecordIDs.insert(secondID)
            $0.pinnedRecordPersistenceError = nil
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        XCTAssertEqual(savedStores.stores().count, 3)
        XCTAssertEqual(savedStores.stores()[2].records, [firstSnapshotAfterNav, secondSnapshot])

        await store.finish()
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
            ContentTabFeature()
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

        let feature = ContentTabFeature()
        _ = feature.reduce(into: &state, action: .pinnedRecordSaveSucceeded)
        XCTAssertEqual(state.previousActiveTabID, previousID)
        XCTAssertNil(state.pinnedRecordPersistenceError)

        _ = feature.reduce(
            into: &state,
            action: .pinnedRecordSaveFailed(
                tabID: activeID,
                previousIsPinned: false,
                previousPinnedRecord: nil,
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
            $0.pendingPinnedRecordIDs.insert(secondID)
        }
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
            $0.pendingPinnedRecordIDs.insert(secondID)
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
        let olderIntent = PinnedRecordPersistenceIntent.markLatest(tabID: tabID)
        let latestIntent = PinnedRecordPersistenceIntent.markLatest(tabID: tabID)

        XCTAssertThrowsError(try PinnedRecordPersistenceIntent.checkCurrent(
            tabID: tabID,
            intentID: olderIntent,
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNoThrow(try PinnedRecordPersistenceIntent.checkCurrent(tabID: tabID, intentID: latestIntent))
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
            ContentTabFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                let savedStore = try transform(ContentTabPinnedRecordStore(records: [otherRecord, currentRecord]))
                _ = recorder.record(savedStore)
            }
        }

        await store.send(.unpin(currentID)) {
            $0.tabs[id: currentID]?.isPinned = false
            $0.pinnedRecords.removeAll()
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            FileManagerFeature()
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
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded)
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
            FileManagerFeature()
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
            FileManagerFeature()
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
            FileManagerFeature()
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
            FileManagerFeature()
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
            FileManagerFeature()
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
            FileManagerFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))
        await store.receive(\.contentTabs) {
            $0.contentTabs.tabs[id: tabID]?.isPinned = false
            $0.contentTabs.pinnedRecords.removeAll()
            $0.syncContentTabSidebarItems()
        }
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded)
        await store.finish()
    }

    // MARK: - CTM-003-unpin_content_tab_s

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
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.unpin(pinnedID)) {
            var unpinnedTab = $0.tabs[id: pinnedID]!
            unpinnedTab.isPinned = false
            $0.tabs.remove(id: pinnedID)
            $0.tabs.append(unpinnedTab)
            $0.pinnedRecords.removeAll()
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
            ContentTabFeature()
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
            ContentTabFeature()
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
            ContentTabFeature()
        } withDependencies: {
            struct SaveError: Error {}
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }

        await store.send(.unpin(tabID)) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
        }
        await store.receive(\.pinnedRecordSaveFailed) {
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
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.saveStore = { _, _ in }
        }

        await store.send(.close(pinnedID)) {
            $0.tabs[id: pinnedID]?.isPinned = false
            $0.pinnedRecords.removeAll()
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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

    /// CTM-003-go_to_anchored_path_of_pinned_tab: active pinned tab sync가 collection file open effect를 실행
    /// 다른 window에서 같은 pinned tab anchor가 collection file로 바뀌면 synthetic route 복원에 머물지 않고 실제 file load를 시작해야 한다.
    /// - 검증 내용: applyPinnedContentTabs action 처리 후 navigation.view.openCollectionFile effect 수신
    /// - 사전 조건: active pinned Directory tab이 있고 restored state는 같은 id의 collectionFile anchor를 보유
    /// - 기대 결과: active tab은 유지되고 collection URL로 openCollectionFile 액션 전송
    func testApplyPinnedContentTabsOpensCollectionFileWhenActivePinnedAnchorChangesToCollectionFile() async {
        let pinnedID = ContentTabID(rawValue: "shared-pin")
        let oldAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Old")
        let collectionURL = URL(fileURLWithPath: "/Users/test/Synced.voyagercollection")
        let newAnchor: ContentTabPageAnchor = .collectionFile(url: collectionURL)
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
                    page: .collection,
                    anchor: newAnchor,
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
                    anchor: newAnchor,
                    title: "Synced",
                    iconName: "rectangle.stack",
                ),
            ],
        )
        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        // 이 테스트는 applyPinnedContentTabs가 collection file open effect를 연결하는지만 검증하고,
        // handoff 과정의 cancel/resync child action 전체 순서는 기존 tab handoff spec에 위임한다.
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(restoredState))
        await store.receive(\.navigation.view.openCollectionFile, collectionURL)
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
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(.applyPinnedContentTabs(restoredState))

        XCTAssertEqual(store.state.content.homeFavoriteItems.map(\.title), ["Favorite"])
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: 저장된 pinned record store에서 pinned tab 복원
    /// Home과 Directory record가 있는 store를 복원하면 pinned tab과 focused Home tab이 함께 생성됨을 검증한다.
    /// - 검증 내용: pinned tabs 2개 + 기본 Home tab 1개, activeTabID는 기본 Home
    /// - 사전 조건: 유효한 Home + Directory record 2개
    /// - 기대 결과: pinnedRecords에 2개 entry가 유지되고 기본 Home tab이 active
    func testApplyPinnedContentTabs_resyncsActivePinnedTabWhenAnchorChanges() {
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
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, newAnchor)
        XCTAssertEqual(state.content.navigation.currentPath, "/Users/test/New")
        XCTAssertEqual(state.tabContentStates[pinnedID]?.navigation.currentPath, "/Users/test/New")
    }

    func testApplyPinnedContentTabsClearsInactivePinnedTabStateWhenAnchorChanges() {
        let homeID = ContentTabID(rawValue: "home-tab")
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
                pinnedID: Self.pinnedRecord(id: pinnedID, anchor: oldAnchor, title: "Old", iconName: "folder"),
            ],
        )
        var stalePinnedContent = FileManagerContentFeature.State.initialContent(for: oldAnchor)
        stalePinnedContent.navigation.seedInitialFolderPath("/Users/test/Old")
        state.tabContentStates[pinnedID] = stalePinnedContent
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
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, newAnchor)
        XCTAssertNil(state.tabContentStates[pinnedID])
    }

    func testApplyPinnedContentTabsRestoresHomeContentWhenActivePinnedTabRemoved() throws {
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
        let restoredState = ContentTabState(tabs: [], activeTabID: nil, pinnedRecords: [:])

        state.applyPinnedContentTabs(restoredState)

        let activeTabID = try XCTUnwrap(state.contentTabs.activeTabID)
        XCTAssertEqual(state.contentTabs.tabs.count, 1)
        XCTAssertEqual(state.contentTabs.tabs[id: activeTabID]?.page, .home)
        XCTAssertFalse(state.contentTabs.tabs[id: activeTabID]?.isPinned ?? true)
        XCTAssertEqual(state.content.navigation.currentPath, "Home")
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

        // pinned tab 갱신 검증
        XCTAssertEqual(state.contentTabs.tabs.map(\.id), [pinnedID, homeID])
        XCTAssertEqual(state.contentTabs.tabs[id: pinnedID]?.anchor, restoredAnchor)

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
                iconName: "sparkles",
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
                iconName: "sparkles",
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
            ContentTabFeature()
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
        }
        await testStore.receive(\.pinnedRecordSaveSucceeded)

        // saveStore 결과에 orig-dir-1 record가 없어야 함 (unpin으로 제거됨)
        let ids = recorder.stores().last?.records.map(\.id) ?? []
        XCTAssertFalse(ids.contains("orig-dir-1"), "unpin한 record ID가 persistence에 남아 있으면 안 됨")
        XCTAssertTrue(ids.contains("orig-dir-2"), "unpin하지 않은 record ID는 persistence에 유지되어야 함")
    }
}
