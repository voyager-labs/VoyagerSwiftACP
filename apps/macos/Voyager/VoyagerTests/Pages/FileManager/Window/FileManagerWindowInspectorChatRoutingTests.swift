import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesEntryOperations
import XCTest

// swiftlint:disable type_name
@MainActor
final class FileManagerWindowInspectorChatRoutingTests: XCTestCase {
    func testOpenContextualAiChatRoutesCurrentContextSetupToInspector() async {
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

        let connectionsFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: initialState.content,
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000000"),
            connectionsFile: connectionsFile,
        )

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000000"),
            connectionsFile: connectionsFile,
        )

        await store.send(.request(.openContextualAiChat))
        await assertOpenChat(on: store, expectedSetup: expectedSetup)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)

        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Documents · 1 selected")
        assertCurrentContextInitialChatIsEmpty(store.state.inspector.aiChat)
    }

    func testOpenContextualAiChatTogglesClosedOnRepeatedCommand() async {
        let selectedEntry = makeEntry(name: "A.txt", fullPath: "/Users/test/Documents/A.txt")
        let anotherEntry = makeEntry(name: "B.txt", fullPath: "/Users/test/Documents/B.txt")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry, anotherEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id, anotherEntry.id]

        let connectionsFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])
        let currentContextSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: initialState.content,
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000000"),
            connectionsFile: connectionsFile,
        )

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { connectionsFile }
        }
        store.exhaustivity = .off

        await store.send(.request(.openContextualAiChat))
        await assertOpenChatRouting(on: store, expectedSetup: currentContextSetup)
        await assertAiChatSetupIgnoringSession(on: store, expectedSetup: currentContextSetup)

        let firstSessionID = store.state.inspector.aiChat.sessionID
        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Documents · 2 selected")

        await store.send(.request(.openContextualAiChat))
        await assertCloseChat(on: store)

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, firstSessionID)
    }

    func testOpenContextualAiChatWithoutConfiguredProviderShowsSettingsGate() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000030")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: initialState.content,
            sessionID: AiChatSessionID(rawValue: fixedUUID),
            connectionsFile: .empty(),
        )

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: .empty())

        await store.send(.request(.openContextualAiChat))
        await assertOpenChat(on: store, expectedSetup: expectedSetup)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)

        XCTAssertTrue(store.state.inspector.aiChat.catalogRows.isEmpty)
        XCTAssertNil(store.state.inspector.aiChat.selectedModelHandle)
        XCTAssertFalse(store.state.inspector.aiChat.canSubmit)
        XCTAssertEqual(store.state.inspector.aiChat.connectionState, .error(.init(
            title: "No AI provider connected",
            detail: "Connect an AI provider in Settings to start chatting.",
            fixLabel: "Connect provider in Settings",
        )))
    }

    func testToolbarSparklesOpensInspectorChatMode() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000010")
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

        let connectionsFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: initialState.content,
            sessionID: AiChatSessionID(rawValue: fixedUUID),
            connectionsFile: connectionsFile,
        )

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: connectionsFile)

        await store.send(.content(.view(.openContextualAiChatTapped)))
        await store.receive(\.content.delegate.openContextualAiChat)
        await store.receive(\.request.openContextualAiChat)
        await assertOpenChat(on: store, expectedSetup: expectedSetup)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)

        await store.send(.content(.view(.openContextualAiChatTapped)))
        await store.receive(\.content.delegate.openContextualAiChat)
        await store.receive(\.request.openContextualAiChat)
        await assertCloseChat(on: store)

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    func testCommandLTogglesContextualAiChat() async {
        let fixture = makeFocusedWindowFixture(
            sessionUUID: makeUUID("00000000-0000-0000-0000-000000000020"),
            focusedUUID: makeUUID("00000000-0000-0000-0000-000000000021"),
        )

        await assertMenuCommandDelegatesToWindowManager()

        let windowStore = makeWindowManagerStore(fixture: fixture)
        await assertCommandLOpensContextualAiChat(on: windowStore, fixture: fixture)
        await assertCommandLClosesContextualAiChat(on: windowStore, fixture: fixture)
        await windowStore.finish()
    }

    private func assertMenuCommandDelegatesToWindowManager() async {
        let menuStore = TestStore(initialState: MenuCommandsFeature.State()) {
            MenuCommandsFeature()
        }
        menuStore.exhaustivity = .off

        await menuStore.send(.view(.edit(.openContextualAiChat)))
        await menuStore.receive {
            guard case .delegate(.windowManager(.edit(.openContextualAiChat))) = $0 else { return false }
            return true
        }
        await menuStore.finish()
    }

    private func makeWindowManagerStore(
        fixture: FocusedWindowFixture,
    ) -> TestStore<WindowManagerFeature.State, WindowManagerFeature.Action> {
        let store = TestStore(initialState: fixture.initialState) {
            WindowManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(fixture.sessionUUID)
            $0.aiConnectionsFileClient.load = { fixture.connectionsFile }
        }
        store.exhaustivity = .off
        return store
    }

    private func assertCommandLOpensContextualAiChat(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.send(.edit(.openContextualAiChat))
        await assertWindowManagerRequest(on: store, fixture: fixture)
        await assertWindowManagerOpenChat(on: store, fixture: fixture)
        await assertWindowManagerAiChatSetup(on: store, fixture: fixture)
    }

    private func assertCommandLClosesContextualAiChat(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.send(.edit(.openContextualAiChat))
        await assertWindowManagerRequest(on: store, fixture: fixture)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.setInspectorVisible) {
            $0.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible = false
        }
    }

    private func assertWindowManagerRequest(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.request(.openContextualAiChat)))) = action else {
                return false
            }
            return id == fixture.focusedUUID
        }
    }

    private func assertWindowManagerOpenChat(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.receive { action in
            guard case let .windows(.element(id: id, action: .window(.inspector(.openChat(setup))))) = action else {
                return false
            }
            return id == fixture.focusedUUID
                && setup.sessionID == fixture.expectedSetup.sessionID
                && setup.currentContext == fixture.expectedSetup.currentContext
        }
    }

    private func assertWindowManagerAiChatSetup(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.aiChat.setup) {
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionID = fixture.expectedSetup.sessionID
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionStatus = fixture.expectedSetup
                .sessionStatus
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.currentContext = fixture.expectedSetup
                .currentContext
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.transcriptHistory = fixture.expectedSetup
                .transcriptHistory
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.draftText = fixture.expectedSetup.draftText
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.streamDraftText = ""
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.catalogRows = fixture.expectedSetup.catalogRows
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.selectedModelHandle = fixture.expectedSetup
                .selectedModelHandle
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.lockedModelHandle = fixture.expectedSetup
                .lockedModelHandle
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.lastExecutionFailure = fixture.expectedSetup
                .lastExecutionFailure
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.executionPhase = .idle
        }
    }
}

