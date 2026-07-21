import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerWindowInspectorChatRoutingTests: XCTestCase {
    func testShowChatHistoryOpensClosedInspectorWithCurrentContext() async {
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

        let connectionsFile = AIConnectionsFile.empty()
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000000"),
            connectionsFile: connectionsFile,
        )

        await store.send(.request(.showChatHistory))
        await assertOpenChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: connectionsFile)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: connectionsFile)
        await store.receive(\.inspector.aiChat.backToSessionsTapped)

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Documents · 1 selected")
    }

    func testOpenInspectorCommandsSwitchDestinationWithoutClosingOrFreshSetup() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000061")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .chat
        initialState.inspector.aiChat.sessionID = sessionID
        initialState.inspector.aiChat.sessionStatus = .active
        initialState.inspector.aiChat.draftText = "Preserved draft"

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000062"),
            connectionsFile: .empty(),
        )
        // store.exhaustivity = .off: inspector와 AiChat의 목적지 전환 action만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.showChatHistory))
        await store.receive(\.inspector.showChatHistoryRequested)
        await store.receive(\.inspector.aiChat.backToSessionsTapped)

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .sessions)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Preserved draft")

        await store.send(.request(.newChat))
        await store.receive(\.inspector.newChatRequested)
        await store.receive(\.inspector.aiChat.prepareUnpersistedNewChat)

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)
        XCTAssertNotEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertTrue(store.state.inspector.aiChat.draftText.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
    }

    func testOpenInspectorCommandsCloseMatchingDestination() async {
        var newChatState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        newChatState.inspector.inspectorVisible = true
        newChatState.inspector.inspectorPaneExists = true
        newChatState.inspector.activeMode = .chat
        newChatState.inspector.aiChat.mode = .chat

        let newChatStore = makeStore(
            initialState: newChatState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000063"),
            connectionsFile: .empty(),
        )
        // store.exhaustivity = .off: 동일 목적지 command의 inspector 닫기 action만 선별 검증한다.
        newChatStore.exhaustivity = .off

        await newChatStore.send(.request(.newChat))
        await newChatStore.receive(\.inspector.closeChat)
        XCTAssertFalse(newChatStore.state.inspector.inspectorVisible)

        var historyState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        historyState.inspector.inspectorVisible = true
        historyState.inspector.inspectorPaneExists = true
        historyState.inspector.activeMode = .chat
        historyState.inspector.aiChat.mode = .sessions

        let historyStore = makeStore(
            initialState: historyState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000064"),
            connectionsFile: .empty(),
        )
        // store.exhaustivity = .off: 동일 목적지 command의 inspector 닫기 action만 선별 검증한다.
        historyStore.exhaustivity = .off

        await historyStore.send(.request(.showChatHistory))
        await historyStore.receive(\.inspector.closeChat)
        XCTAssertFalse(historyStore.state.inspector.inspectorVisible)

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: historyStore.state.content)
        await historyStore.send(.request(.newChat))
        await assertOpenNewChat(
            on: historyStore,
            expectedSetup: expectedSetup,
            expectedConnectionsFile: .empty(),
        )
        await assertAiChatSetup(on: historyStore, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: historyStore, expectedFile: .empty())
        await historyStore.receive(\.inspector.aiChat.prepareUnpersistedNewChat)
        await historyStore.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = true
        }

        XCTAssertTrue(historyStore.state.inspector.inspectorVisible)
        XCTAssertEqual(historyStore.state.inspector.aiChat.mode, .chat)

        await historyStore.send(.inspector(.aiChat(.sessionsAppeared)))
        XCTAssertEqual(historyStore.state.inspector.aiChat.mode, .chat)
    }

    func testRepeatedPendingNewChatCommandCancelsInspectorOpen() async throws {
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents"),
            gate: gate,
        )

        await store.send(.request(.newChat))
        let pendingOpen = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(pendingOpen.destination, .newChat)
        await gate.waitForPendingLoadCount(1)

        await store.send(.request(.newChat))
        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)

        await gate.resumeNext(with: .empty())
        await store.finish()
        XCTAssertFalse(store.state.inspector.inspectorVisible)
    }

    func testDifferentPendingChatCommandReplacesInspectorDestination() async throws {
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents"),
            gate: gate,
        )

        await store.send(.request(.newChat))
        let firstPendingOpen = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(firstPendingOpen.destination, .newChat)
        await gate.waitForPendingLoadCount(1)

        await store.send(.request(.showChatHistory))
        let replacementOpen = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(replacementOpen.destination, .chatHistory)
        XCTAssertNotEqual(replacementOpen.requestID, firstPendingOpen.requestID)
        await gate.waitForPendingLoadCount(2)

        var staleSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: store.state.content)
        staleSetup.mode = .chat
        await store.send(.internal(.aiChatNewChatInspectorOpenLoaded(
            requestID: firstPendingOpen.requestID,
            setup: staleSetup,
            connectionsFile: .empty(),
        )))
        XCTAssertEqual(store.state.pendingAiChatInspectorOpen, replacementOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)

        await gate.resumeNext(with: .empty())
        await gate.resumeNext(with: .empty())
        await store.receive { action in
            guard case let .internal(.aiChatHistoryInspectorOpenLoaded(requestID, _, _)) = action else {
                return false
            }
            return requestID == replacementOpen.requestID
        }
        await store.receive(\.inspector.openChatHistory)

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .sessions)
    }

    func testSamePendingChatCommandOnDifferentActiveTabReplacesOpen() async throws {
        let secondTabID = ContentTabID()
        let secondAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Downloads")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let firstTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.contentTabs.tabs.append(ContentTabItem(
            id: secondTabID,
            page: .directory,
            anchor: secondAnchor,
            isPinned: false,
            title: "Downloads",
            iconName: "folder",
        ))
        initialState.tabContentStates[secondTabID] = FileManagerContentFeature.State.initialContent(
            for: secondAnchor,
            inheritingWindowContextFrom: initialState.content,
        )
        initialState.tabInspectorStates[secondTabID] = .init()

        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(initialState: initialState, gate: gate)

        await store.send(.request(.newChat))
        let firstPendingOpen = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(firstPendingOpen.tabID, firstTabID)
        await gate.waitForPendingLoadCount(1)

        await store.send(.contentTabs(.setCurrent(secondTabID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, secondTabID)

        await store.send(.request(.newChat))
        let replacementOpen = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(replacementOpen.destination, .newChat)
        XCTAssertEqual(replacementOpen.tabID, secondTabID)
        XCTAssertNotEqual(replacementOpen.requestID, firstPendingOpen.requestID)
        await gate.waitForPendingLoadCount(2)

        await gate.resumeNext(with: .empty())
        await gate.resumeNext(with: .empty())
        await store.receive { action in
            guard case let .internal(.aiChatNewChatInspectorOpenLoaded(requestID, _, _)) = action else {
                return false
            }
            return requestID == replacementOpen.requestID
        }
        await store.receive(\.inspector.openNewChat)

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(store.state.contentTabs.activeTabID, secondTabID)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    func testToolbarSparklesWithoutConfiguredProviderShowsSettingsGate() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000030")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: .empty())

        await store.send(.content(.view(.newChatTapped)))
        await store.receive(\.content.delegate.newChatRequested)
        await store.receive(\.request.newChat)
        await assertOpenNewChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: .empty())
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: .empty())
        await store.receive(\.inspector.aiChat.prepareUnpersistedNewChat)
        await store.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = true
        }

        assertUnconnectedCurrentContextContract(
            store.state.inspector.aiChat,
            expectedSummaryTitle: "Documents",
            expectedBanner: .init(
                title: "Connect an AI provider",
                detail: "Set up a provider in Settings to chat with this context.",
                fixLabel: "Open Settings",
            ),
        )
        XCTAssertTrue(store.state.inspector.aiChat.catalogRows.isEmpty)
        XCTAssertNil(store.state.inspector.aiChat.selectedModelHandle)
        XCTAssertFalse(store.state.inspector.aiChat.canSubmit)
        XCTAssertEqual(store.state.inspector.aiChat.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings",
        )))
    }

    func testAiChatOpenSettingsDelegateRoutesToWindowDelegate() async {
        let store = TestStore(initialState: FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")) {
            FileManagerFeature()
        }

        await store.send(.inspector(.aiChat(.delegate(.openAISettings))))
        await store.receive(\.inspector.delegate.openAISettings)
        await store.receive(\.delegate.openAISettings)
    }

    func testAiConnectionUpdateRefreshesOpenInspectorChatWithoutReopening() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000031")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: .empty())

        await store.send(.request(.showChatHistory))
        await assertOpenChat(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
            expectedConnectionsFile: .empty(),
        )
        await assertAiChatSetup(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
        )
        await assertProviderConnectionsUpdated(on: store, expectedFile: .empty())
        await store.send(.inspector(.setInspectorPaneExists(true))) {
            $0.inspector.inspectorPaneExists = true
        }

        let connectedFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])

        await store.send(.aiConnectionsFileUpdated(connectedFile))
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)

        XCTAssertNil(store.state.inspector.aiChat.sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Documents")
    }

    func testAiConnectionUpdateKeepsSelectorOpenAndFallsBackWhenSelectedProviderDisappears() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000032")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let initialFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
            .testFixture(provider: .anthropic, authMethod: .apiKey),
        ])
        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: initialFile)

        await store.send(.request(.showChatHistory))
        await assertOpenChat(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
            expectedConnectionsFile: initialFile,
        )
        await assertAiChatSetup(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
        )
        await assertProviderConnectionsUpdated(on: store, expectedFile: initialFile)
        await store.send(.inspector(.setInspectorPaneExists(true))) {
            $0.inspector.inspectorPaneExists = true
        }
        await store.send(.inspector(.aiChat(.modelSelectorTapped))) {
            $0.inspector.aiChat.isModelSelectorPresented = true
        }

        let fallbackFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .anthropic, authMethod: .apiKey, state: .connected),
            .testFixture(provider: .openai, authMethod: .apiKey, state: .connectionFailed),
        ])

        await store.send(.aiConnectionsFileUpdated(fallbackFile))
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)

        XCTAssertTrue(store.state.inspector.aiChat.isModelSelectorPresented)
    }

    func testAiConnectionUpdateToEmptyCatalogShowsSettingsGateWithoutReopening() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000033")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let initialFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .openai, providers: [
            .testFixture(provider: .openai, authMethod: .apiKey),
        ])
        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: initialFile)

        await store.send(.request(.showChatHistory))
        await assertOpenChat(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
            expectedConnectionsFile: initialFile,
        )
        await assertAiChatSetup(
            on: store,
            expectedSetup: FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content),
        )
        await assertProviderConnectionsUpdated(on: store, expectedFile: initialFile)
        await store.send(.inspector(.setInspectorPaneExists(true))) {
            $0.inspector.inspectorPaneExists = true
        }

        await store.send(.aiConnectionsFileUpdated(.empty()))
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)

        XCTAssertNil(store.state.inspector.aiChat.sessionID)
    }

    func testShowChatHistoryLoadsCurrentConnectionsSnapshotAtOpenTime() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000040")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let currentConnectionsFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .anthropic, providers: [
            .testFixture(provider: .anthropic, authMethod: .apiKey),
        ])
        let anthropicModel = AiProviderModel(
            id: AiModelHandle(provider: .anthropic, rawValue: "claude-sonnet-4-20250514"),
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            providerDisplayName: ProviderDescriptor.descriptor(for: .anthropic)?.displayName ?? "Anthropic",
            thinkingCapability: .unknown(reason: .init(message: "Thinking capability metadata is not loaded yet.")),
            unavailableReason: nil,
        )
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)
        let store = makeStore(
            initialState: initialState,
            uuid: fixedUUID,
            connectionsFile: currentConnectionsFile,
            aiProviderModels: [anthropicModel],
        )

        await store.send(.request(.showChatHistory))
        await assertOpenChat(
            on: store,
            expectedSetup: expectedSetup,
            expectedConnectionsFile: currentConnectionsFile,
        )
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: currentConnectionsFile)
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoading(_, provider, _))) = action else { return false }
            return provider == .anthropic
        }
        await store.receive { action in
            guard case let .inspector(.aiChat(.modelListLoaded(_, provider, models))) = action else { return false }
            return provider == .anthropic && models == [anthropicModel]
        }

        XCTAssertEqual(store.state.inspector.aiChat.modelListProvider, .anthropic)
        XCTAssertEqual(store.state.inspector.aiChat.catalogRows.map(\.handle), [anthropicModel.id])
        XCTAssertNil(store.state.inspector.aiChat.selectedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.connectionState, .connected)
    }

    func testShowChatHistoryFallsBackToEmptySnapshotWhenLoadFails() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000041")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(fixedUUID)
            $0.aiConnectionsFileClient.load = { throw NSError(domain: "test", code: -1) }
        }
        // store.exhaustivity = .off: 연결 파일 load 실패 이후 목적지와 fallback 상태만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.request(.showChatHistory))
        await assertOpenChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: .empty())
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: .empty())

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertTrue(store.state.inspector.aiChat.catalogRows.isEmpty)
        XCTAssertNil(store.state.inspector.aiChat.selectedModelHandle)
    }

    func testInspectorCloseChatActionHidesPaneWithoutTearingDownChat() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000050")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.sessionID = sessionID
        initialState.inspector.aiChat.sessionStatus = .active

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.inspector(.closeChat)) {
            $0.inspector.inspectorVisible = false
        }

        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.sessionStatus, .active)
    }

    func testShowChatHistoryReopensWithoutRetainingClosedChatSession() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000051")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .chat
        initialState.inspector.aiChat.sessionID = sessionID
        initialState.inspector.aiChat.sessionStatus = .active

        let store = makeStore(
            initialState: initialState,
            uuid: sessionID.rawValue,
            connectionsFile: .empty(),
        )

        await store.send(.inspector(.closeChat)) {
            $0.inspector.inspectorVisible = false
        }

        await store.send(.request(.showChatHistory))
        await store.receive { action in
            guard case let .inspector(.openChatHistory(setup, connectionsFile)) = action else { return false }
            return setup.mode == .sessions
                && setup.sessionID == nil
                && connectionsFile == .empty()
        }
        await store.receive(\.inspector.aiChat.setup)
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)

        XCTAssertEqual(store.state.inspector.aiChat.mode, .sessions)
        XCTAssertNil(store.state.inspector.aiChat.sessionID)
    }

    func testToolbarSparklesOpensAndClosesNewChat() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000010")
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]

        let connectionsFile = AIConnectionsFile.empty()
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: connectionsFile)

        await store.send(.content(.view(.newChatTapped)))
        await store.receive(\.content.delegate.newChatRequested)
        await store.receive(\.request.newChat)
        await assertOpenNewChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: connectionsFile)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: connectionsFile)
        await store.receive(\.inspector.aiChat.prepareUnpersistedNewChat)
        await store.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = true
        }

        assertUnconnectedCurrentContextContract(
            store.state.inspector.aiChat,
            expectedSummaryTitle: "Documents · 1 selected",
            expectedBanner: .init(
                title: "Connect an AI provider",
                detail: "Set up a provider in Settings to chat with this context.",
                fixLabel: "Open Settings",
            ),
        )

        await store.send(.inspector(.setInspectorPaneExists(true))) {
            $0.inspector.inspectorPaneExists = true
        }

        await store.send(.content(.view(.newChatTapped)))
        await store.receive(\.content.delegate.newChatRequested)
        await store.receive(\.request.newChat)
        await store.receive(\.inspector.closeChat)

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.draftText.isEmpty)
    }

    func testSelectionStateChangesRouteIntoOpenAiChatContext() async {
        let firstEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        let secondEntry = makeEntry(name: "Notes.md", fullPath: "/Users/test/Documents/Notes.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [firstEntry, secondEntry]
        initialState.content.entryViewLayout.selectedIds = [firstEntry.id]

        let connectionsFile = AIConnectionsFile.empty()
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)
        var updatedContent = initialState.content
        updatedContent.entryViewLayout.selectedIds = [secondEntry.id]
        let rawUpdatedContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: updatedContent)
        let updatedReference = addingCurrentFolderOnlyMode(to: rawUpdatedContext.references[0])
        let updatedItem = AiChatContextItem(
            kind: rawUpdatedContext.items[0].kind,
            identifier: rawUpdatedContext.items[0].identifier,
            title: rawUpdatedContext.items[0].title,
            subtitle: rawUpdatedContext.items[0].subtitle,
            metadata: rawUpdatedContext.items[0].metadata,
            references: [updatedReference],
        )
        let updatedContext = AiChatCurrentContextSnapshot(
            summary: rawUpdatedContext.summary,
            references: [updatedReference],
            items: [updatedItem],
            attachments: rawUpdatedContext.attachments,
        )

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000040"),
            connectionsFile: connectionsFile,
        )

        await store.send(.request(.showChatHistory))
        await assertOpenChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: connectionsFile)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: connectionsFile)

        await store.send(.content(.entryViewLayout(.internal(.setSelectionState(
            ids: [secondEntry.id],
            lastSelectedId: secondEntry.id,
            rangeAnchorId: secondEntry.id,
            shouldScrollToSelection: false,
        ))))) {
            $0.content.entryViewLayout.selectedIds = [secondEntry.id]
            $0.content.entryViewLayout.lastSelectedId = secondEntry.id
            $0.content.entryViewLayout.rangeAnchorId = secondEntry.id
            $0.content.entryViewLayout.shouldScrollToSelection = false
        }
        await store.receive(\.content.entryViewLayout.delegate.selectionChanged)
        await store.receive { action in
            guard case let .content(.delegate(.currentContextChanged(snapshot))) = action else { return false }
            return snapshot == rawUpdatedContext
        }
        await store.receive(\.inspector.aiChat.currentContextChanged) {
            $0.inspector.aiChat.currentContext = updatedContext
        }
    }
}

