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
        await store.send(.windows(.element(
            id: fixture.focusedUUID,
            action: .window(.inspector(.setInspectorPaneExists(true))),
        ))) {
            $0.windows[id: fixture.focusedUUID]?.window.inspector.inspectorPaneExists = true
        }
    }

    private func assertCommandLClosesContextualAiChat(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.send(.edit(.openContextualAiChat))
        await assertWindowManagerRequest(on: store, fixture: fixture)
        await store.receive(\.windows[id: fixture.focusedUUID].window.inspector.closeChat) {
            $0.windows[id: fixture.focusedUUID]?.window.inspector.inspectorVisible = false
        }
        XCTAssertEqual(
            store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.sessionID,
            fixture.expectedSetup.sessionID,
        )
    }

    private func assertWindowManagerRequest(
        on store: TestStore<WindowManagerFeature.State, WindowManagerFeature.Action>,
        fixture: FocusedWindowFixture,
    ) async {
        await store.receive { action in
            guard case let .windows(.element(id: id, action: windowAction)) = action else {
                return false
            }
            guard case .window(.request(.openContextualAiChat)) = windowAction else {
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
            guard case let .windows(.element(id: id, action: windowAction)) = action else {
                return false
            }
            guard case let .window(.inspector(inspectorAction)) = windowAction else {
                return false
            }
            guard case let .openChat(setup, connectionsFile) = inspectorAction else {
                return false
            }
            return id == fixture.focusedUUID
                && setup.sessionID == fixture.expectedSetup.sessionID
                && setup.currentContext == fixture.expectedSetup.currentContext
                && connectionsFile == fixture.connectionsFile
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
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.catalogRows = fixture.expectedSetup.catalogRows
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.selectedModelHandle = fixture.expectedSetup
                .selectedModelHandle
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.lockedModelHandle = fixture.expectedSetup
                .lockedModelHandle
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.lastExecutionFailure = fixture.expectedSetup
                .lastExecutionFailure
            $0.windows[id: fixture.focusedUUID]?.window.inspector.aiChat.executionPhase = .idle
        }

        await store.receive { action in
            guard case let .windows(.element(id: id, action: windowAction)) = action else {
                return false
            }
            guard case let .window(.inspector(.aiChat(aiChatAction))) = windowAction else {
                return false
            }
            guard case let .providerConnectionsUpdated(file) = aiChatAction else {
                return false
            }
            return id == fixture.focusedUUID && file == fixture.connectionsFile
        }

        guard let aiChat = store.state.windows[id: fixture.focusedUUID]?.window.inspector.aiChat else {
            XCTFail("Missing focused window AI chat state")
            return
        }

        assertUnconnectedCurrentContextContract(
            aiChat,
            expectedSummaryTitle: "Documents · 1 selected",
            expectedBanner: .init(
                title: "Connect an AI provider",
                detail: "Set up a provider in Settings to chat with this context.",
                fixLabel: "Open Settings",
            ),
        )
    }

    private func assertUnconnectedCurrentContextContract(
        _ state: AiChatFeature.State,
        expectedSummaryTitle: String,
        expectedBanner: AiChatConnectionMetadata,
    ) {
        XCTAssertEqual(state.currentContextSummaryDisplayModel.title, expectedSummaryTitle)
        XCTAssertEqual(state.skeletonDisplayModel.headerTitle, "Chat")
        XCTAssertEqual(state.skeletonDisplayModel.currentContext.title, expectedSummaryTitle)
        XCTAssertEqual(state.chatInputDisplayModel.placeholder, "Ask anything…")

        guard case let .unconnected(connection, summary) = state.surfaceState else {
            XCTFail("Expected provider-missing unconnected surface state")
            return
        }

        XCTAssertEqual(connection, expectedBanner)
        XCTAssertEqual(summary.title, expectedSummaryTitle)
        XCTAssertEqual(state.connectionState, .unconnected(expectedBanner))
        XCTAssertFalse(state.canSubmit)
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)

        guard case let .unconnected(skeletonConnection) = state.skeletonDisplayModel.surface else {
            XCTFail("Expected provider-missing skeleton unconnected surface")
            return
        }

        XCTAssertEqual(skeletonConnection, expectedBanner)
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

        let connectionsFile = AIConnectionsFile.empty()

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(
            content: focusedWindow.content,
            sessionID: AiChatSessionID(rawValue: sessionUUID),
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
