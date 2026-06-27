import ComposableArchitecture
import Foundation
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

@MainActor
final class CTM003ManagePinnedContentTabsTests: XCTestCase {
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
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.finish()
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
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.finish()
    }

    /// CTM-003-pin_content_tab_s: pin 시점 record snapshot은 이후 tab 변경과 다음 save에도 유지
    /// Pinned tab의 page/anchor/title/icon이 바뀐 뒤 다른 tab pin으로 저장이 다시 발생해도 최초 pinned record가 오염되지 않음을 검증한다.
    /// - 검증 내용: pin → active tab anchor 변경 → 다른 tab pin save 시 첫 record는 pin 시점 snapshot 유지
    /// - 사전 조건: unpinned Directory tab과 unpinned AI Chat tab
    /// - 기대 결과: 첫 record page/anchor/title/iconName/pinnedAt이 pin 시점 값으로 유지
    func testPin_recordSnapshotSurvivesTabNavigationAndLaterSave() async {
        let firstID = ContentTabID()
        let secondID = ContentTabID()
        let originalAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Documents")
        let changedAnchor: ContentTabPageAnchor = .aiChat(sessionID: "chat-1")
        let secondAnchor: ContentTabPageAnchor = .directory(path: "/Users/test/Downloads")
        let firstSnapshot = Self.pinnedRecord(
            id: firstID,
            anchor: originalAnchor,
            title: "Documents",
            iconName: "folder",
        )
        let secondSnapshot = Self.pinnedRecord(
            id: secondID,
            anchor: secondAnchor,
            title: "Downloads",
            iconName: "folder",
        )
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
                let savedStore = try transform(ContentTabPinnedRecordStore())
                if savedStore.records.count == 2 {
                    XCTAssertEqual(savedStore.records, [firstSnapshot, secondSnapshot])
                }
            }
        }

        await store.send(.pin(firstID)) {
            $0.tabs[id: firstID]?.isPinned = true
            $0.pinnedRecords[firstID] = firstSnapshot
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.send(.updateActivePageAnchor(firstID, changedAnchor)) {
            $0.tabs[id: firstID]?.page = .aiChat
            $0.tabs[id: firstID]?.anchor = changedAnchor
            $0.tabs[id: firstID]?.title = "AI Chat"
            $0.tabs[id: firstID]?.iconName = "sparkles"
        }
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondSnapshot
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
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
        }
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.tabs[id: tabID]?.isPinned = false
            $0.pinnedRecords.removeAll()
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
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
        }
        await store.receive(\.pinnedRecordSaveFailed) {
            $0.tabs[id: secondID]?.isPinned = false
            $0.pinnedRecords.removeValue(forKey: secondID)
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
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.send(.pin(secondID)) {
            $0.tabs[id: secondID]?.isPinned = true
            $0.pinnedRecords[secondID] = secondRecord
        }
        await store.receive(\.pinnedRecordSaveSucceeded)
        await store.finish()

        XCTAssertEqual(recorder.stores().map { $0.records.map(\.id).sorted() }, [
            [firstID.rawValue, secondID.rawValue].sorted(),
            [secondID.rawValue],
        ])
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
            $0.syncContentTabSidebarItems()
        }
        await store.receive(\.contentTabs.pinnedRecordSaveSucceeded)
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
}