private extension FileManagerWindowInspectorChatRoutingTests {
    private func assertConnectedCurrentContextSkeletonContract(
        _ state: AiChatFeature.State,
        expectedSummaryTitle: String,
        expectedModelTitle: String,
        expectedCanSubmit: Bool,
    ) {
        guard case let .empty(summary, selectedModel) = state.surfaceState else {
            XCTFail("Expected current-context chat to start with empty surface")
            return
        }

        XCTAssertEqual(summary.title, expectedSummaryTitle)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(selectedModel?.label.title, expectedModelTitle)
        XCTAssertEqual(state.currentContext.summary, expectedSummaryTitle)
        XCTAssertEqual(state.currentContextSummaryDisplayModel.title, expectedSummaryTitle)
        XCTAssertEqual(state.skeletonDisplayModel.headerTitle, "Chat")
        XCTAssertEqual(state.skeletonDisplayModel.currentContext.title, expectedSummaryTitle)
        XCTAssertEqual(state.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, expectedModelTitle)
        XCTAssertEqual(state.chatInputDisplayModel.canSubmit, expectedCanSubmit)
        XCTAssertEqual(state.canSubmit, expectedCanSubmit)
        XCTAssertTrue(state.transcriptHistory.isEmpty)
        XCTAssertTrue(state.draftText.isEmpty)

        guard case let .empty(emptyDisplay) = state.skeletonDisplayModel.surface else {
            XCTFail("Expected connected current-context skeleton empty surface")
            return
        }

        XCTAssertEqual(emptyDisplay.title, "Ask about this context")
        XCTAssertEqual(emptyDisplay.detail, "Send a message to start a contextual chat.")
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

    private func addingCurrentFolderOnlyMode(
        to reference: AiChatContextReference,
    ) -> AiChatContextReference {
        var metadata = reference.metadata
        metadata["folderStructureMode"] = "currentFolderOnly"
        return AiChatContextReference(
            kind: reference.kind,
            identifier: reference.identifier,
            title: reference.title,
            subtitle: reference.subtitle,
            metadata: metadata,
        )
    }

    private func makeStore(
        initialState: FileManagerFeature.State,
        uuid: UUID,
        connectionsFile: AIConnectionsFile,
        aiProviderModels: [AiProviderModel] = [],
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(uuid)
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, _ in
                aiProviderModels.filter { $0.provider == provider }
            })
        }
        // store.exhaustivity = .off: FileManager부터 AiChat까지의 통합 action 중 목적지 계약만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func makeDelayedConnectionsStore(
        initialState: FileManagerFeature.State,
        gate: AIConnectionsLoadGate,
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { await gate.load() }
            $0.aiChatSessionPersistenceClient.saveSession = { $0 }
        }
        // store.exhaustivity = .off: pending open의 destination/token 전환과 최종 표시만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func assertOpenNewChat(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
        expectedConnectionsFile: AIConnectionsFile,
    ) async {
        await store.receive { action in
            guard case let .internal(.aiChatNewChatInspectorOpenLoaded(_, setup, connectionsFile)) = action else {
                return false
            }
            return setup.mode == .chat
                && setup.currentContext == expectedSetup.currentContext
                && connectionsFile == expectedConnectionsFile
        }
        await store.receive { action in
            guard case let .inspector(.openNewChat(setup, connectionsFile)) = action else { return false }
            return setup.mode == .chat
                && setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && setup.lockedModelHandle == expectedSetup.lockedModelHandle
                && setup.lastExecutionFailure == expectedSetup.lastExecutionFailure
                && connectionsFile == expectedConnectionsFile
        }

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    private func assertOpenChat(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
        expectedConnectionsFile: AIConnectionsFile,
    ) async {
        await store.receive { action in
            guard case let .internal(.aiChatHistoryInspectorOpenLoaded(_, setup, connectionsFile)) = action else {
                return false
            }
            return setup.mode == .sessions
                && setup.currentContext == expectedSetup.currentContext
                && connectionsFile == expectedConnectionsFile
        }
        await store.receive { action in
            guard case let .inspector(.openChatHistory(setup, connectionsFile)) = action else { return false }
            return setup.sessionID == expectedSetup.sessionID
                && setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && setup.lockedModelHandle == expectedSetup.lockedModelHandle
                && setup.lastExecutionFailure == expectedSetup.lastExecutionFailure
                && connectionsFile == expectedConnectionsFile
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
        XCTAssertEqual(store.state.inspector.aiChat.catalogRows, expectedSetup.catalogRows)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, expectedSetup.selectedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, expectedSetup.lockedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lastExecutionFailure, expectedSetup.lastExecutionFailure)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .idle)
    }

    private func assertOpenChatRouting(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedSetup: AiChatSetupState,
        expectedConnectionsFile: AIConnectionsFile,
    ) async {
        await store.receive { action in
            guard case let .internal(.aiChatHistoryInspectorOpenLoaded(_, setup, connectionsFile)) = action else {
                return false
            }
            return setup.mode == .sessions
                && setup.currentContext == expectedSetup.currentContext
                && connectionsFile == expectedConnectionsFile
        }
        await store.receive { action in
            guard case let .inspector(.openChatHistory(setup, connectionsFile)) = action else { return false }
            return setup.currentContext == expectedSetup.currentContext
                && setup.catalogRows == expectedSetup.catalogRows
                && setup.selectedModelHandle == expectedSetup.selectedModelHandle
                && setup.lockedModelHandle == expectedSetup.lockedModelHandle
                && setup.lastExecutionFailure == expectedSetup.lastExecutionFailure
                && connectionsFile == expectedConnectionsFile
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
        XCTAssertEqual(store.state.inspector.aiChat.catalogRows, expectedSetup.catalogRows)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, expectedSetup.selectedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lockedModelHandle, expectedSetup.lockedModelHandle)
        XCTAssertEqual(store.state.inspector.aiChat.lastExecutionFailure, expectedSetup.lastExecutionFailure)
        XCTAssertEqual(store.state.inspector.aiChat.executionPhase, .idle)
    }

    private func assertProviderConnectionsUpdated(
        on store: TestStore<FileManagerFeature.State, FileManagerFeature.Action>,
        expectedFile: AIConnectionsFile,
    ) async {
        await store.receive { action in
            guard case let .inspector(.aiChat(.providerConnectionsUpdated(file))) = action else { return false }
            return file == expectedFile
        }
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
}

private actor AIConnectionsLoadGate {
    private var continuations: [CheckedContinuation<AIConnectionsFile, Never>] = []

    func load() async -> AIConnectionsFile {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForPendingLoadCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resumeNext(with connectionsFile: AIConnectionsFile) {
        continuations.removeFirst().resume(returning: connectionsFile)
    }
}
