import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerPagesFileManager
import VoyagerShared
import XCTest

// MARK: - Home Chat History State/Effect Tests

/// Home 화면 Chat History section의 state/effect/routing을 검증한다.
/// - Task 4: Home Chat History state/effect/routing 구현
/// - Task 5에서 UI가 Chat History를 활용하는 것과 달리, 이 테스트는 reducer/dependency/routing 계층을 검증한다.
@MainActor
final class ContentHomeChatHistoryTests: XCTestCase {
    /// 테스트용 AiChatSessionSummary 목업을 생성한다.
    private func makeSummary(
        id: String = UUID().uuidString,
        title: String = "Test Session",
        preview: String? = nil,
        updatedAtMs: Int64 = 1_000_000,
    ) -> AiChatSessionSummary {
        AiChatSessionSummary(
            sessionID: AiChatSessionID(rawValue: UUID(uuidString: id) ?? UUID()),
            title: title,
            preview: preview,
            messageCount: 0,
            contextTitle: nil,
            searchText: nil,
            provider: nil,
            model: nil,
            createdAtMs: updatedAtMs,
            updatedAtMs: updatedAtMs,
            status: .completed,
        )
    }
}

// MARK: - Chat History Loading

@MainActor
extension ContentHomeChatHistoryTests {
    /// homeAppeared 시 listSessions가 limit=5로 호출되고 최대 5개 항목이 state에 저장됨
    /// - 검증 내용: listSessions에 limit=5 전달, homeChatHistoryItems.count == 5
    /// - 사전 조건: listSessions가 7개 summary 반환
    /// - 기대 결과: state.homeChatHistoryItems가 정확히 5개
    func testHomeLoadsMax5ChatSessions() async {
        let summaries = (0 ..< 7).map { i in
            makeSummary(
                id: UUID().uuidString,
                title: "Session \(i)",
                updatedAtMs: Int64(1_000_000 + i),
            )
        }

        let capturedLimit = LockIsolated<Int?>(nil)

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.listSessions = { limit, _ in
                capturedLimit.withValue { $0 = limit }
                return summaries
            }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in snapshot }
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerClient.urlsForDirectory = { _, _ in [URL(fileURLWithPath: "/tmp")] }
            $0.fileManagerClient.contentsOfDirectory = { _, _, _ in [] }
            $0.fileManagerClient.displayName = { _ in "/" }
            $0.homeAiChatClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.content(.view(.homeAppeared)))
        await store.receive { action in
            guard case let .content(.internal(.homeChatHistoryLoaded(items))) = action else {
                return false
            }
            return items.count == 5
        } assert: { state in
            state.content.homeChatHistoryItems = Array(summaries.prefix(5)).map { summary in
                FileManagerHomeChatHistoryItem(
                    sessionID: summary.sessionID.rawValue.uuidString,
                    title: summary.title,
                    detail: summary.preview,
                    updatedAtMs: summary.updatedAtMs,
                )
            }
            state.content.homeChatHistoryLoadFailed = false
        }

        XCTAssertEqual(capturedLimit.value, 5)
        XCTAssertEqual(store.state.content.homeChatHistoryItems.count, 5)
    }

    /// homeAppeared 시 chat history 로드 실패 → homeChatHistoryItems가 비어있고 homeChatHistoryLoadFailed가 true
    /// - 검증 내용: listSessions throw 후 items = [], loadFailed = true
    /// - 사전 조건: listSessions가 throw
    /// - 기대 결과: homeChatHistoryItems.isEmpty, homeChatHistoryLoadFailed == true, crash 없음
    func testHomeChatHistoryLoadFailureGraceful() async {
        struct TestError: Error, Equatable { let message: String }

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.listSessions = { _, _ in
                throw TestError(message: "db unavailable")
            }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in snapshot }
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerClient.urlsForDirectory = { _, _ in [URL(fileURLWithPath: "/tmp")] }
            $0.fileManagerClient.contentsOfDirectory = { _, _, _ in [] }
            $0.fileManagerClient.displayName = { _ in "/" }
            $0.homeAiChatClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.content(.view(.homeAppeared)))
        await store.receive { action in
            guard case .content(.internal(.homeChatHistoryLoadFailed)) = action else {
                return false
            }
            return true
        } assert: { state in
            state.content.homeChatHistoryItems = []
            state.content.homeChatHistoryLoadFailed = true
        }

        XCTAssertTrue(store.state.content.homeChatHistoryItems.isEmpty)
        XCTAssertTrue(store.state.content.homeChatHistoryLoadFailed)
    }
}

