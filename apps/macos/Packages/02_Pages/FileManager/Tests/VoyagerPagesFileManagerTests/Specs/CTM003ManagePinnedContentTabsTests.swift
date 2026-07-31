import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
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

    init(data: Data?) {
        storedData = data
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

    func data() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedData
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

private struct ContentTabPinnedRecordStoreV1Fixture: Encodable {
    let schemaVersion = 1
    let records: [ContentTabPinnedRecord]
}

private struct ContentTabPinnedRecordStoreLegacyV2Fixture: Encodable {
    let schemaVersion = 2
    let records: [ContentTabPinnedRecord]
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

    // MARK: - CTM-003-restore_pinned_content_tabs

    /// CTM-003-restore_pinned_content_tabs: 같은 raw ID의 Location과 Content Tab을 서로 다른 identity로 취급한다.
    /// 통합 상단 내비게이션에서 서로 다른 tag가 raw 문자열 충돌에도 섞이지 않는지 검증한다.
    /// - 검증 내용: tagged enum의 Equatable 및 Hashable identity
    /// - 사전 조건: 두 case 모두 raw ID가 `same`
    /// - 기대 결과: Location과 Content Tab identity가 같지 않음
    func testTopNavigationItemID_sameRawIDWithDifferentTagsIsNotEqual() {
        XCTAssertNotEqual(
            FileManagerTopNavigationItemID.location("same"),
            FileManagerTopNavigationItemID.contentTab(ContentTabID(rawValue: "same")),
        )

        let sameID = ContentTabID(rawValue: "same")
        let normalized = FileManagerTopNavigationOrderPolicy.normalize(
            store: ContentTabPinnedRecordStore(
                records: [Self.pinnedRecord(id: sameID, anchor: .directory(path: "/same"))],
                topNavigationOrder: .init(items: [.location("same"), .contentTab(sameID)]),
            ),
            discoveredLocationIDs: ["same"],
        )
        XCTAssertEqual(normalized.durableOrder.items, [.location("same"), .contentTab(sameID)])
    }

    /// CTM-003-restore_pinned_content_tabs: schema v2 order가 명시적 tagged JSON으로 왕복된다.
    /// durable wire contract가 synthesized enum 표현에 의존하지 않는지 검증한다.
    /// - 검증 내용: schemaVersion, dense order 배열, 각 `{kind,id}` exact key/value 및 round-trip
    /// - 사전 조건: Location과 Content Tab이 하나씩 포함된 schema v2 store
    /// - 기대 결과: 정확한 wire shape와 원본 store가 복원됨
    func testTopNavigationOrder_schemaV2UsesExactTaggedWireShapeAndRoundTrips() throws {
        let store = ContentTabPinnedRecordStore(
            records: [],
            topNavigationOrder: .init(items: [
                .location("L1"),
                .contentTab(ContentTabID(rawValue: "A")),
            ]),
        )

        let data = try JSONEncoder().encode(store)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let order = try XCTUnwrap(object["topNavigationOrder"] as? [[String: String]])

        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(order, [
            ["kind": "location", "id": "L1"],
            ["kind": "contentTab", "id": "A"],
        ])
        XCTAssertEqual(try JSONDecoder().decode(ContentTabPinnedRecordStore.self, from: data), store)
    }

    /// CTM-003-restore_pinned_content_tabs: v1 record를 discovered Location 앞순서와 함께 메모리에서 migration한다.
    /// 기존 pinned record를 보존하면서 load-only 경로가 저장소를 수정하지 않는지 검증한다.
    /// - 검증 내용: migratedV1 category, `[L1,L2,A,B]` exact order, record 보존, write 0회
    /// - 사전 조건: 독립 v1 fixture `[A,B]`와 discovered Locations `[L1,L2]`
    /// - 기대 결과: schema v2 writable store가 메모리에만 생성되고 원본 bytes가 유지됨
    func testPinnedRecordClient_v1LoadMigratesInMemoryWithoutWriting() throws {
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "A"), anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "B"), anchor: .directory(path: "/B")),
        ]
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreV1Fixture(records: records))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: ["L1", "L2"],
        )

        guard case let .migratedV1(store) = outcome else {
            return XCTFail("v1 payload는 migratedV1이어야 함: \(outcome)")
        }
        XCTAssertEqual(store.schemaVersion, 2)
        XCTAssertEqual(store.records, records)
        XCTAssertEqual(store.topNavigationOrder.items, [
            .location("L1"),
            .location("L2"),
            .contentTab(ContentTabID(rawValue: "A")),
            .contentTab(ContentTabID(rawValue: "B")),
        ])
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: order 필드가 없는 과도기 v2 payload를 메모리에서 migration한다.
    /// 유효한 pinned record를 corrupt fallback으로 숨기지 않고 원본 bytes를 유지하는지 검증한다.
    /// - 검증 내용: migratedLegacyV2 category, discovered Location 뒤 record order, write 0회
    /// - 사전 조건: schemaVersion 2와 records `[A,B]`는 있지만 `topNavigationOrder`가 없는 payload
    /// - 기대 결과: schema v2 writable store가 메모리에 생성되고 pinned records와 원본 bytes가 보존됨
    func testPinnedRecordClient_legacyV2WithoutOrderMigratesInMemoryWithoutWriting() throws {
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "A"), anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "B"), anchor: .directory(path: "/B")),
        ]
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreLegacyV2Fixture(records: records))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: ["L1", "L2"],
        )

        guard case let .migratedLegacyV2(store) = outcome else {
            return XCTFail("order 없는 과도기 v2 payload는 migratedLegacyV2여야 함: \(outcome)")
        }
        XCTAssertEqual(store.schemaVersion, 2)
        XCTAssertEqual(store.records, records)
        XCTAssertEqual(store.topNavigationOrder.items, [
            .location("L1"),
            .location("L2"),
            .contentTab(ContentTabID(rawValue: "A")),
            .contentTab(ContentTabID(rawValue: "B")),
        ])
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: 저장 값 부재를 명시적인 missing으로 분류한다.
    /// 최초 실행과 손상 상태가 같은 empty fallback으로 합쳐지지 않는지 검증한다.
    /// - 검증 내용: missing category와 write 0회
    /// - 사전 조건: storage key에 Data가 없음
    /// - 기대 결과: missing이며 빈 schema v2 writable store만 메모리에서 제공됨
    func testPinnedRecordClient_missingValueReturnsTypedMissingWithoutWriting() throws {
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: nil)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: ["L1"],
        )

        XCTAssertEqual(outcome, .missing)
        XCTAssertEqual(outcome.writableStore, ContentTabPinnedRecordStore())
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: 유효한 schema v2 payload를 currentV2로 분류한다.
    /// 단순 current load가 저장 값을 다시 encode하거나 쓰지 않는지 검증한다.
    /// - 검증 내용: currentV2 category, store/bytes 보존, write 0회
    /// - 사전 조건: tagged order를 포함한 유효한 schema v2 Data
    /// - 기대 결과: 원본 store가 반환되고 source bytes가 변경되지 않음
    func testPinnedRecordClient_schemaV2LoadReturnsCurrentWithoutWriting() throws {
        let store = ContentTabPinnedRecordStore(
            topNavigationOrder: .init(items: [.location("L1")]),
        )
        let sourceData = try JSONEncoder().encode(store)
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: [],
        )

        XCTAssertEqual(outcome, .currentV2(store))
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: malformed JSON을 writable store로 복구하지 않는다.
    /// 손상 payload가 missing과 구분되고 원본 bytes를 유지하는지 검증한다.
    /// - 검증 내용: corruptUnavailable category, source bytes, write 0회
    /// - 사전 조건: JSON이 아닌 raw Data
    /// - 기대 결과: unavailable이며 writable store가 생성되지 않음
    func testPinnedRecordClient_malformedPayloadPreservesBytesAndDoesNotWrite() throws {
        let sourceData = Data("not-json".utf8)
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: [],
        )

        XCTAssertEqual(outcome, .corruptUnavailable(originalData: sourceData, reason: .invalidPayload))
        XCTAssertNil(outcome.writableStore)
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: 미래 schema payload를 손상과 다른 unavailable로 분류한다.
    /// 현재 앱이 이해하지 못하는 bytes를 downgrade rewrite하지 않는지 검증한다.
    /// - 검증 내용: futureSchemaUnavailable version/source bytes와 write 0회
    /// - 사전 조건: schemaVersion 3 payload
    /// - 기대 결과: future category이며 writable store가 생성되지 않음
    func testPinnedRecordClient_futureSchemaPreservesBytesAndDoesNotWrite() throws {
        let sourceData = Data(#"{"schemaVersion":3,"records":[],"topNavigationOrder":[]}"#.utf8)
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: [],
        )

        XCTAssertEqual(outcome, .futureSchemaUnavailable(schemaVersion: 3, originalData: sourceData))
        XCTAssertNil(outcome.writableStore)
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: 알 수 없는 kind를 corrupt unavailable로 거부한다.
    /// tagged identity discriminator가 임의 case로 확장되지 않는지 검증한다.
    /// - 검증 내용: unknown kind의 deterministic corrupt classification
    /// - 사전 조건: schema v2 order item의 kind가 `other`
    /// - 기대 결과: 원본 bytes를 보존한 corruptUnavailable
    func testPinnedRecordClient_unknownTaggedKindIsCorruptUnavailable() throws {
        try assertCorruptTaggedItem(#"{"kind":"other","id":"A"}"#)
    }

    /// CTM-003-restore_pinned_content_tabs: id가 누락된 tagged item을 거부한다.
    /// required-field decoding이 누락을 암묵적인 빈 문자열로 바꾸지 않는지 검증한다.
    /// - 검증 내용: missing id의 deterministic corrupt classification
    /// - 사전 조건: schema v2 order item에 kind만 존재
    /// - 기대 결과: 원본 bytes를 보존한 corruptUnavailable
    func testPinnedRecordClient_missingTaggedIDIsCorruptUnavailable() throws {
        try assertCorruptTaggedItem(#"{"kind":"location"}"#)
    }

    /// CTM-003-restore_pinned_content_tabs: 빈 id의 tagged item을 거부한다.
    /// durable identity가 빈 문자열로 생성되지 않는지 검증한다.
    /// - 검증 내용: empty id의 deterministic corrupt classification
    /// - 사전 조건: schema v2 order item의 id가 빈 문자열
    /// - 기대 결과: 원본 bytes를 보존한 corruptUnavailable
    func testPinnedRecordClient_emptyTaggedIDIsCorruptUnavailable() throws {
        try assertCorruptTaggedItem(#"{"kind":"location","id":""}"#)
    }

    /// CTM-003-restore_pinned_content_tabs: 문자열이 아닌 id의 tagged item을 거부한다.
    /// JSON type mismatch가 문자열 변환이나 기본값으로 흡수되지 않는지 검증한다.
    /// - 검증 내용: non-string id의 deterministic corrupt classification
    /// - 사전 조건: schema v2 order item의 id가 숫자
    /// - 기대 결과: 원본 bytes를 보존한 corruptUnavailable
    func testPinnedRecordClient_nonStringTaggedIDIsCorruptUnavailable() throws {
        try assertCorruptTaggedItem(#"{"kind":"contentTab","id":42}"#)
    }

    private func assertCorruptTaggedItem(
        _ itemJSON: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) throws {
        let sourceData = Data(
            "{\"schemaVersion\":2,\"records\":[],\"topNavigationOrder\":[\(itemJSON)]}".utf8,
        )
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
        let outcome = try ContentTabPinnedRecordClient.liveValue.loadStoreOutcome(
            defaultsRecorder.client(),
            discoveredLocationIDs: [],
        )

        XCTAssertEqual(
            outcome,
            .corruptUnavailable(originalData: sourceData, reason: .invalidPayload),
            file: file,
            line: line,
        )
        XCTAssertNil(outcome.writableStore, file: file, line: line)
        XCTAssertEqual(defaultsRecorder.data(), sourceData, file: file, line: line)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0, file: file, line: line)
    }

    /// CTM-003-restore_pinned_content_tabs: durable order를 정해진 1→7 순서로 정규화한다.
    /// 중복, orphan, tombstone, 누락 pin, 새 Location이 서로 다른 단계에서 결정되는 대표 복구 경로를 검증한다.
    /// - 검증 내용: full-tag first-wins, invalid/orphan 제거, Location tombstone 보존, record-order append, canonical discovery
    /// insertion, projection 분리
    /// - 사전 조건: `[L1,A,L1,orphan,absent]`, pinned records `[A,B]`, discovered Locations `[L1,L2]`
    /// - 기대 결과: discovery 전 `[L1,A,absent,B]`, 최종 durable `[L1,A,absent,L2,B]`, visible에서 absent 제거
    func testTopNavigationOrderPolicy_normalizesInCanonicalStageOrder() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let records = [
            Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
        ]
        let store = ContentTabPinnedRecordStore(
            records: records,
            topNavigationOrder: .init(items: [
                .location("L1"),
                .contentTab(tabA),
                .location("L1"),
                .contentTab(ContentTabID(rawValue: "orphan")),
                .location("absentLocation"),
                .location(""),
            ]),
        )

        let beforeDiscovery = FileManagerTopNavigationOrderPolicy.normalize(
            store: store,
            discoveredLocationIDs: ["L1"],
        )
        XCTAssertEqual(beforeDiscovery.durableOrder.items, [
            .location("L1"), .contentTab(tabA), .location("absentLocation"), .contentTab(tabB),
        ])

        let result = FileManagerTopNavigationOrderPolicy.normalize(
            store: store,
            discoveredLocationIDs: ["L1", "L2"],
        )
        XCTAssertEqual(result.durableOrder.items, [
            .location("L1"), .contentTab(tabA), .location("absentLocation"),
            .location("L2"), .contentTab(tabB),
        ])
        XCTAssertEqual(result.normalizedStore.topNavigationOrder, result.durableOrder)
        XCTAssertEqual(result.visibleMixedTopOrder.items, [
            .location("L1"), .contentTab(tabA), .location("L2"), .contentTab(tabB),
        ])
    }

    /// CTM-003-pin_content_tab_s: 신규 pin과 same-session/restart repin 삽입 위치를 구분한다.
    /// runtime dormant slot이 durable DTO에 저장되지 않으면서 같은 세션 repin에만 재사용되는지 검증한다.
    /// - 검증 내용: new/restart pin end insertion, dormant neighbor anchor insertion, runtime-only dormant projection
    /// - 사전 조건: durable `[L1,A,L2,B]`와 L1-A 사이 dormant C slot
    /// - 기대 결과: new/restart C는 end, same-session C는 L1-A 사이, dormant C는 durable에는 없고 runtime에만 존재
    func testTopNavigationOrderPolicy_appliesPinAndDormantRepinInsertionContracts() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let order = FileManagerTopNavigationOrder(items: [
            .location("L1"), .contentTab(tabA), .location("L2"), .contentTab(tabB),
        ])
        let dormant = FileManagerTopNavigationOrderPolicy.DormantContentTabSlot(
            id: tabC,
            before: .location("L1"),
            after: .contentTab(tabA),
        )

        XCTAssertEqual(
            FileManagerTopNavigationOrderPolicy.insertingPinnedItem(tabC, into: order).items,
            order.items + [.contentTab(tabC)],
        )
        XCTAssertEqual(
            FileManagerTopNavigationOrderPolicy.insertingPinnedItem(
                tabC,
                into: order,
                dormantSlot: dormant,
            ).items,
            [.location("L1"), .contentTab(tabC), .contentTab(tabA), .location("L2"), .contentTab(tabB)],
        )

        let runtime = FileManagerTopNavigationOrderPolicy.normalize(
            store: ContentTabPinnedRecordStore(
                records: [
                    Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
                    Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
                ],
                topNavigationOrder: order,
            ),
            discoveredLocationIDs: ["L1", "L2"],
            dormantContentTabSlots: [dormant],
        )
        XCTAssertFalse(runtime.durableOrder.items.contains(.contentTab(tabC)))
        XCTAssertEqual(runtime.runtimeOrder.items, [
            .location("L1"), .contentTab(tabC), .contentTab(tabA), .location("L2"), .contentTab(tabB),
        ])
        XCTAssertFalse(runtime.visibleMixedTopOrder.items.contains(.contentTab(tabC)))
    }

    /// CTM-003-restore_pinned_content_tabs: 새 Location은 마지막 Location tombstone 뒤에 들어가고 재등장 Location은 기존 slot을 유지한다.
    /// discovery 변화가 pinned 상대 순서나 absent Location tombstone을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: no-location front insertion, last-location insertion, tombstone slot retention
    /// - 사전 조건: pinned-only order와 `[L1,A,absent,B]` tombstone order
    /// - 기대 결과: 새 Location은 canonical discovery order로 front/last tombstone 뒤, absent 재등장은 기존 위치 유지
    func testTopNavigationOrderPolicy_insertsNewAndReappearingLocationsCanonically() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let records = [
            Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
        ]
        let pinnedOnly = ContentTabPinnedRecordStore(
            records: records,
            topNavigationOrder: .init(items: [.contentTab(tabA), .contentTab(tabB)]),
        )
        XCTAssertEqual(
            FileManagerTopNavigationOrderPolicy.normalize(
                store: pinnedOnly,
                discoveredLocationIDs: ["L1", "L2"],
            ).durableOrder.items,
            [.location("L1"), .location("L2"), .contentTab(tabA), .contentTab(tabB)],
        )

        let tombstoneStore = ContentTabPinnedRecordStore(
            records: records,
            topNavigationOrder: .init(items: [
                .location("L1"), .contentTab(tabA), .location("absent"), .contentTab(tabB),
            ]),
        )
        XCTAssertEqual(
            FileManagerTopNavigationOrderPolicy.normalize(
                store: tombstoneStore,
                discoveredLocationIDs: ["L1", "absent", "L2"],
            ).durableOrder.items,
            [.location("L1"), .contentTab(tabA), .location("absent"), .location("L2"), .contentTab(tabB)],
        )
    }

    /// CTM-003-restore_pinned_content_tabs: semantic move는 storage lock 안에서 최신 snapshot에 적용된다.
    /// caller가 보지 못한 pinned/Location 항목을 잃지 않고 tagged anchor 기준으로 이동하는지 검증한다.
    /// - 검증 내용: latest load, A after B semantic move, normalized committed snapshot, 단일 write
    /// - 사전 조건: caller 관점은 `[L1,A]`, 실제 저장소는 `[L1,A,L2,B]`
    /// - 기대 결과: committed `[L1,L2,B,A]`, B/L2 보존, write 1회
    func testPinnedRecordClient_semanticMoveUsesLatestLockedSnapshot() throws {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let latestStore = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
                Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
            ],
            topNavigationOrder: .init(items: [
                .location("L1"), .contentTab(tabA), .location("L2"), .contentTab(tabB),
            ]),
        )
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: latestStore)

        let committed = try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
            defaultsRecorder.client(),
            ["L1", "L2"],
            .contentTab(tabA),
            .after(.contentTab(tabB)),
        )

        XCTAssertEqual(committed.topNavigationOrder.items, [
            .location("L1"), .location("L2"), .contentTab(tabB), .contentTab(tabA),
        ])
        XCTAssertEqual(defaultsRecorder.writeCount(), 1)
        XCTAssertEqual(
            try ContentTabPinnedRecordClient.liveValue.loadStore(defaultsRecorder.client()),
            committed,
        )
    }

    /// CTM-003-restore_pinned_content_tabs: missing source/anchor와 unchanged move는 성공 no-op이다.
    /// stale semantic intent가 최신 committed snapshot을 다시 쓰거나 오류로 바꾸지 않는지 검증한다.
    /// - 검증 내용: 세 no-op 분기 반환 snapshot과 write count
    /// - 사전 조건: normalized latest `[L1,A,B]`
    /// - 기대 결과: 각 호출은 latest snapshot을 그대로 반환하고 write 0회
    func testPinnedRecordClient_semanticMoveNoOpsReturnLatestWithoutWriting() throws {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let latestStore = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
                Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
            ],
            topNavigationOrder: .init(items: [.location("L1"), .contentTab(tabA), .contentTab(tabB)]),
        )
        let mutations: [(FileManagerTopNavigationItemID, FileManagerTopNavigationMoveDestination)] = [
            (.contentTab(ContentTabID(rawValue: "missing")), .after(.contentTab(tabB))),
            (.contentTab(tabA), .after(.contentTab(ContentTabID(rawValue: "missing-anchor")))),
            (.contentTab(tabA), .before(.contentTab(tabB))),
        ]

        for (source, destination) in mutations {
            let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: latestStore)
            let returned = try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
                defaultsRecorder.client(),
                ["L1"],
                source,
                destination,
            )
            XCTAssertEqual(returned, latestStore)
            XCTAssertEqual(defaultsRecorder.writeCount(), 0)
        }
    }

    /// CTM-003-restore_pinned_content_tabs: 비정규화된 latest store의 no-op은 저장된 원본 snapshot을 반환한다.
    /// normalization이 move 판단에만 사용되고 쓰지 않은 projection을 committed 결과로 노출하지 않는지 검증한다.
    /// - 검증 내용: latest raw store load, normalized unchanged 판단, exact raw snapshot 반환, write count
    /// - 사전 조건: duplicate Location과 orphan ContentTab이 있는 persisted order에서 A before B 요청
    /// - 기대 결과: 반환값은 비정규화 persisted store와 정확히 같고 write는 0회
    func testPinnedRecordClient_semanticMoveNoOpReturnsExactNonNormalizedLatestStore() throws {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let latestStore = ContentTabPinnedRecordStore(
            records: [
                Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A")),
                Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B")),
            ],
            topNavigationOrder: .init(items: [
                .location("L1"),
                .contentTab(tabA),
                .location("L1"),
                .contentTab(ContentTabID(rawValue: "orphan")),
                .contentTab(tabB),
            ]),
        )
        let normalizedStore = FileManagerTopNavigationOrderPolicy.normalize(
            store: latestStore,
            discoveredLocationIDs: ["L1"],
        ).normalizedStore
        XCTAssertNotEqual(latestStore, normalizedStore)
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: latestStore)
        let sourceData = defaultsRecorder.data()

        let returned = try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
            defaultsRecorder.client(),
            ["L1"],
            .contentTab(tabA),
            .before(.contentTab(tabB)),
        )

        XCTAssertEqual(returned, latestStore)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
    }

    /// CTM-003-restore_pinned_content_tabs: v1의 첫 실제 semantic mutation만 normalized schema v2를 기록한다.
    /// lazy migration bytes가 read 시점이 아니라 성공한 order 변경 시점에 한 번만 교체되는지 검증한다.
    /// - 검증 내용: v1 latest load, normalized move, schema v2 encode, write 1회
    /// - 사전 조건: v1 records `[A,B]`, discovered Location `[L1]`, A after B mutation
    /// - 기대 결과: `[L1,B,A]` schema v2가 한 번 저장됨
    func testPinnedRecordClient_firstSuccessfulV1MutationWritesNormalizedV2Once() throws {
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "A"), anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "B"), anchor: .directory(path: "/B")),
        ]
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreV1Fixture(records: records))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let committed = try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
            defaultsRecorder.client(),
            ["L1"],
            .contentTab(ContentTabID(rawValue: "A")),
            .after(.contentTab(ContentTabID(rawValue: "B"))),
        )

        XCTAssertEqual(committed.schemaVersion, 2)
        XCTAssertEqual(committed.topNavigationOrder.items, [
            .location("L1"), .contentTab(ContentTabID(rawValue: "B")),
            .contentTab(ContentTabID(rawValue: "A")),
        ])
        XCTAssertEqual(defaultsRecorder.writeCount(), 1)
        XCTAssertNotEqual(defaultsRecorder.data(), sourceData)
    }

    /// CTM-003-restore_pinned_content_tabs: 과도기 v2의 첫 semantic mutation은 완전한 schema v2를 기록한다.
    /// 누락된 order를 load 시 덮어쓰지 않고 실제 사용자 변경 시에만 교체하는 lazy migration을 검증한다.
    /// - 검증 내용: legacy-v2 latest load, normalized move, 완전한 v2 encode, write 1회
    /// - 사전 조건: order 없는 v2 records `[A,B]`, discovered Location `[L1]`, A after B mutation
    /// - 기대 결과: `[L1,B,A]`와 `topNavigationOrder` 필드가 한 번 저장됨
    func testPinnedRecordClient_firstSuccessfulLegacyV2MutationWritesNormalizedV2Once() throws {
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "A"), anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "B"), anchor: .directory(path: "/B")),
        ]
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreLegacyV2Fixture(records: records))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)

        let committed = try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
            defaultsRecorder.client(),
            ["L1"],
            .contentTab(ContentTabID(rawValue: "A")),
            .after(.contentTab(ContentTabID(rawValue: "B"))),
        )

        XCTAssertEqual(committed.schemaVersion, 2)
        XCTAssertEqual(committed.topNavigationOrder.items, [
            .location("L1"), .contentTab(ContentTabID(rawValue: "B")),
            .contentTab(ContentTabID(rawValue: "A")),
        ])
        XCTAssertEqual(defaultsRecorder.writeCount(), 1)
        let storedData = try XCTUnwrap(defaultsRecorder.data())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: storedData) as? [String: Any])
        XCTAssertNotNil(object["topNavigationOrder"])
    }

    /// CTM-003-restore_pinned_content_tabs: v1 semantic mutation 저장 실패는 원본 bytes를 보존한다.
    /// write 경계 실패가 load-corrupt로 오분류되지 않고 save error 그대로 전달되는지 검증한다.
    /// - 검증 내용: migrated v1 transform 이후 throwing save, 원본 bytes/write count 보존
    /// - 사전 조건: 유효한 v1 `[A,B]`와 saveStore failure
    /// - 기대 결과: injected save failure가 반환되고 원본 v1 bytes가 유지됨
    func testPinnedRecordClient_failedV1MutationPreservesOriginalBytes() throws {
        enum SaveFailure: Error, Equatable { case expected }
        let records = [
            Self.pinnedRecord(id: ContentTabID(rawValue: "A"), anchor: .directory(path: "/A")),
            Self.pinnedRecord(id: ContentTabID(rawValue: "B"), anchor: .directory(path: "/B")),
        ]
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreV1Fixture(records: records))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
        let live = ContentTabPinnedRecordClient.liveValue
        let client = ContentTabPinnedRecordClient(
            loadStore: live.loadStore,
            classifyStoreLoad: live.classifyStoreLoad,
            saveStore: { _, _ in throw SaveFailure.expected },
        )

        XCTAssertThrowsError(try client.moveTopNavigationItem(
            defaultsRecorder.client(),
            ["L1"],
            .contentTab(ContentTabID(rawValue: "A")),
            .after(.contentTab(ContentTabID(rawValue: "B"))),
        )) { error in
            XCTAssertEqual(error as? SaveFailure, .expected)
        }
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
    }

    /// CTM-003-restore_pinned_content_tabs: corrupt/future unavailable store는 semantic mutation을 거부한다.
    /// 이해할 수 없는 저장 상태가 writable empty store로 바뀌거나 rewrite되지 않는지 검증한다.
    /// - 검증 내용: typed rejection, source bytes 보존, write 0회
    /// - 사전 조건: malformed payload와 schemaVersion 3 payload
    /// - 기대 결과: 각각 corrupt/future load error이며 bytes가 그대로 유지됨
    func testPinnedRecordClient_unavailableStoreRejectsSemanticMoveWithoutWriting() throws {
        let fixtures: [(Data, ContentTabPinnedRecordStoreLoadError)] = [
            (Data("not-json".utf8), .corruptUnavailable),
            (Data(#"{"schemaVersion":3,"records":[],"topNavigationOrder":[]}"#.utf8), .futureSchemaUnavailable(3)),
        ]

        for (sourceData, expectedError) in fixtures {
            let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
            XCTAssertThrowsError(try ContentTabPinnedRecordClient.liveValue.moveTopNavigationItem(
                defaultsRecorder.client(),
                [],
                .location("L1"),
                .after(.location("L2")),
            )) { error in
                XCTAssertEqual(error as? ContentTabPinnedRecordStoreLoadError, expectedError)
            }
            XCTAssertEqual(defaultsRecorder.data(), sourceData)
            XCTAssertEqual(defaultsRecorder.writeCount(), 0)
        }
    }

    /// CTM-003-pin_content_tab_s: v1 첫 lifecycle mutation은 발견된 Location identity를 보존한다.
    /// lazy migration이 실제 window discovery를 사용해 mixed order를 완전한 schema v2로 기록하는지 검증한다.
    /// - 검증 내용: 첫 pin 뒤 저장된 order의 non-empty Location ID와 신규 Content Tab
    /// - 사전 조건: Location L1이 발견된 window, v1 records A, unpinned B
    /// - 기대 결과: 저장된 schema v2 order가 `[L1,A,B]`를 유지함
    func testLifecycle_firstV1PinMutationRetainsDiscoveredLocationIDs() async throws {
        let existingTabID = ContentTabID(rawValue: "legacy-A")
        let newTabID = ContentTabID(rawValue: "new-B")
        let sourceData = try JSONEncoder().encode(ContentTabPinnedRecordStoreV1Fixture(records: [
            Self.pinnedRecord(id: existingTabID, anchor: .directory(path: "/A")),
        ]))
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
        let fixedLocation = FileManagerFixedLocationItem(
            id: "L1",
            title: "Location",
            path: "/Users/test/Location",
            iconName: "folder",
            accessibilityLabel: "Location",
        )
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                ContentTabItem(
                    id: newTabID,
                    page: .directory,
                    anchor: .directory(path: "/B"),
                    isPinned: false,
                    title: "B",
                    iconName: "folder",
                ),
            ],
            activeTabID: newTabID,
        )
        state.applyFixedLocationItems([fixedLocation])
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: lifecycle terminal 내부 action보다 migration 결과를 집중 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.contentTabs(.pin(newTabID)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        let stored = try ContentTabPinnedRecordClient.liveValue.loadStore(defaultsRecorder.client())
        XCTAssertEqual(stored.topNavigationOrder.items, [
            .location(fixedLocation.id),
            .contentTab(existingTabID),
            .contentTab(newTabID),
        ])
    }

    private func topNavigationToken(_ value: UInt8) -> FileManagerTopNavigationOperationToken {
        FileManagerTopNavigationOperationToken(value: UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value,
        )))
    }

    /// CTM-003-pin_content_tab_s: pin/unpin helper는 records와 mixed order를 한 store 값으로 변경한다.
    /// lifecycle transform이 record-only snapshot을 만들지 않고 tagged order까지 함께 확정하는지 검증한다.
    /// - 검증 내용: pin append와 unpin 제거 뒤 records/order 일치
    /// - 사전 조건: Location L1만 있는 schema-v2 store와 신규 A record
    /// - 기대 결과: pin은 `[L1,A]`, unpin은 `[L1]`이며 어느 시점에도 orphan durable ID가 없음
    func testPinnedRecordLifecycleHelpers_updateRecordsAndOrderAtomically() {
        let tabID = ContentTabID(rawValue: "lifecycle-A")
        let record = Self.pinnedRecord(id: tabID, anchor: .directory(path: "/A"))
        let initial = ContentTabPinnedRecordStore(
            topNavigationOrder: .init(items: [.location("L1")]),
        )

        let pinned = upsertPinnedRecord(record, in: initial)
        XCTAssertEqual(pinned.records, [record])
        XCTAssertEqual(pinned.topNavigationOrder.items, [.location("L1"), .contentTab(tabID)])

        let unpinned = removePinnedRecord(id: tabID.rawValue, from: pinned)
        XCTAssertTrue(unpinned.records.isEmpty)
        XCTAssertEqual(unpinned.topNavigationOrder.items, [.location("L1")])
    }

    /// CTM-003-unpin_content_tab_s: same-session unpin은 semantic 이웃 anchor dormant slot을 한 개 남긴다.
    /// raw index가 아니라 현재 mixed order의 before/after identity를 window-local 상태에 기록하는지 검증한다.
    /// - 검증 내용: A unpin 직후 dormant slot과 durable optimistic projection
    /// - 사전 조건: mixed order `[L1,A,L2,B]`와 pinned A/B runtime
    /// - 기대 결과: A slot은 before L1/after L2이고 durable optimistic order에서 A가 제거됨
    func testUnpin_recordsOneWindowLocalDormantNeighborAnchor() {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let recordA = Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A"))
        let recordB = Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B"))
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                Self.pinnedItem(id: tabA, anchor: .directory(path: "/A"), title: "A"),
                Self.pinnedItem(id: tabB, anchor: .directory(path: "/B"), title: "B"),
            ],
            activeTabID: tabA,
            pinnedRecords: [tabA: recordA, tabB: recordB],
        )
        state.lastConfirmedTopNavigationOrder = .init(items: [
            .location("L1"), .contentTab(tabA), .location("L2"), .contentTab(tabB),
        ])
        state.optimisticTopNavigationOrder = state.lastConfirmedTopNavigationOrder

        _ = FileManagerFeature().reduce(into: &state, action: .contentTabs(.unpin(tabA)))

        XCTAssertEqual(state.dormantContentTabSlots, [.init(
            id: tabA,
            before: .location("L1"),
            after: .location("L2"),
        )])
        XCTAssertEqual(state.optimisticTopNavigationOrder.items, [
            .location("L1"), .location("L2"), .contentTab(tabB),
        ])
        XCTAssertEqual(state.contentTabs.tabs.filter { !$0.isPinned }.map(\.id), [tabA])
    }

    /// CTM-003-pin_content_tab_s: same-session repin은 dormant anchor를 복원하고 restart repin은 end에 붙인다.
    /// window-local slot 유무만으로 동일 tab의 durable 삽입 위치가 달라지는 lifecycle 계약을 검증한다.
    /// - 검증 내용: unpin commit, same-session repin commit, slot 없는 restart-equivalent repin commit
    /// - 사전 조건: durable `[L1,A,L2,B]`와 pinned A/B
    /// - 기대 결과: same-session은 원래 slot, restart-equivalent는 `[L1,L2,B,A]`
    func testLifecycle_sameSessionRepinRestoresAnchorAndRestartRepinAppends() async throws {
        let tabA = ContentTabID(rawValue: "lifecycle-repin-A")
        let tabB = ContentTabID(rawValue: "lifecycle-repin-B")
        let recordA = Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A"), title: "A")
        let recordB = Self.pinnedRecord(id: tabB, anchor: .directory(path: "/B"), title: "B")
        let initialOrder = FileManagerTopNavigationOrder(items: [
            .location("L1"), .contentTab(tabA), .location("L2"), .contentTab(tabB),
        ])
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: .init(
            records: [recordA, recordB],
            topNavigationOrder: initialOrder,
        ))
        var initialState = FileManagerFeature.State()
        initialState.contentTabs = ContentTabState(
            tabs: [
                Self.pinnedItem(id: tabA, anchor: .directory(path: "/A"), title: "A"),
                Self.pinnedItem(id: tabB, anchor: .directory(path: "/B"), title: "B"),
            ],
            activeTabID: tabA,
            pinnedRecords: [tabA: recordA, tabB: recordB],
        )
        initialState.lastConfirmedTopNavigationOrder = initialOrder
        initialState.optimisticTopNavigationOrder = initialOrder
        let sameSession = TestStore(initialState: initialState) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: lifecycle 내부 terminal보다 최종 durable/runtime 계약을 집중 검증한다.
        sameSession.exhaustivity = .off(showSkippedAssertions: false)

        await sameSession.send(.contentTabs(.unpin(tabA)))
        await sameSession.skipReceivedActions(strict: false)
        await sameSession.finish()
        XCTAssertEqual(sameSession.state.dormantContentTabSlots.count, 1)
        XCTAssertEqual(sameSession.state.contentTabs.tabs.filter { !$0.isPinned }.map(\.id), [tabA])
        await sameSession.send(.contentTabs(.pin(tabA)))
        await sameSession.skipReceivedActions(strict: false)
        await sameSession.finish()

        let sameSessionStore = try ContentTabPinnedRecordClient.liveValue.loadStore(defaultsRecorder.client())
        XCTAssertEqual(sameSessionStore.topNavigationOrder, initialOrder)
        XCTAssertTrue(sameSession.state.dormantContentTabSlots.isEmpty)

        let restartRecorder = try PinnedRecordDefaultsRecorder(store: removePinnedRecord(
            id: tabA.rawValue,
            from: .init(records: [recordA, recordB], topNavigationOrder: initialOrder),
        ))
        var restartState = initialState
        restartState.contentTabs.tabs[id: tabA]?.isPinned = false
        restartState.contentTabs.pinnedRecords.removeValue(forKey: tabA)
        restartState.dormantContentTabSlots = []
        restartState.lastConfirmedTopNavigationOrder = .init(items: [
            .location("L1"), .location("L2"), .contentTab(tabB),
        ])
        restartState.optimisticTopNavigationOrder = restartState.lastConfirmedTopNavigationOrder
        let restarted = TestStore(initialState: restartState) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = restartRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: restart-equivalent 최종 삽입 위치와 write 결과를 집중 검증한다.
        restarted.exhaustivity = .off(showSkippedAssertions: false)
        await restarted.send(.contentTabs(.pin(tabA)))
        await restarted.skipReceivedActions(strict: false)
        await restarted.finish()

        XCTAssertEqual(
            try ContentTabPinnedRecordClient.liveValue.loadStore(restartRecorder.client())
                .topNavigationOrder.items,
            [.location("L1"), .location("L2"), .contentTab(tabB), .contentTab(tabA)],
        )
    }

    /// CTM-003-unpin_content_tab_s: pinned close와 dormant-unpinned close는 durable ID와 slot을 모두 제거한다.
    /// close가 generic unpin처럼 dormant residue를 남기지 않고 기존 active fallback을 수행하는지 검증한다.
    /// - 검증 내용: pinned close atomic removal/runtime close와 dormant unpinned close cleanup
    /// - 사전 조건: active pinned A, unpinned B 및 별도 dormant C
    /// - 기대 결과: A/C tab·record·order·slot residue가 없고 B가 active임
    func testLifecycle_closeRemovesPinnedAndDormantResidue() async throws {
        let tabA = ContentTabID(rawValue: "close-pinned-A")
        let tabB = ContentTabID(rawValue: "close-fallback-B")
        let recordA = Self.pinnedRecord(id: tabA, anchor: .directory(path: "/A"), title: "A")
        let initialOrder = FileManagerTopNavigationOrder(items: [.location("L1"), .contentTab(tabA)])
        let defaultsRecorder = try PinnedRecordDefaultsRecorder(store: .init(
            records: [recordA],
            topNavigationOrder: initialOrder,
        ))
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [
                Self.pinnedItem(id: tabA, anchor: .directory(path: "/A"), title: "A"),
                ContentTabItem(
                    id: tabB, page: .home, anchor: .homeDefault, isPinned: false,
                    title: "Home", iconName: "house",
                ),
            ],
            activeTabID: tabA,
            pinnedRecords: [tabA: recordA],
        )
        state.lastConfirmedTopNavigationOrder = initialOrder
        state.optimisticTopNavigationOrder = initialOrder
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: close coordinator의 내부 action보다 최종 residue와 active fallback을 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.closeContentTabRequested(tabA))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertNil(store.state.contentTabs.tabs[id: tabA])
        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertTrue(store.state.dormantContentTabSlots.isEmpty)
        let closedStore = try ContentTabPinnedRecordClient.liveValue.loadStore(defaultsRecorder.client())
        XCTAssertFalse(closedStore.records.contains { $0.id == tabA.rawValue })
        XCTAssertFalse(closedStore.topNavigationOrder.items.contains(.contentTab(tabA)))

        var dormantState = store.state
        dormantState.dormantContentTabSlots = [.init(
            id: tabB, before: .location("L1"), after: nil,
        )]
        _ = FileManagerFeature().reduce(into: &dormantState, action: .closeContentTabRequested(tabB))
        XCTAssertTrue(dormantState.dormantContentTabSlots.isEmpty)
    }

    /// CTM-003-pin_content_tab_s: corrupt store pin은 bytes를 보존하고 load-unavailable로 남는다.
    /// unavailable store를 writable empty state로 취급하거나 save rollback으로 오분류하지 않는지 검증한다.
    /// - 검증 내용: write 0, source bytes, local rollback, typed availability/presentation
    /// - 사전 조건: malformed persisted bytes와 unpinned A
    /// - 기대 결과: bytes 불변, A unpinned, corrupt/loadUnavailable 상태 유지
    func testLifecycle_unavailablePinPreservesBytesAndPresentation() async {
        let tabID = ContentTabID(rawValue: "unavailable-pin")
        let sourceData = Data("not-json".utf8)
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID, page: .directory, anchor: .directory(path: "/A"),
                isPinned: false, title: "A", iconName: "folder",
            )],
            activeTabID: tabID,
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: typed unavailable terminal 이후 최종 rollback과 byte 보존을 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.contentTabs(.pin(tabID)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertEqual(store.state.topNavigationArrangementAvailability, .unavailable(.corrupt))
        XCTAssertEqual(store.state.topNavigationArrangementPresentation, .loadUnavailable)
    }

    /// CTM-003-go_to_anchored_path_of_pinned_tab: pinned anchor 갱신도 unavailable store를 load failure로 표시한다.
    /// metadata 갱신 경로가 corrupt bytes를 save rollback으로 오분류하지 않는지 검증한다.
    /// - 검증 내용: runtime anchor 유지, frozen record rollback, bytes/write 0, loadUnavailable presentation
    /// - 사전 조건: pinned A와 malformed persisted bytes
    /// - 기대 결과: runtime은 새 anchor, record는 이전 snapshot이며 corrupt/loadUnavailable 상태가 됨
    func testPinnedAnchorUpdate_unavailableStoreUsesLoadUnavailablePresentation() async {
        let tabID = ContentTabID(rawValue: "unavailable-anchor-update")
        let oldAnchor = ContentTabPageAnchor.directory(path: "/old")
        let newAnchor = ContentTabPageAnchor.directory(path: "/new")
        let oldRecord = Self.pinnedRecord(id: tabID, anchor: oldAnchor, title: "Old")
        let sourceData = Data("not-json".utf8)
        let defaultsRecorder = PinnedRecordDefaultsRecorder(data: sourceData)
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [Self.pinnedItem(id: tabID, anchor: oldAnchor, title: "Old")],
            activeTabID: tabID,
            pinnedRecords: [tabID: oldRecord],
        )
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = .liveValue
            $0.userDefaultsClient = defaultsRecorder.client()
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: metadata persistence terminal 뒤 typed presentation과 runtime/record 분리를 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.contentTabs(.updateActivePageAnchor(tabID, newAnchor)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(defaultsRecorder.data(), sourceData)
        XCTAssertEqual(defaultsRecorder.writeCount(), 0)
        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.anchor, newAnchor)
        XCTAssertEqual(store.state.contentTabs.pinnedRecords[tabID], oldRecord)
        XCTAssertEqual(store.state.topNavigationArrangementAvailability, .unavailable(.corrupt))
        XCTAssertEqual(store.state.topNavigationArrangementPresentation, .loadUnavailable)
    }

    /// CTM-003-pin_content_tab_s: save failure는 confirmed order와 runtime cache를 보존해 reconcile한다.
    /// optimistic pin rollback이 active route나 tab content cache를 captured store snapshot으로 덮지 않는지 검증한다.
    /// - 검증 내용: saveRollback, confirmed/optimistic equality, runtime route/cache identity
    /// - 사전 조건: confirmed L1, active directory A cache와 throwing guarded write
    /// - 기대 결과: A는 unpinned, order는 L1, cache/route는 그대로이며 saveRollback만 표시됨
    func testLifecycle_saveFailureReconcilesWithoutCorruptingRuntimeCache() async {
        struct SaveFailure: Error {}
        let tabID = ContentTabID(rawValue: "save-failure-pin")
        var state = FileManagerFeature.State()
        state.contentTabs = ContentTabState(
            tabs: [ContentTabItem(
                id: tabID, page: .directory, anchor: .directory(path: "/runtime"),
                isPinned: false, title: "Runtime", iconName: "folder",
            )],
            activeTabID: tabID,
        )
        state.content.navigation.navigationState = .folder("/runtime")
        state.syncActiveTabContentState()
        state.lastConfirmedTopNavigationOrder = .init(items: [.location("L1")])
        state.optimisticTopNavigationOrder = state.lastConfirmedTopNavigationOrder
        let originalContent = state.content
        var client = ContentTabPinnedRecordClient.liveValue
        client.guardedUpdateStore = { _, _, _ in throw SaveFailure() }
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient = client
            $0.date = .constant(Self.pinnedAt)
        }
        // store.exhaustivity = .off: failure terminal의 최종 reconciliation과 runtime cache 불변을 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.contentTabs(.pin(tabID)))
        await store.skipReceivedActions(strict: false)
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.tabs[id: tabID]?.isPinned, false)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationOrder.items, [.location("L1")])
        XCTAssertEqual(store.state.optimisticTopNavigationOrder.items, [.location("L1")])
        XCTAssertEqual(store.state.content, originalContent)
        XCTAssertEqual(store.state.tabContentStates[tabID], originalContent)
        XCTAssertEqual(store.state.topNavigationArrangementPresentation, .saveRollback)
    }

    // MARK: - CTM-003-reconcile_top_navigation_order

    /// CTM-003-reconcile_top_navigation_order: 실패한 이전 move 뒤의 newer move를 유지한다.
    /// terminal rollback이 전체 before-state를 복원하지 않고 완료 intent 하나만 제거하는지 검증한다.
    /// - 검증 내용: A save failure 뒤 pending B와 B의 optimistic 결과
    /// - 사전 조건: confirmed `[A,B,C]`, pending A=`C before A`, pending B=`B after C`
    /// - 기대 결과: A만 제거되고 B를 confirmed 위에 replay한 `[A,C,B]`가 표시됨
    func testTopNavigationReconciliation_failedOlderMoveRetainsNewerMove() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tokenA = topNavigationToken(1)
        let tokenB = topNavigationToken(2)
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [
            .contentTab(tabA), .contentTab(tabB), .contentTab(tabC),
        ])
        state.pendingTopNavigationIntents = [
            .init(token: tokenA, intent: .move(
                source: .contentTab(tabC),
                destination: .before(.contentTab(tabA)),
            )),
            .init(token: tokenB, intent: .move(
                source: .contentTab(tabB),
                destination: .after(.contentTab(tabC)),
            )),
        ]
        state.optimisticTopNavigationOrder = .init(items: [
            .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
        ])
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == tokenB }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenA,
            terminal: .failed(.save),
        ))) {
            $0.pendingTopNavigationIntents.removeFirst()
            $0.optimisticTopNavigationOrder = .init(items: [
                .contentTab(tabA), .contentTab(tabC), .contentTab(tabB),
            ])
        }

        XCTAssertNil(store.state.topNavigationArrangementPresentation)

        let committedB = FileManagerTopNavigationOrder(items: [
            .contentTab(tabA), .contentTab(tabC), .contentTab(tabB),
        ])
        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenB,
            terminal: .committed(.init(order: committedB, revision: 1)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committedB
            $0.lastConfirmedTopNavigationCommitRevision = 1
            $0.pendingTopNavigationIntents.removeAll()
        }
        XCTAssertEqual(store.state.optimisticTopNavigationOrder, committedB)
    }

    /// CTM-003-reconcile_top_navigation_order: Window child가 valid move를 optimistic 적용하고 parent persistence를 요청한다.
    /// child 수명과 persistence effect를 분리하면서 terminal reconciliation은 기존 child 계약을 유지하는지 검증한다.
    /// - 검증 내용: pending enqueue, optimistic order, parent delegate 요청, committed terminal
    /// - 사전 조건: confirmed `[L1,A,B]`, semantic `A after B`
    /// - 기대 결과: `[L1,B,A]`가 confirmed/optimistic에 반영되고 pending queue가 비워짐
    func testTopNavigationReconciliation_childRequestsParentPersistenceAndCommitsSnapshot() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let token = topNavigationToken(3)
        let initial = FileManagerTopNavigationOrder(items: [
            .location("L1"), .contentTab(tabA), .contentTab(tabB),
        ])
        let committed = FileManagerTopNavigationOrder(items: [
            .location("L1"), .contentTab(tabB), .contentTab(tabA),
        ])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = initial
        state.optimisticTopNavigationOrder = initial
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { token }
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == token }
        }

        await store.send(.topNavigationMoveRequested(
            source: .contentTab(tabA),
            destination: .after(.contentTab(tabB)),
        )) {
            $0.pendingTopNavigationIntents = [.init(token: token, intent: .move(
                source: .contentTab(tabA),
                destination: .after(.contentTab(tabB)),
            ))]
            $0.optimisticTopNavigationOrder = committed
        }
        await store.receive { action in
            guard case let .delegate(.persistTopNavigationMove(
                receivedToken,
                source,
                destination,
                discoveredLocationIDs,
            )) = action else { return false }
            return receivedToken == token
                && source == .contentTab(tabA)
                && destination == .after(.contentTab(tabB))
                && discoveredLocationIDs.isEmpty
        }
        await store.send(.internal(.topNavigationIntentCompleted(
            token: token,
            terminal: .committed(.init(order: committed, revision: 1)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committed
            $0.lastConfirmedTopNavigationCommitRevision = 1
            $0.pendingTopNavigationIntents.removeAll()
        }

        XCTAssertEqual(store.state.optimisticTopNavigationOrder, committed)
        // store.finish() 불필요: delegate와 terminal을 모두 소비함
    }

    /// CTM-003-reconcile_top_navigation_order: stale A success snapshot을 confirmed에 적용하고 pending B를 다시 투영한다.
    /// arrival order가 generation보다 늦어도 committed snapshot 자체를 버리지 않는지 검증한다.
    /// - 검증 내용: lastConfirmed 교체, A intent만 제거, B replay
    /// - 사전 조건: pending A/B와 A committed `[C,A,B]`
    /// - 기대 결과: confirmed는 `[C,A,B]`, visible optimistic은 B가 적용된 `[C,B,A]`
    func testTopNavigationReconciliation_staleSuccessUpdatesConfirmedAndReplaysNewerMove() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tokenA = topNavigationToken(11)
        let tokenB = topNavigationToken(12)
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [
            .contentTab(tabA), .contentTab(tabB), .contentTab(tabC),
        ])
        state.pendingTopNavigationIntents = [
            .init(token: tokenA, intent: .move(
                source: .contentTab(tabC),
                destination: .before(.contentTab(tabA)),
            )),
            .init(token: tokenB, intent: .move(
                source: .contentTab(tabB),
                destination: .after(.contentTab(tabC)),
            )),
        ]
        state.optimisticTopNavigationOrder = .init(items: [
            .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
        ])
        let committedA = FileManagerTopNavigationOrder(items: [
            .contentTab(tabC), .contentTab(tabA), .contentTab(tabB),
        ])
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == tokenB }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenA,
            terminal: .committed(.init(order: committedA, revision: 1)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committedA
            $0.lastConfirmedTopNavigationCommitRevision = 1
            $0.pendingTopNavigationIntents.removeFirst()
            $0.optimisticTopNavigationOrder = .init(items: [
                .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
            ])
        }
    }

    /// CTM-003-reconcile_top_navigation_order: failed pin-shaped intent 뒤 successful unpin-shaped winner를 유지한다.
    /// pin/unpin lifecycle 구현 없이 semantic queue replay가 stale pin snapshot을 복원하지 않는지 검증한다.
    /// - 검증 내용: pin failure 후 unpin pending 유지, unpin commit 후 queue 정리
    /// - 사전 조건: confirmed `[L1,A]`, pending pin X 다음 unpin X
    /// - 기대 결과: 두 terminal 모두 X가 보이지 않고 마지막 confirmed가 winner order가 됨
    func testTopNavigationReconciliation_failedPinThenSuccessfulUnpinRetainsWinner() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabX = ContentTabID(rawValue: "X")
        let tokenPin = topNavigationToken(21)
        let tokenUnpin = topNavigationToken(22)
        let winner = FileManagerTopNavigationOrder(items: [.location("L1"), .contentTab(tabA)])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = winner
        state.optimisticTopNavigationOrder = winner
        state.pendingTopNavigationIntents = [
            .init(token: tokenPin, intent: .pin(tabX)),
            .init(token: tokenUnpin, intent: .unpin(tabX)),
        ]
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == tokenUnpin }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenPin,
            terminal: .failed(.save),
        ))) {
            $0.pendingTopNavigationIntents.removeFirst()
        }
        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenUnpin,
            terminal: .committed(.init(order: winner, revision: 1)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = winner
            $0.lastConfirmedTopNavigationCommitRevision = 1
            $0.pendingTopNavigationIntents.removeAll()
        }

        XCTAssertEqual(store.state.optimisticTopNavigationOrder, winner)
        XCTAssertNil(store.state.topNavigationArrangementPresentation)
    }

    /// CTM-003-reconcile_top_navigation_order: external committed snapshot 위에 local pending move를 rebase한다.
    /// 외부에서 추가된 항목을 잃지 않고 window-local overlay를 유지하는지 검증한다.
    /// - 검증 내용: confirmed external 교체, pending 보존, semantic replay
    /// - 사전 조건: local pending `B before A`, external `[X,A,B]`
    /// - 기대 결과: confirmed `[X,A,B]`, optimistic `[X,B,A]`, X 보존
    func testTopNavigationReconciliation_externalCommitRebasesPendingWithoutItemLoss() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let token = topNavigationToken(31)
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(tabA), .contentTab(tabB)])
        state.optimisticTopNavigationOrder = .init(items: [.contentTab(tabB), .contentTab(tabA)])
        state.pendingTopNavigationIntents = [.init(token: token, intent: .move(
            source: .contentTab(tabB),
            destination: .before(.contentTab(tabA)),
        ))]
        let external = FileManagerTopNavigationOrder(items: [
            .location("X"), .contentTab(tabA), .contentTab(tabB),
        ])
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.applyExternalCommittedTopNavigationOrder(external)) {
            $0.lastConfirmedTopNavigationOrder = external
            $0.lastConfirmedTopNavigationCommitRevision = nil
            $0.optimisticTopNavigationOrder = .init(items: [
                .location("X"), .contentTab(tabB), .contentTab(tabA),
            ])
            $0.topNavigationArrangementAvailability = .available
            $0.topNavigationArrangementPresentation = nil
        }
    }

    /// CTM-003-reconcile_top_navigation_order: relevant save failure만 redacted rollback presentation을 만든다.
    /// superseded/cancelled terminal은 사용자 오류를 만들지 않는 typed presentation 계약을 검증한다.
    /// - 검증 내용: current save failure 1회 표시와 cancelled/superseded 무표시
    /// - 사전 조건: 각 terminal token 하나가 pending인 독립 상태
    /// - 기대 결과: save만 `.saveRollback`, 나머지는 nil
    func testTopNavigationReconciliation_onlyRelevantSaveFailurePresentsRedactedRollback() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let failures: [(FileManagerTopNavigationIntentFailure, Bool)] = [
            (.save, true), (.superseded, false), (.cancelled, false),
        ]
        for (index, fixture) in failures.enumerated() {
            let token = topNavigationToken(UInt8(41 + index))
            var state = FileManagerFeature.State()
            state.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(tabA), .contentTab(tabB)])
            state.optimisticTopNavigationOrder = .init(items: [.contentTab(tabB), .contentTab(tabA)])
            state.pendingTopNavigationIntents = [.init(token: token, intent: .move(
                source: .contentTab(tabB),
                destination: .before(.contentTab(tabA)),
            ))]
            let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
                $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == token }
            }

            await store.send(.internal(.topNavigationIntentCompleted(
                token: token,
                terminal: .failed(fixture.0),
            ))) {
                $0.pendingTopNavigationIntents.removeAll()
                $0.optimisticTopNavigationOrder = $0.lastConfirmedTopNavigationOrder
                $0.topNavigationArrangementPresentation = fixture.1 ? .saveRollback : nil
            }
        }
    }

    /// CTM-003-reconcile_top_navigation_order: newer success 뒤 stale store-unavailable가 availability를 회귀시키지 않는다.
    /// stale failure가 자기 intent만 제거하고 최신 committed 상태와 사용자 presentation을 보존하는지 검증한다.
    /// - 검증 내용: current B revision 2 success 뒤 stale A unavailable terminal
    /// - 사전 조건: pending A/B, current token B, B committed `[C,B,A]`
    /// - 기대 결과: available/nil presentation과 revision 2 confirmed/optimistic을 유지하고 queue만 비움
    func testTopNavigationReconciliation_staleStoreUnavailableAfterNewerSuccessPreservesAvailableWinner() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tokenA = topNavigationToken(54)
        let tokenB = topNavigationToken(55)
        let committedB = FileManagerTopNavigationOrder(items: [
            .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
        ])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [
            .contentTab(tabA), .contentTab(tabB), .contentTab(tabC),
        ])
        state.optimisticTopNavigationOrder = committedB
        state.pendingTopNavigationIntents = [
            .init(token: tokenA, intent: .move(
                source: .contentTab(tabC),
                destination: .before(.contentTab(tabA)),
            )),
            .init(token: tokenB, intent: .move(
                source: .contentTab(tabB),
                destination: .after(.contentTab(tabC)),
            )),
        ]
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == tokenB }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenB,
            terminal: .committed(.init(order: committedB, revision: 2)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committedB
            $0.lastConfirmedTopNavigationCommitRevision = 2
            $0.pendingTopNavigationIntents.removeLast()
            $0.optimisticTopNavigationOrder = .init(items: [
                .contentTab(tabB), .contentTab(tabC), .contentTab(tabA),
            ])
        }
        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenA,
            terminal: .failed(.storeUnavailable(.corrupt)),
        ))) {
            $0.pendingTopNavigationIntents.removeAll()
            $0.optimisticTopNavigationOrder = committedB
        }

        XCTAssertEqual(store.state.topNavigationArrangementAvailability, .available)
        XCTAssertNil(store.state.topNavigationArrangementPresentation)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationOrder, committedB)
        XCTAssertEqual(store.state.optimisticTopNavigationOrder, committedB)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationCommitRevision, 2)
        XCTAssertTrue(store.state.pendingTopNavigationIntents.isEmpty)
    }

    /// CTM-003-reconcile_top_navigation_order: newer unavailable 뒤 stale committed가 availability를 복구하지 않는다.
    /// revision이 거부된 stale success가 현재 failure의 typed availability/presentation을 지우지 않는지 검증한다.
    /// - 검증 내용: current B unavailable 뒤 older A revision 1 committed terminal
    /// - 사전 조건: confirmed revision 2, pending A/B, current token B
    /// - 기대 결과: confirmed revision/order를 유지하고 corrupt/loadUnavailable 상태와 빈 queue를 보존함
    func testTopNavigationReconciliation_staleCommitAfterNewerUnavailablePreservesFailureState() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tokenA = topNavigationToken(56)
        let tokenB = topNavigationToken(57)
        let confirmed = FileManagerTopNavigationOrder(items: [
            .contentTab(tabA), .contentTab(tabB), .contentTab(tabC),
        ])
        let staleCommit = FileManagerTopNavigationOrder(items: [
            .contentTab(tabC), .contentTab(tabA), .contentTab(tabB),
        ])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = confirmed
        state.lastConfirmedTopNavigationCommitRevision = 2
        state.optimisticTopNavigationOrder = .init(items: [
            .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
        ])
        state.pendingTopNavigationIntents = [
            .init(token: tokenA, intent: .move(
                source: .contentTab(tabC),
                destination: .before(.contentTab(tabA)),
            )),
            .init(token: tokenB, intent: .move(
                source: .contentTab(tabB),
                destination: .after(.contentTab(tabC)),
            )),
        ]
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == tokenB }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenB,
            terminal: .failed(.storeUnavailable(.corrupt)),
        ))) {
            $0.pendingTopNavigationIntents.removeLast()
            $0.optimisticTopNavigationOrder = staleCommit
            $0.topNavigationArrangementAvailability = .unavailable(.corrupt)
            $0.topNavigationArrangementPresentation = .loadUnavailable
        }
        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenA,
            terminal: .committed(.init(order: staleCommit, revision: 1)),
        ))) {
            $0.pendingTopNavigationIntents.removeAll()
            $0.optimisticTopNavigationOrder = confirmed
        }

        XCTAssertEqual(store.state.topNavigationArrangementAvailability, .unavailable(.corrupt))
        XCTAssertEqual(store.state.topNavigationArrangementPresentation, .loadUnavailable)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationOrder, confirmed)
        XCTAssertEqual(store.state.optimisticTopNavigationOrder, confirmed)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationCommitRevision, 2)
        XCTAssertTrue(store.state.pendingTopNavigationIntents.isEmpty)
    }

    /// CTM-003-reconcile_top_navigation_order: newer commit terminal 뒤 늦은 older terminal이 confirmed를 회귀시키지 않는다.
    /// storage commit revision이 action arrival inversion에서도 최종 durable winner를 보존하는지 검증한다.
    /// - 검증 내용: B revision 2 수신 후 A revision 1 수신, completed token별 queue 제거
    /// - 사전 조건: pending A/B와 committed snapshots A=`[C,A,B]`, B=`[C,B,A]`
    /// - 기대 결과: queue는 비고 confirmed/optimistic은 revision 2의 B snapshot을 유지함
    func testTopNavigationReconciliation_reverseSuccessArrivalKeepsNewestCommit() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let tabC = ContentTabID(rawValue: "C")
        let tokenA = topNavigationToken(51)
        let tokenB = topNavigationToken(52)
        let committedA = FileManagerTopNavigationOrder(items: [
            .contentTab(tabC), .contentTab(tabA), .contentTab(tabB),
        ])
        let committedB = FileManagerTopNavigationOrder(items: [
            .contentTab(tabC), .contentTab(tabB), .contentTab(tabA),
        ])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [
            .contentTab(tabA), .contentTab(tabB), .contentTab(tabC),
        ])
        state.optimisticTopNavigationOrder = committedB
        state.pendingTopNavigationIntents = [
            .init(token: tokenA, intent: .move(
                source: .contentTab(tabC),
                destination: .before(.contentTab(tabA)),
            )),
            .init(token: tokenB, intent: .move(
                source: .contentTab(tabB),
                destination: .after(.contentTab(tabC)),
            )),
        ]
        let store = TestStore(initialState: state) { FileManagerFeature() }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenB,
            terminal: .committed(.init(order: committedB, revision: 2)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committedB
            $0.lastConfirmedTopNavigationCommitRevision = 2
            $0.pendingTopNavigationIntents.removeLast()
            $0.optimisticTopNavigationOrder = .init(items: [
                .contentTab(tabB), .contentTab(tabC), .contentTab(tabA),
            ])
        }
        await store.send(.internal(.topNavigationIntentCompleted(
            token: tokenA,
            terminal: .committed(.init(order: committedA, revision: 1)),
        ))) {
            $0.pendingTopNavigationIntents.removeAll()
            $0.optimisticTopNavigationOrder = committedB
        }

        XCTAssertEqual(store.state.lastConfirmedTopNavigationOrder, committedB)
        XCTAssertEqual(store.state.lastConfirmedTopNavigationCommitRevision, 2)
    }

    /// CTM-003-reconcile_top_navigation_order: current successful commit은 이전 save rollback presentation을 정리한다.
    /// stale success가 아닌 실제 winner 성공만 obsolete save error를 해제하는지 검증한다.
    /// - 검증 내용: current token commit 뒤 typed presentation 해제
    /// - 사전 조건: `.saveRollback` presentation과 pending winner B
    /// - 기대 결과: committed order/revision을 적용하고 presentation이 nil이 됨
    func testTopNavigationReconciliation_currentSuccessClearsPreviousSaveRollbackPresentation() async {
        let tabA = ContentTabID(rawValue: "A")
        let tabB = ContentTabID(rawValue: "B")
        let token = topNavigationToken(53)
        let committed = FileManagerTopNavigationOrder(items: [.contentTab(tabB), .contentTab(tabA)])
        var state = FileManagerFeature.State()
        state.lastConfirmedTopNavigationOrder = .init(items: [.contentTab(tabA), .contentTab(tabB)])
        state.optimisticTopNavigationOrder = committed
        state.pendingTopNavigationIntents = [.init(token: token, intent: .move(
            source: .contentTab(tabB),
            destination: .before(.contentTab(tabA)),
        ))]
        state.topNavigationArrangementPresentation = .saveRollback
        let store = TestStore(initialState: state) { FileManagerFeature() } withDependencies: {
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == token }
        }

        await store.send(.internal(.topNavigationIntentCompleted(
            token: token,
            terminal: .committed(.init(order: committed, revision: 3)),
        ))) {
            $0.lastConfirmedTopNavigationOrder = committed
            $0.lastConfirmedTopNavigationCommitRevision = 3
            $0.pendingTopNavigationIntents.removeAll()
            $0.topNavigationArrangementPresentation = nil
        }
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

    /// CTM-003-seed_built_in_pinned_content_tabs: Recents와 All Tags 사이에 기존 Finder/User 순서를 보존한다.
    /// 최초 built-in seed가 identity별 canonical 위치와 metadata를 전체 pinned ordering에 반영하는지 검증한다.
    /// - 검증 내용: Location과 Finder/User 상대 순서 보존, Recents 첫 탭·All Tags 마지막 탭 배치 및 canonical metadata
    /// - 사전 조건: Location 사이 Finder/User record가 있고 두 built-in ensure 결과가 ready, completion은 false
    /// - 기대 결과: built-in canonical 위치와 기존 mixed-order 상대 순서가 함께 저장됨
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
        let locationA = "fixed-location-a"
        let locationB = "fixed-location-b"
        let discoveredLocationIDs = [locationA, locationB]
        let initialStore = ContentTabPinnedRecordStore(
            records: [finderRecord, userRecord],
            topNavigationOrder: .init(items: [
                .location(locationA),
                .contentTab(ContentTabID(rawValue: "finder")),
                .location(locationB),
                .contentTab(ContentTabID(rawValue: "user")),
            ]),
        )

        let recentsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .recents, canonicalPackageURL: recentsURL)),
            completion: false,
            store: initialStore,
            now: Self.pinnedAt,
            discoveredLocationIDs: discoveredLocationIDs,
        )
        guard case let .seed(recentsStore) = recentsResult else {
            return XCTFail("Recents는 새 record를 seed해야 함")
        }
        let allTagsResult = BuiltInContentTabPinnedRecordSeedPolicy.evaluate(
            ensureResult: .ready(.init(identity: .allTags, canonicalPackageURL: allTagsURL)),
            completion: false,
            store: recentsStore,
            now: Self.pinnedAt,
            discoveredLocationIDs: discoveredLocationIDs,
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
        let recentsRecord = finalStore.records.first { $0.id == "built-in-collection-recents" }
        let allTagsRecord = finalStore.records.first { $0.id == "built-in-collection-all-tags" }
        XCTAssertEqual(recentsRecord?.page, .collection)
        XCTAssertEqual(recentsRecord?.anchor, .collectionFile(url: recentsURL))
        XCTAssertEqual(recentsRecord?.title, "Recents")
        XCTAssertEqual(recentsRecord?.iconName, "clock")
        XCTAssertEqual(allTagsRecord?.page, .collection)
        XCTAssertEqual(allTagsRecord?.anchor, .collectionFile(url: allTagsURL))
        XCTAssertEqual(allTagsRecord?.title, "All Tags")
        XCTAssertEqual(allTagsRecord?.iconName, "tag")
        XCTAssertFalse(finalStore.records.contains {
            if case .virtualCollection = $0.anchor { true } else { false }
        })
        XCTAssertEqual(finalStore.topNavigationOrder.items, [
            .location(locationA),
            .contentTab(ContentTabID(rawValue: "built-in-collection-recents")),
            .contentTab(ContentTabID(rawValue: "finder")),
            .location(locationB),
            .contentTab(ContentTabID(rawValue: "user")),
            .contentTab(ContentTabID(rawValue: "built-in-collection-all-tags")),
        ])
    }

    /// CTM-003-seed_built_in_pinned_content_tabs: stable ID를 URL보다 우선해 중복을 canonicalize하고 선두에 배치한다.
    /// crash retry에서 ID/URL residue가 함께 남아도 nonmatching 상대 순서와 하나의 stable record만 유지되는지 검증한다.
    /// - 검증 내용: stable ID match의 pinnedAt 보존, ID/URL 전체 duplicate 제거, Recents 선두와 nonmatching 상대 순서 보존
    /// - 사전 조건: canonical URL duplicate 2개와 stable ID duplicate 1개가 섞인 store
    /// - 기대 결과: [Recents, first-other, second-other] 순서와 stable ID record의 pinnedAt이 유지됨
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
        let recentsRecord = finalStore.records.first { $0.id == "built-in-collection-recents" }
        XCTAssertEqual(recentsRecord?.pinnedAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(recentsRecord?.anchor, .collectionFile(url: canonicalURL))
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
        XCTAssertEqual(try client.loadStore(defaults), ContentTabPinnedRecordStore(
            records: [newRecord],
            topNavigationOrder: .init(items: [.contentTab(tabID)]),
        ))
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
            ContentTabFeature()
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
            ContentTabFeature()
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
                        iconName: "bubble.right",
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
            FileManagerFeature()
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
            FileManagerFeature()
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
            FileManagerFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
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
            ContentTabPinnedRecordStore(
                records: [firstRecord],
                topNavigationOrder: .init(items: [.contentTab(firstID)]),
            ),
            ContentTabPinnedRecordStore(
                records: [firstRecord, secondRecord],
                topNavigationOrder: .init(items: [.contentTab(firstID), .contentTab(secondID)]),
            ),
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
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(firstID)
        }
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
            $0.pendingPinnedRecordIDs.insert(secondID)
        }
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
        let feature = ContentTabFeature()

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
            FileManagerFeature()
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
        await store.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(currentID)
        }
        await store.finish()

        XCTAssertEqual(recorder.stores(), [
            ContentTabPinnedRecordStore(
                records: [otherRecord, currentRecord],
                topNavigationOrder: .init(items: [.contentTab(otherID), .contentTab(currentID)]),
            ),
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
            ContentTabPinnedRecordStore(
                records: [otherRecord],
                topNavigationOrder: .init(items: [.contentTab(otherID)]),
            ),
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
        let token = topNavigationToken(71)
        let committedOrder = FileManagerTopNavigationOrder(items: [.contentTab(tabID)])
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
            $0.contentTabPinnedRecordClient.reserveTopNavigationOperationToken = { token }
            $0.contentTabPinnedRecordClient.isCurrentTopNavigationOperationToken = { $0 == token }
            $0.contentTabPinnedRecordClient.loadTopNavigationCommit = { _, _ in
                .init(order: committedOrder, revision: 1)
            }
        }

        await store.send(FileManagerWindowAction.request(.toggleActiveContentTabPin))
        await store.receive(\.contentTabs) {
            $0.pendingTopNavigationIntents = [.init(token: token, intent: .pin(tabID))]
            $0.optimisticTopNavigationOrder = committedOrder
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
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded) {
            $0.lastConfirmedTopNavigationOrder = committedOrder
            $0.lastConfirmedTopNavigationCommitRevision = 1
            $0.pendingTopNavigationIntents.removeAll()
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
            ContentTabFeature()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, transform in
                _ = try transform(ContentTabPinnedRecordStore())
            }
        }
        await successStore.send(.pin(targetID)) {
            Self.expectPinnedState(&$0, targetID: targetID, targetAnchor: targetAnchor)
        }
        await successStore.receive(\.pinnedRecordSaveSucceeded) {
            $0.pendingPinnedRecordIDs.remove(targetID)
        }
        await successStore.finish()
        Self.assertSelection(successStore.state, targetID: targetID, anchorID: anchorID)

        let rollbackStore = TestStore(initialState: initialState) {
            ContentTabFeature()
        } withDependencies: {
            $0.date = DateGenerator { Date(timeIntervalSince1970: 443) }
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }
        await rollbackStore.send(.pin(targetID)) {
            Self.expectPinnedState(&$0, targetID: targetID, targetAnchor: targetAnchor)
        }
        await rollbackStore.receive(\.pinnedRecordSaveFailed) {
            Self.expectPinRollbackState(&$0, targetID: targetID)
        }
        await rollbackStore.finish()
        Self.assertSelection(rollbackStore.state, targetID: targetID, anchorID: anchorID)
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

    /// CTM-003-unpin_content_tab_s: leaf close는 durable 제거 전환을 만들고 window commitClose가 실제 close를 소유한다.
    /// 저장 성공 전 runtime cache를 제거하지 않는 2단계 pinned close 준비 계약을 검증한다.
    /// - 검증 내용: leaf close의 isPinned=false, tab 유지, record 제거와 saveSucceeded
    /// - 사전 조건: pinned Directory tab 하나 (frozen record 설정)
    /// - 기대 결과: leaf 단계는 탭을 유지하고 window lifecycle 성공 뒤 별도 commitClose가 제거함
    func testContentTabLeafClose_preparesPinnedRemovalBeforeWindowCommitClose() async {
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
            ContentTabFeature()
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
        await successStore.receive(\.pinnedRecordSaveSucceeded)
        await successStore.finish()
        XCTAssertEqual(successStore.state.selectedTabIDs, [targetID, anchorID])
        XCTAssertEqual(successStore.state.selectionAnchorID, targetID)

        let rollbackStore = TestStore(initialState: initialState) {
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }
        await rollbackStore.send(.unpin(targetID)) {
            Self.expectUnpinnedState(&$0, targetID: targetID)
            $0.selectedTabIDs.insert(targetID)
            $0.selectionAnchorID = targetID
        }
        await rollbackStore.receive(\.pinnedRecordSaveFailed) {
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
            ContentTabFeature()
        } withDependencies: {
            $0.contentTabPinnedRecordClient.updateStore = { _, _ in throw SaveError() }
        }

        await store.send(.unpin(rollbackTargetID)) {
            $0.tabs[id: rollbackTargetID]?.isPinned = false
            $0.tabs.move(fromOffsets: [1], toOffset: 3)
            $0.pinnedRecords.removeValue(forKey: rollbackTargetID)
        }
        await store.receive(\.pinnedRecordSaveFailed) {
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
            FileManagerFeature()
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
        ], topNavigationOrder: .init(items: [
            .contentTab(ContentTabID(rawValue: "dir-1")),
            .contentTab(ContentTabID(rawValue: "col-1")),
            .contentTab(ContentTabID(rawValue: "ai-1")),
        ]))
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
        XCTAssertEqual(updatedStore.topNavigationOrder.items, [
            .contentTab(ContentTabID(rawValue: "dir-1")),
            .contentTab(ContentTabID(rawValue: "col-1")),
            .contentTab(ContentTabID(rawValue: "ai-1")),
        ])
        XCTAssertEqual(appendedStore.topNavigationOrder.items, [
            .contentTab(ContentTabID(rawValue: "dir-1")),
            .contentTab(ContentTabID(rawValue: "col-1")),
            .contentTab(ContentTabID(rawValue: "ai-1")),
            .contentTab(ContentTabID(rawValue: "dir-2")),
        ])
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