// swiftlint:enable type_name

private extension FileManagerWindowInspectorChatRoutingTests {
    private func assertCurrentContextInitialChatIsEmpty(_ state: AiChatFeature.State) {
        guard case let .empty(summary, selectedModel) = state.surfaceState else {
            XCTFail("Expected current-context chat to start with empty surface")
            return
        }

        XCTAssertEqual(summary.title, "Documents · 1 selected")
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
        XCTAssertTrue(state.transcriptHistory.isEmpty)
        XCTAssertTrue(state.draftText.isEmpty)
    }

    private func makeStore(
        initialState: FileManagerFeature.State,
        uuid: UUID,
        connectionsFile: AIConnectionsFile,
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(uuid)
            $0.aiConnectionsFileClient.load = { connectionsFile }
        }
        store.exhaustivity = .off
        return store
    }

    private func assertOpenChat(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
    ) async {
        await store.receive { action in
            guard case let .inspector(.openChat(setup)) = action else { return false }
            return setup.sessionID == expectedSetup.sessionID
                && setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && setup.lockedModelHandle == expectedSetup.lockedModelHandle
                && setup.lastExecutionFailure == expectedSetup.lastExecutionFailure
        }

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    private func assertAiChatSetup(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
    ) async {
        await store.receive(\.inspector.aiChat.setup)

        XCTAssertEqual(store.state.inspector.aiChat.sessionID, expectedSetup.sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.sessionStatus, expectedSetup.sessionStatus)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext, expectedSetup.currentContext)
        XCTAssertEqual(store.state.inspector.aiChat.transcriptHistory, expectedSetup.transcriptHistory)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, expectedSetup.draftText)
        XCTAssertEqual(store.state.inspector.aiChat.streamDraftText, "")
        XCTAssertEqual(store.state.inspector.aiChat.catalogRows, expectedSetup.catalogRows)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, expectedSetup.selectedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, expectedSetup.lockedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lastExecutionFailure, expectedSetup.lastExecutionFailure)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .idle)
    }

    private func assertCloseChat(on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>) async {
        await store.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = false
        }
    }

    private func assertOpenChatRouting(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
    ) async {
        await store.receive { action in
            guard case let .inspector(.openChat(setup)) = action else { return false }
            return setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && setup.lockedModelHandle == expectedSetup.lockedModelHandle
                && setup.lastExecutionFailure == expectedSetup.lastExecutionFailure
        }

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    private func assertAiChatSetupIgnoringSession(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
    ) async {
        await store.receive(\.inspector.aiChat.setup)

        XCTAssertEqual(store.state.inspector.aiChat.sessionStatus, expectedSetup.sessionStatus)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext, expectedSetup.currentContext)
        XCTAssertEqual(store.state.inspector.aiChat.transcriptHistory, expectedSetup.transcriptHistory)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, expectedSetup.draftText)
        XCTAssertEqual(store.state.inspector.aiChat.streamDraftText, "")
        XCTAssertEqual(store.state.inspector.aiChat.catalogRows, expectedSetup.catalogRows)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, expectedSetup.selectedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, expectedSetup.lockedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lastExecutionFailure, expectedSetup.lastExecutionFailure)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .idle)
    }

    private func makeSessionID(_ rawValue: String) -> AiChatSessionID {
        guard let uuid = UUID(uuidString: rawValue) else {
            XCTFail("Invalid UUID fixture: \(rawValue)")
            return AiChatSessionID(rawValue: UUID())
        }
        return AiChatSessionID(rawValue: uuid)
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
        let sessionUUID: UUID
        let connectionsFile: AIConnectionsFile
        let expectedSetup: AiChatSetupState
    }

    private func makeFocusedWindowFixture(
        sessionUUID: UUID,
        focusedUUID: UUID,
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
            let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
                content: windowState.content,
                sessionID: AiChatSessionID(rawValue: sessionUUID),
                connectionsFile: .empty(),
            )
            return FocusedWindowFixture(
                initialState: initialState,
                focusedUUID: focusedUUID,
                sessionUUID: sessionUUID,
                connectionsFile: .empty(),
                expectedSetup: expectedSetup,
            )
        }
        focusedWindow.content.entryViewLayout.entryOperations.items = [selectedEntry]
        focusedWindow.content.entryViewLayout.selectedIds = [selectedEntry.id]
        initialState.windows[id: focusedUUID]?.window = focusedWindow

        let connectionsFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: focusedWindow.content,
            sessionID: AiChatSessionID(rawValue: sessionUUID),
            connectionsFile: connectionsFile,
        )

        return FocusedWindowFixture(
            initialState: initialState,
            focusedUUID: focusedUUID,
            sessionUUID: sessionUUID,
            connectionsFile: connectionsFile,
            expectedSetup: expectedSetup,
        )
    }
}
