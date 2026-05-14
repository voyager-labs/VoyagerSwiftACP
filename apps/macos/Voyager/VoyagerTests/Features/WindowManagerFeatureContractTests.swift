import ComposableArchitecture
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
import VoyagerPagesOnboarding
import XCTest

@MainActor
final class WindowManagerFeatureContractTests: XCTestCase {
    func testApplyAppPreferencesFansOutToAllWindows() async {
        let firstID = UUID()
        let secondID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: firstID, window: .makeInitial(path: "/a")),
            WindowSessionState(id: secondID, window: .makeInitial(path: "/b")),
        ]

        var preferences = AppPreferencesState()
        preferences.viewLayout = .grid
        preferences.groupKey = .kind

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
            $0.onboardingWindowClient.showIfNeeded = { false }
            $0.fileManagerWindowClient.open = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.lifecycle(.applyAppPreferences(preferences))) {
            $0.appPreferences = preferences
        }
        await store.finish()
    }

    func testQuickLookRoutesToFocusedWindowCommandBus() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.file(.quickLook))
        await store.finish()
    }

    func testNewFolderRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_891))
            $0.entryFileOpsClient.createFolder = { _, _ in }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
        store.exhaustivity = .off

        await store.send(.file(.newFolder))
        await store.finish()
    }

    func testCopyRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.edit(.copy))
        await store.finish()
    }

    func testOpenContextualAiChatEditCommandRoutesToFocusedWindowRequest() async {
        let focusedID = UUID()
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000000")
        let fixedSessionID = AiChatSessionID(rawValue: fixedUUID)

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let connectionsFile = AIConnectionsFile.empty()
        let expectedSetup = makeExpectedSetup(
            initialState: initialState,
            focusedID: focusedID,
            sessionID: fixedSessionID,
            connectionsFile: connectionsFile,
        )

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(fixedUUID)
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.undoManagerClient = UndoManagerClient(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
        store.exhaustivity = .off

        await store.send(.edit(.openContextualAiChat))
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.openContextualAiChat)))) = action else {
                return false
            }
            return id == focusedID
        }
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.inspector(.openChat(setup, openedConnectionsFile))),
            )) = action else {
                return false
            }
            return id == focusedID
                && setup.sessionID == expectedSetup.sessionID
                && setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && openedConnectionsFile == connectionsFile
        }
        await assertAiChatSetupReceived(on: store, focusedID: focusedID, expectedSetup: expectedSetup)
        await store.receive { action in
            guard case let .windows(.element(
                id: id,
                action: .window(.inspector(.aiChat(.providerConnectionsUpdated(file)))),
            )) = action else {
                return false
            }
            return id == focusedID && file == connectionsFile
        }
        await store.finish()
    }

    func testWindowOpenSettingsDelegateRoutesToWindowManagerDelegate() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }

        await store.send(.windows(.element(id: focusedID, action: .window(.delegate(.openAISettings)))))
        await store.receive(.delegate(.openAISettings))
    }

    func testToggleSidebarRoutesToFocusedWindow() async {
        let focusedID = UUID()

        var initialState = WindowManagerFeature.State()
        initialState.windows = [
            WindowSessionState(id: focusedID, window: .makeInitial(path: "/tmp")),
        ]
        initialState.focusedWindowID = focusedID

        let store = TestStore(initialState: initialState) {
            WindowManagerFeature()
        }
        store.exhaustivity = .off

        await store.send(.window(.toggleSidebar))
    }

    func testNoCommandSentWhenNoFocusedWindow() {
        var state = WindowManagerFeature.State()
        let reducer = WindowManagerFeature()

        _ = reducer.reduce(into: &state, action: .file(.quickLook))

        XCTAssertNil(state.focusedWindowID)
        XCTAssertTrue(state.windows.isEmpty)
    }

    private func makeSessionID(_ rawValue: String) -> AiChatSessionID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return AiChatSessionID(rawValue: UUID())
        }
        return AiChatSessionID(rawValue: uuid)
    }

    private func makeExpectedSetup(
        initialState: WindowManagerFeature.State,
        focusedID: UUID,
        sessionID: AiChatSessionID,
        connectionsFile _: AIConnectionsFile,
    ) -> AiChatSetupState {
        guard let content = initialState.windows[id: focusedID]?.window.content else {
            XCTFail("Missing focused window fixture")
            return FileManagerAiChatContextAdapter.makeAiChatSetupState(
                content: .init(),
                sessionID: sessionID,
            )
        }
        return FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: content,
            sessionID: sessionID,
        )
    }

    private func assertAiChatSetupReceived(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        focusedID: UUID,
        expectedSetup: AiChatSetupState,
    ) async {
        await store.receive(\.windows[id: focusedID].window.inspector.aiChat.setup) {
            $0.windows[id: focusedID]?.window.inspector.aiChat.sessionID = expectedSetup.sessionID
            $0.windows[id: focusedID]?.window.inspector.aiChat.sessionStatus = expectedSetup.sessionStatus
            $0.windows[id: focusedID]?.window.inspector.aiChat.currentContext = expectedSetup.currentContext
            $0.windows[id: focusedID]?.window.inspector.aiChat.transcriptHistory = expectedSetup.transcriptHistory
            $0.windows[id: focusedID]?.window.inspector.aiChat.draftText = expectedSetup.draftText
            $0.windows[id: focusedID]?.window.inspector.aiChat.catalogRows = expectedSetup.catalogRows
            $0.windows[id: focusedID]?.window.inspector.aiChat.selectedModelHandle = expectedSetup.selectedModelHandle
            $0.windows[id: focusedID]?.window.inspector.aiChat.lockedModelHandle = expectedSetup.lockedModelHandle
            $0.windows[id: focusedID]?.window.inspector.aiChat.lastExecutionFailure = expectedSetup.lastExecutionFailure
            $0.windows[id: focusedID]?.window.inspector.aiChat.executionPhase = .idle
        }
    }

    private func makeUUID(_ rawValue: String) -> UUID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return UUID()
        }
        return uuid
    }
}
