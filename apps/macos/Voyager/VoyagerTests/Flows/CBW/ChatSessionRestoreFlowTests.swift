// FLOW-ID: cbw.chat_session_restore
import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
@testable import VoyagerPagesFileManager
import XCTest

@MainActor
final class ChatSessionRestoreFlowTests: XCTestCase {
    // FLOW-PATH: reopen_last_inspector_chat

    /// CBW chat_session_restore: open_chat_reentry_restores_exact_session
    /// 닫힌 Inspector Chat을 다시 열 때 마지막 durable session을 새 대화로 교체하지 않는지 검증한다.
    /// - 검증 내용: exact session ID, persisted transcript, persisted request context 복원
    /// - 사전 조건: active tab Inspector에 durable active session이 남아 있고 Inspector는 닫혀 있다.
    /// - 기대 결과: Open Chat 진입이 같은 session을 복원하고 새 transient session을 만들지 않는다.
    func testOpenChatReentryRestoresExactPersistedSession() async throws {
        let sessionID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000647"),
        ))
        let persistedContext = AiChatLockedRequestContextSnapshot(
            currentContext: .init(summary: "Persisted request context"),
        )
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: [AiChatMessage(role: .user, content: "Persisted question")],
            lastRequestContext: persistedContext,
            updatedAtMs: 1,
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.aiChat = AiChatFeature.State(
            restoreSessionID: sessionID,
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
        )
        initialState.syncActiveTabInspectorState()
        let generatedSessionID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000648"),
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(generatedSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { requestedID in
                XCTAssertEqual(requestedID, sessionID)
                return snapshot
            }
        }
        // Inspector 재열기 결과만 검증하며 provider catalog 후속 action은 이 흐름의 소유 범위가 아니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.transcriptHistory, snapshot.transcriptHistory)
        XCTAssertEqual(store.state.inspector.aiChat.lastRequestContext, persistedContext)
    }

    // FLOW-PATH: missing_session_fallback

    /// CBW chat_session_restore: missing_session_falls_back_to_new_chat
    /// durable candidate가 저장소에서 사라졌을 때 기존 restore fallback이 새 세션을 제공하는지 검증한다.
    /// - 검증 내용: missingRecord failure, 새 session ID, 열린 Inspector Chat
    /// - 사전 조건: active candidate ID에 대응하는 persisted snapshot이 없다.
    /// - 기대 결과: 사용자에게 실패 화면 대신 기존 New Chat fallback이 표시된다.
    func testMissingPersistedSessionFallsBackToNewChat() async throws {
        let sessionID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000652"),
        ))
        let fallbackID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000653"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
        )
        initialState.syncActiveTabInspectorState()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(fallbackID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in nil }
        }
        // persisted restore와 fallback 최종 상태만 검증하며 provider 후속 action은 이 흐름의 소유 범위가 아니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, fallbackID)
        XCTAssertEqual(store.state.inspector.aiChat.restoreFailure, .missingRecord)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
    }

    // FLOW-PATH: corrupted_session_fallback

    /// CBW chat_session_restore: corrupted_session_falls_back_to_new_chat
    /// durable candidate의 저장 데이터가 손상됐을 때 안전한 새 세션 fallback을 검증한다.
    /// - 검증 내용: corruptedRecord failure, 새 session ID, 열린 Inspector Chat
    /// - 사전 조건: active candidate의 persisted snapshot load가 오류를 반환한다.
    /// - 기대 결과: 손상된 session 대신 빈 New Chat이 표시된다.
    func testCorruptedPersistedSessionFallsBackToNewChat() async throws {
        let sessionID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000674"),
        ))
        let fallbackID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000675"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
        )
        initialState.syncActiveTabInspectorState()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(fallbackID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                throw NSError(domain: "ChatSessionRestoreFlowTests", code: 1)
            }
        }
        // corrupted restore와 fallback 최종 상태만 검증하며 provider 후속 action은 이 흐름의 소유 범위가 아니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, fallbackID)
        XCTAssertEqual(store.state.inspector.aiChat.restoreFailure, .corruptedRecord)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
    }

    // FLOW-PATH: untouched_transient_fallback

    /// CBW chat_session_restore: untouched_transient_uses_new_chat_path
    /// 아직 사용하지 않은 transient Inspector session을 durable resume 후보로 오인하지 않는지 검증한다.
    /// - 검증 내용: prepared transient 제외, 새 session ID, 빈 transcript
    /// - 사전 조건: Inspector에 untouched prepared transient session만 남아 있다.
    /// - 기대 결과: exact restore 없이 기존 New Chat 경로가 실행된다.
    func testUntouchedTransientCandidateUsesExistingNewChatPath() async throws {
        let transientID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000654"),
        ))
        let newSessionID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000655"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: transientID,
            preparedTransientSessionID: transientID,
            sessionStatus: .idle,
        )
        initialState.syncActiveTabInspectorState()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(newSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
        }
        // candidate 배제 후 New Chat 최종 상태만 검증하며 catalog 후속 action은 이 흐름의 소유 범위가 아니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, newSessionID)
        XCTAssertTrue(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
    }

    // FLOW-PATH: first_use_new_chat

    /// CBW chat_session_restore: first_use_opens_new_chat
    /// Inspector Chat을 처음 여는 탭에는 복원 후보 없이 새 대화가 제공되는지 검증한다.
    /// - 검증 내용: 새 transient session, 빈 transcript, 열린 Inspector
    /// - 사전 조건: active Directory 탭에 Inspector Chat session 이력이 없다.
    /// - 기대 결과: 기존 New Chat 경로가 실행되고 복원 저장소를 조회하지 않는다.
    func testFirstUseOpensNewChat() async throws {
        let newSessionID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000660"),
        )
        let store = TestStore(
            initialState: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents"),
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(newSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("First use must not attempt persisted restore")
                return nil
            }
        }
        // 최초 진입의 최종 사용자 상태만 검증하며 provider catalog 후속 action은 이 흐름의 소유 범위가 아니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, newSessionID)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
    }

    // FLOW-PATH: history_close_new_chat

    /// CBW chat_session_restore: history_close_reopens_new_chat
    /// Chat History 화면에서 Inspector를 닫은 뒤 Open Chat으로 재진입하면 마지막 chat을 자동 복원하지 않는지 검증한다.
    /// - 검증 내용: History mode 제외, 새 transient session, 빈 transcript
    /// - 사전 조건: active Directory 탭의 Inspector가 sessions mode에서 닫혀 있다.
    /// - 기대 결과: 재진입은 History나 이전 session이 아니라 New Chat을 표시한다.
    func testHistoryCloseReopensNewChat() async throws {
        let previousSessionID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000661"),
        ))
        let newSessionID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000662"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            sessionID: previousSessionID,
            sessionStatus: .active,
        )
        initialState.syncActiveTabInspectorState()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(newSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("History-close reopen must use New Chat")
                return nil
            }
        }
        // History-close 재진입의 목적지와 session 교체만 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, newSessionID)
        XCTAssertNotEqual(store.state.inspector.aiChat.sessionID, previousSessionID)
    }

    // FLOW-PATH: explicit_destination_precedence

    /// CBW chat_session_restore: explicit_destinations_override_reopen
    /// retained durable session이 있어도 명시적 New Chat과 Chat History 명령이 자동 복원보다 우선하는지 검증한다.
    /// - 검증 내용: explicit New Chat session 교체, explicit History sessions mode
    /// - 사전 조건: 닫힌 Inspector에 durable active session이 남아 있다.
    /// - 기대 결과: 두 명시적 명령 모두 retained session의 automatic restore를 실행하지 않는다.
    func testExplicitDestinationsOverrideReopen() async throws {
        let retainedID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000663"),
        ))
        let newSessionID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000664"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: retainedID,
            sessionStatus: .active,
        )
        initialState.syncActiveTabInspectorState()

        let newChatStore = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(newSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Explicit New Chat must not restore retained session")
                return nil
            }
        }
        // 명시적 목적지의 최종 상태만 검증한다.
        newChatStore.exhaustivity = .off(showSkippedAssertions: false)
        await newChatStore.send(.request(.newChat))
        await newChatStore.skipReceivedActions()
        await newChatStore.finish()
        XCTAssertEqual(newChatStore.state.inspector.aiChat.sessionID?.rawValue, newSessionID)
        XCTAssertNotEqual(newChatStore.state.inspector.aiChat.sessionID, retainedID)

        let historyStore = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(newSessionID)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Explicit Chat History must not restore retained session")
                return nil
            }
        }
        // 명시적 목적지의 최종 상태만 검증한다.
        historyStore.exhaustivity = .off(showSkippedAssertions: false)
        await historyStore.send(.request(.showChatHistory))
        await historyStore.skipReceivedActions()
        await historyStore.finish()
        XCTAssertEqual(historyStore.state.inspector.aiChat.mode, .sessions)
        XCTAssertNil(historyStore.state.inspector.aiChat.sessionID)
    }

    // FLOW-PATH: content_tab_isolation

    /// CBW chat_session_restore: content_tabs_keep_inspector_sessions_isolated
    /// Collection 탭 B에서 Open Chat을 실행할 때 Directory 탭 A의 retained session이 유출되지 않는지 검증한다.
    /// - 검증 내용: active B의 새 session, A snapshot의 exact session과 transcript 보존
    /// - 사전 조건: Directory A에는 marker transcript가 있는 durable session, Collection B에는 session이 없다.
    /// - 기대 결과: B는 New Chat을 표시하고 A의 tab-scoped Inspector state는 변경되지 않는다.
    func testContentTabsKeepInspectorSessionsIsolated() async throws {
        let sessionA = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000665"),
        ))
        let sessionB = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000666"),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let tabA = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionA,
            sessionStatus: .active,
            transcriptHistory: [AiChatMessage(role: .user, content: "Tab A marker")],
        )
        initialState.syncActiveTabInspectorState()

        let tabB = ContentTabID()
        let collectionAnchor = ContentTabPageAnchor.collectionFile(
            url: URL(fileURLWithPath: "/Users/test/Saved.voyagercollection"),
        )
        let contentB = FileManagerContentFeature.State.initialContent(
            for: collectionAnchor,
            inheritingWindowContextFrom: initialState.content,
        )
        initialState.contentTabs.tabs.append(ContentTabItem(
            id: tabB,
            page: .collection,
            anchor: collectionAnchor,
            isPinned: false,
            title: "Saved",
            iconName: "rectangle.stack",
        ))
        initialState.contentTabs.activeTabID = tabB
        initialState.tabContentStates[tabB] = contentB
        initialState.tabInspectorStates[tabB] = .init()
        initialState.content = contentB
        initialState.inspector = .init()

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .constant(sessionB)
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [] })
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Tab B must not restore Tab A session")
                return nil
            }
        }
        // 탭 B의 결과와 탭 A snapshot 격리만 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(store.state.contentTabs.activeTabID, tabB)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID?.rawValue, sessionB)
        XCTAssertEqual(store.state.tabInspectorStates[tabA]?.aiChat.sessionID, sessionA)
        XCTAssertEqual(
            store.state.tabInspectorStates[tabA]?.aiChat.transcriptHistory,
            [AiChatMessage(role: .user, content: "Tab A marker")],
        )
    }
}
