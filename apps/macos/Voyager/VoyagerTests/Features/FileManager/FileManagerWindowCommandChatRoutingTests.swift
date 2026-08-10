import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerWindowCommandChatRoutingTests: XCTestCase {
    func testMenuCommandsRouteSemanticChatDestinations() async {
        let store = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        // store.exhaustivity = .off: 메뉴 command에서 WindowManager delegate로의 의미 라우팅만 검증한다.
        store.exhaustivity = .off

        await store.send(.view(.edit(.openChat)))
        await store.receive {
            guard case .delegate(.windowManager(.edit(.openChat))) = $0 else { return false }
            return true
        }

        await store.send(.view(.edit(.showChatHistory)))
        await store.receive {
            guard case .delegate(.windowManager(.edit(.showChatHistory))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    /// Open Chat 단축키 경로는 닫힌 Inspector의 마지막 active session을 복원한다.
    /// - 검증 내용: app menu command부터 exact session restore까지의 session ID와 transcript
    /// - 사전 조건: focused Directory tab에 durable active session이 남아 있고 Inspector는 닫혀 있다.
    /// - 기대 결과: Open Chat이 New Chat을 만들지 않고 기존 session을 다시 표시한다.
    func testOpenChatCommandReopensRetainedActiveSession() async throws {
        let sessionID = try AiChatSessionID(rawValue: XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000647"),
        ))
        let transcript = [AiChatMessage(role: .user, content: "Retained command session")]
        let snapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: nil,
            model: nil,
            transcriptHistory: transcript,
            lastRequestContext: nil,
            updatedAtMs: 1,
        )
        let fixture = makeFocusedWindowFixture(
            focusedUUID: makeUUID("00000000-0000-0000-0000-000000000020"),
        ) { window in
            window.inspector.activeMode = .chat
            window.inspector.aiChat = AiChatFeature.State(
                mode: .chat,
                sessionID: sessionID,
                sessionStatus: .active,
            )
            window.syncActiveTabInspectorState()
        }
        let store = makeWindowManagerStore(fixture: fixture, persistedSnapshot: snapshot)

        await store.send(.edit(.openChat))
        await assertWindowManagerRequest(.reopenChat, on: store, fixture: fixture)
        await store.skipReceivedActions()
        await store.finish()

        let aiChat = try XCTUnwrap(store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat)
        XCTAssertTrue(try XCTUnwrap(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible))
        XCTAssertEqual(aiChat.sessionID, sessionID)
        XCTAssertEqual(aiChat.transcriptHistory, transcript)
    }

    func testChatCommandsOpenAndSwitchDestinationsWithoutClosingInspector() async {
        let fixture = makeFocusedWindowFixture(
            focusedUUID: makeUUID("00000000-0000-0000-0000-000000000021"),
        )
        let savedSessionCount = LockIsolated(0)
        let store = makeWindowManagerStore(fixture: fixture, savedSessionCount: savedSessionCount)

        await store.send(.edit(.openChat))
        await assertWindowManagerRequest(.reopenChat, on: store, fixture: fixture)
        await store.receive {
            guard case let .windows(.element(
                id: id,
                action: .window(.internal(.aiChatNewChatInspectorOpenLoaded(_, setup, file))),
            )) = $0
            else { return false }
            return id == fixture.focusedUUID
                && setup.mode == .chat
                && setup.currentContext == fixture.expectedSetup.currentContext
                && file == fixture.connectionsFile
        }
        await store.receive {
            guard case let .windows(.element(id: id, action: .window(.inspector(.openNewChat(setup, file))))) = $0
            else { return false }
            return id == fixture.focusedUUID
                && setup.mode == .chat
                && setup.currentContext == fixture.expectedSetup.currentContext
                && file == fixture.connectionsFile
        }
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.aiChat.setup)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.aiChat.providerConnectionsUpdated)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.setInspectorVisible) {
            $0.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible = true
        }
        await store.receive(
            \.windows[id: fixture.focusedUUID].window.internal.applyInspectorNewChatSeed,
        )

        guard let firstSessionID = store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionID
        else {
            XCTFail("Expected New Chat to prepare a session ID")
            return
        }
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible, true)
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.mode, .chat)
        XCTAssertEqual(
            store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.transcriptHistory.isEmpty,
            true,
        )
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.draftText.isEmpty, true)
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorPaneExists, false)

        await store.send(.edit(.showChatHistory))
        await assertWindowManagerRequest(.showChatHistory, on: store, fixture: fixture)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.showChatHistoryRequested)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.aiChat.backToSessionsTapped)

        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible, true)
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.mode, .sessions)
        XCTAssertEqual(
            store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionID,
            firstSessionID,
        )

        await store.send(.edit(.openChat))
        await assertWindowManagerRequest(.reopenChat, on: store, fixture: fixture)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.internal(.applyInspectorNewChatSeed(application))),
            )) = action
            else { return false }
            return id == fixture.focusedUUID && application.snapshot == fixture.expectedSetup.currentContext
        }

        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible, true)
        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.mode, .chat)
        XCTAssertNotEqual(
            store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionID,
            firstSessionID,
        )

        await store.send(.edit(.openChat))
        await assertWindowManagerRequest(.reopenChat, on: store, fixture: fixture)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.closeChat)

        XCTAssertEqual(store.state.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible, false)
        XCTAssertEqual(savedSessionCount.value, 0)
        await store.finish()
    }

    // MARK: - VOY-637-transcript_search_command

    /// VOY-637-transcript_search_command: production command composition이 focused New Chat의 transcript search를 연다.
    /// Settings commands root와 FileManager NSHosting root가 분리되어도 reducer command route로 local search를 전달한다.
    /// - 검증 내용: AppRoot의 menu command부터 focused window의 AiChat transcriptSearch state까지 실제 reducer chain
    /// - 사전 조건: focused FileManager inspector가 빈 transcript의 `.chat` mode로 표시됨
    /// - 기대 결과: transcript search가 열리고 Collection Filter Composer는 열리지 않음
    func testFindCommandFromProductionCompositionOpensFocusedChatTranscriptSearch() async {
        let focusedUUID = makeUUID("00000000-0000-0000-0000-000000000637")
        var window = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        window.inspector.inspectorVisible = true
        window.inspector.inspectorPaneExists = true
        window.inspector.activeMode = .chat
        window.inspector.aiChat.mode = .chat

        var initialState = AppRootFeature.State()
        initialState.windowManager.windows = [
            WindowSessionState(id: focusedUUID, window: window),
        ]
        initialState.windowManager.focusedWindowID = focusedUUID

        let store = TestStore(initialState: initialState) {
            AppRootFeature()
        }
        // store.exhaustivity = .off: production command chain의 중간 delegate action보다 최종 focused child state를 검증한다.
        store.exhaustivity = .off

        await store.send(.menuCommands(.view(.edit(.find))))
        await store.skipReceivedActions()

        XCTAssertEqual(
            store.state.windowManager.windows[id: focusedUUID]?.window.inspector.aiChat.transcriptSearch.isPresented,
            true,
        )
        XCTAssertFalse(MenuCommandsState(state: store.state).isComposerPresented)
        await store.finish()
    }

    /// VOY-637-transcript_search_command: focused FileManager window가 없으면 Find command는 no-op이다.
    /// App command가 background window를 임의로 변경하지 않는 focused-window 경계를 검증한다.
    /// - 검증 내용: `.edit(.find)`가 후속 window command를 방출하지 않는지 확인
    /// - 사전 조건: WindowManager에 focused FileManager window가 없음
    /// - 기대 결과: 상태 변경과 후속 action 없이 command가 종료됨
    func testFindCommandWithoutFocusedWindowDoesNothing() async {
        let store = TestStore(initialState: WindowManagerFeature.State()) {
            WindowManagerFeature()
        }

        await store.send(.edit(.find))
    }

    /// VOY-637-transcript_search_command: stale focus가 남아 있어도 Find command는 live background window를 변경하지 않는다.
    /// Focus invariant 위반을 MRU fallback으로 숨기지 않는 command routing 정책을 검증한다.
    /// - 검증 내용: 존재하지 않는 focused ID에서 `.edit(.find)`가 후속 window command를 방출하지 않는지 확인
    /// - 사전 조건: live background window 하나와 registry에 없는 focusedWindowID가 있음
    /// - 기대 결과: live window 상태가 유지되고 후속 action 없이 command가 종료됨
    func testFindCommandWithStaleFocusedWindowDoesNothing() async {
        let liveWindowID = makeUUID("00000000-0000-0000-0000-000000000638")
        let staleWindowID = makeUUID("00000000-0000-0000-0000-000000000639")
        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(
                id: liveWindowID,
                window: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents"),
            ),
        ]
        initialState.focusedWindowID = staleWindowID
        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.edit(.find))
        XCTAssertEqual(Array(store.state.windows.ids), [liveWindowID])
    }

    private func makeWindowManagerStore(
        fixture: FocusedWindowFixture,
        savedSessionCount: LockIsolated<Int>? = nil,
        persistedSnapshot: AiChatSessionSnapshot? = nil,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        let store = TestStore(initialState: fixture.initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { fixture.connectionsFile }
            $0.aiChatSessionPersistenceClient.loadSession = { sessionID in
                guard persistedSnapshot?.sessionID == sessionID else { return nil }
                return persistedSnapshot
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSessionCount?.withValue { $0 += 1 }
                return snapshot
            }
        }
        // store.exhaustivity = .off: WindowManager부터 AiChat persistence까지의 통합 흐름에서 목적지 action만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func assertWindowManagerRequest(
        _ command: FileManagerWindowAction.WindowCommand,
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(receivedCommand)))) = action else {
                return false
            }
            guard id == fixture.focusedUUID else { return false }
            switch (receivedCommand, command) {
            case (.reopenChat, .reopenChat), (.showChatHistory, .showChatHistory):
                return true
            default:
                return false
            }
        }
    }

    private func makeEntry(name: String, fullPath: String) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: (name as NSString).pathExtension,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return uuid
    }

    private struct FocusedWindowFixture {
        let initialState: WindowManagerFeature.State
        let focusedUUID: UUID
        let connectionsFile: AIConnectionsFile
        let expectedSetup: AiChatSetupState
    }

    private func makeFocusedWindowFixture(
        focusedUUID: UUID,
        configure: (inout FileManagerFeature.State) -> Void = { _ in },
    ) -> FocusedWindowFixture {
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")

        var initialState = WindowManagerFeature.State()
        let windowState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.windows = [
            WindowSessionState(id: focusedUUID, window: windowState),
        ]
        initialState.focusedWindowID = focusedUUID

        guard var focusedWindow = initialState.windows[id: focusedUUID]?.window else {
            XCTFail("Missing focused window fixture")
            let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: windowState.content)
            return FocusedWindowFixture(
                initialState: initialState,
                focusedUUID: focusedUUID,
                connectionsFile: .empty(),
                expectedSetup: expectedSetup,
            )
        }
        focusedWindow.content.entryOperations.items = [selectedEntry]
        focusedWindow.content.entryViewLayout.entries = [selectedEntry]
        focusedWindow.content.entryViewLayout.selectedIds = [selectedEntry.id]
        configure(&focusedWindow)
        initialState.windows[id: focusedUUID]?.window = focusedWindow

        return FocusedWindowFixture(
            initialState: initialState,
            focusedUUID: focusedUUID,
            connectionsFile: .empty(),
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: focusedWindow.content),
        )
    }
}