// MARK: - Chat History Tap Routing

@MainActor
extension ContentHomeChatHistoryTests {
    /// chatHistory tap이 createSession 없이 기존 session restore setup을 직접 실행함
    /// - 검증 내용: .chatHistory(sessionID) tap → .homeChatHistorySessionSelected → AiChat setup(restoreSessionID,
    /// sessionID=nil)
    ///   - createSession이 호출되지 않음
    ///   - aiChatSessionPersistenceClient.loadSession이 기존 sessionID로 호출됨
    /// - 사전 조건: 기본 FileManagerFeature state
    /// - 기대 결과: contentTabs anchor가 .aiChat(sessionID:)으로 변경되고 저장된 session restore effect가 실행됨
    func testHomeChatHistoryTapRestoresSession() async throws {
        let sessionUUID = UUID()
        let sessionID = AiChatSessionID(rawValue: sessionUUID)
        let createSessionCallCount = LockIsolated(0)
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.homeAiChatClient.createSession = {
                createSessionCallCount.withValue { $0 += 1 }
                return .selected("should-not-be-called")
            }
            $0.aiChatSessionPersistenceClient.listSessions = { _, _ in [] }
            $0.aiChatSessionPersistenceClient.loadSession = { requestedSessionID in
                loadedSessionIDs.withValue { $0.append(requestedSessionID) }
                return AiChatSessionSnapshot(
                    sessionID: requestedSessionID,
                    status: .active,
                    customTitle: "Existing session title",
                    provider: nil,
                    model: nil,
                    updatedAtMs: 1_234_567_890,
                )
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in snapshot }
            $0.aiChatSessionPersistenceClient.deleteSession = { _ in }
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.fileManagerClient.urlsForDirectory = { _, _ in [URL(fileURLWithPath: "/tmp")] }
            $0.fileManagerClient.contentsOfDirectory = { _, _, _ in [] }
            $0.fileManagerClient.displayName = { _ in "/" }
        }
        store.exhaustivity = .off

        await store.send(.content(.view(.homeSelectionTapped(.chatHistory(sessionID)))))
        await store.receive { action in
            guard case let .content(.delegate(.homeChatHistorySessionSelected(receivedSessionID))) = action else {
                return false
            }
            return receivedSessionID == sessionID
        }

        let activeTabID = try XCTUnwrap(store.state.contentTabs.activeTabID)
        await store.receive { action in
            guard case let .contentTabs(.updateActivePageAnchor(receivedTabID, .aiChat(receivedSessionID))) = action
            else {
                return false
            }
            return receivedTabID == activeTabID && receivedSessionID == sessionUUID.uuidString
        } assert: { state in
            state.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(sessionID: sessionUUID.uuidString)
            state.contentTabs.tabs[id: activeTabID]?.page = .aiChat
            state.contentTabs.tabs[id: activeTabID]?.title = "AI Chat"
            state.contentTabs.tabs[id: activeTabID]?.iconName = "bubble.right"
        }

        await store.receive { action in
            guard case let .content(.aiChat(.setup(setup))) = action else {
                return false
            }
            return setup.restoreSessionID == sessionID && setup.sessionID == nil
        }
        await store.receive { action in
            guard case let .content(.aiChat(.restoreOutcome(requestedSessionID, .restored(snapshot: snapshot), nil))) =
                action
            else {
                return false
            }
            return requestedSessionID == sessionID && snapshot.sessionID == sessionID
        }
        await store.receive { action in
            guard case let .content(.delegate(.aiChatSessionRestored(receivedSessionID, title))) = action else {
                return false
            }
            return receivedSessionID == sessionID && title == "Existing session title"
        }
        await store.receive { action in
            guard case let .internal(.aiChatTabTitleUpdated(receivedSessionID, title)) = action else {
                return false
            }
            return receivedSessionID == sessionID && title == "Existing session title"
        }

        XCTAssertEqual(createSessionCallCount.value, 0)
        XCTAssertEqual(loadedSessionIDs.value, [sessionID])
        let activeTab = try XCTUnwrap(store.state.contentTabs.tabs[id: activeTabID])
        XCTAssertEqual(activeTab.anchor, .aiChat(sessionID: sessionUUID.uuidString))
        XCTAssertEqual(activeTab.title, "Existing session title")
        XCTAssertEqual(store.state.sidebar.contentTabSidebarItems.first?.title, "Existing session title")
    }
}
