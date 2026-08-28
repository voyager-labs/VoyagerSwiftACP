import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesAi
import VoyagerEntitiesAppPreferences
import VoyagerEntitiesEntry
import VoyagerFeaturesAiChat
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerWindowInspectorChatRoutingTests: XCTestCase {
    /// 닫힌 Inspector New Chat은 표시 전에 transient session identity를 준비한다.
    /// - 검증 내용: setup → transient 준비 → provider 갱신 → 표시 순서, exact ID, save 0회
    /// - 사전 조건: session이 없는 setup과 현재 context로 닫힌 Inspector를 연다.
    /// - 기대 결과: Inspector가 보이기 전에 deterministic ID와 untouched marker가 준비된다.
    func testClosedInspectorNewChatMaterializesTransientIdentityBeforeVisibility() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000088")
        let context = AiChatCurrentContextSnapshot(summary: "Selected files")
        let setup = AiChatSetupState(mode: .chat, currentContext: context)
        let saveCount = LockIsolated(0)
        let store = TestStore(initialState: FileManagerInspectorFeature.State()) {
            FileManagerInspectorFeature()
        } withDependencies: {
            $0.uuid = .constant(sessionID.rawValue)
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                saveCount.withValue { $0 += 1 }
                return snapshot
            }
        }

        await store.send(.openNewChat(setup, .empty()))
        await store.receive(\.aiChat.setup) { state in
            state.aiChat.mode = .chat
            state.aiChat.currentContext = context
        }
        await store.receive(\.aiChat.prepareUnpersistedNewChatWithContext) { state in
            state.aiChat.sessionID = sessionID
            state.aiChat.preparedTransientSessionID = sessionID
        }

        XCTAssertFalse(store.state.inspectorVisible)
        XCTAssertEqual(store.state.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.aiChat.preparedTransientSessionID, sessionID)
        XCTAssertTrue(store.state.aiChat.isUntouchedPreparedTransientNewChat)
        XCTAssertEqual(saveCount.value, 0)

        await store.receive(\.aiChat.providerConnectionsUpdated) { state in
            state.aiChat.providerConnectionSnapshot = .known([])
        }
        await store.receive(\.setInspectorVisible) { state in
            state.inspectorVisible = true
        }
        XCTAssertEqual(store.state.aiChat.sessionID, sessionID)
        XCTAssertEqual(saveCount.value, 0)
    }

    /// Inspector pending seed 완료 전 draft 변경은 late completion에 의해 지워지지 않는다.
    /// - 검증 내용: draft 보존, transient preparation 없음, pending 정리, save 0회
    /// - 사전 조건: Inspector New Chat seed가 model catalog를 기다리는 중이다.
    /// - 기대 결과: completion은 no-op이고 사용자 draft가 유지된다.
    func testPendingInspectorNewChatIgnoresLateCatalogAfterDraftMutation() async throws {
        try await assertPendingInspectorSeedMutationIsIgnored(.draft)
    }

    /// Inspector pending seed 완료 전 attachment 변경은 late completion에 의해 지워지지 않는다.
    /// - 검증 내용: attachment 보존, transient preparation 없음, pending 정리, save 0회
    /// - 사전 조건: Inspector New Chat seed가 model catalog를 기다리는 중이다.
    /// - 기대 결과: completion은 no-op이고 사용자 attachment가 유지된다.
    func testPendingInspectorNewChatIgnoresLateCatalogAfterAttachmentMutation() async throws {
        try await assertPendingInspectorSeedMutationIsIgnored(.attachment)
    }

    /// Inspector pending seed 완료 전 model 변경은 late completion에 의해 덮어써지지 않는다.
    /// - 검증 내용: explicit model 보존, transient preparation 없음, pending 정리, save 0회
    /// - 사전 조건: Inspector New Chat seed가 model catalog를 기다리는 중이다.
    /// - 기대 결과: completion은 no-op이고 사용자 model 선택이 유지된다.
    func testPendingInspectorNewChatIgnoresLateCatalogAfterModelMutation() async throws {
        try await assertPendingInspectorSeedMutationIsIgnored(.model)
    }

    /// Inspector pending seed 완료 전 thinking 변경은 late completion에 의해 덮어써지지 않는다.
    /// - 검증 내용: explicit thinking 보존, transient preparation 없음, pending 정리, save 0회
    /// - 사전 조건: Inspector New Chat seed가 model catalog를 기다리는 중이다.
    /// - 기대 결과: completion은 no-op이고 사용자 thinking 선택이 유지된다.
    func testPendingInspectorNewChatIgnoresLateCatalogAfterThinkingMutation() async throws {
        try await assertPendingInspectorSeedMutationIsIgnored(.thinking)
    }

    /// Inspector pending seed 완료 전 context 변경은 late completion에 의해 덮어써지지 않는다.
    /// - 검증 내용: exact transient ID와 사용자 context 보존, pending 정리, save 0회
    /// - 사전 조건: Inspector New Chat seed가 model catalog를 기다리는 중이다.
    /// - 기대 결과: completion은 no-op이고 사용자 context와 touched marker 의미가 유지된다.
    func testPendingInspectorNewChatIgnoresLateCatalogAfterContextMutation() async throws {
        try await assertPendingInspectorSeedMutationIsIgnored(.context)
    }

    func testClosedInspectorNewChatWaitsForCatalogThenUsesWindowLastWithoutSaving() async {
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: model.id,
            thinking: .effort(.high),
        )
        let connectionsFile: AIConnectionsFile = .testFixture(
            lastUsedProviderId: .openai,
            providers: [.testFixture(provider: .openai, authMethod: .apiKey)],
        )
        let saveCount = LockIsolated(0)
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000089"),
            connectionsFile: connectionsFile,
            aiProviderModels: [model],
            savedSessionCount: saveCount,
        )

        await store.send(.request(.newChat))
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  let seed = application.seed
            else {
                return false
            }
            return seed == AiChatNewChatSelectionSeed(
                modelHandle: model.id,
                selectedThinking: .effort(.high),
            )
        }

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, model.id)
        XCTAssertEqual(store.state.inspector.aiChat.selectedThinking, .effort(.high))
        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertNil(store.state.pendingAiChatNewChat)
        XCTAssertEqual(saveCount.value, 0)
    }

    /// 닫힌 Inspector의 stale seed race 뒤 첫 submit은 materialized identity를 그대로 사용한다.
    /// - 검증 내용: 표시 전 transient ID, 사용자 payload 보존, request/save 각 1회와 exact session ID
    /// - 사전 조건: model catalog가 pending인 동안 draft/context/attachment를 사용자가 변경한다.
    /// - 기대 결과: late completion은 payload를 덮어쓰지 않고 이후 유효 선택의 submit이 같은 ID로 시작된다.
    func testClosedInspectorPendingSeedMutationSubmitsWithMaterializedIdentityOnce() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-00000000009a")
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let connectionsFile: AIConnectionsFile = .testFixture(
            lastUsedProviderId: .openai,
            providers: [.testFixture(provider: .openai, authMethod: .apiKey)],
        )
        let modelLoadContinuation = LockIsolated<CheckedContinuation<[AiProviderModel], Error>?>(nil)
        let requests = LockIsolated<[AiChatRequest]>([])
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: model.id,
            thinking: .effort(.high),
        )
        let store: TestStore<FileManagerFeature.State, FileManagerFeature.Action> = TestStore(
            initialState: initialState,
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(sessionID.rawValue)
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in
                try await withCheckedThrowingContinuation { continuation in
                    modelLoadContinuation.setValue(continuation)
                }
            })
            $0.aiChatContextPartResolverClient = .live()
            $0.aiChatExecutionClient = AiChatExecutionClient { request in
                requests.withValue { $0.append(request) }
                return AsyncStream { _ in }
            }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSnapshots.withValue { $0.append(snapshot) }
                return snapshot
            }
        }
        // store.exhaustivity = .off: parent race의 identity/payload/request-start 경계만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.newChat))
        await store.receive(\.internal.aiChatNewChatInspectorOpenLoaded)
        await store.receive(\.inspector.openNewChat)
        await store.receive(\.inspector.aiChat.setup)
        await store.receive(\.inspector.aiChat.prepareUnpersistedNewChatWithContext)

        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.preparedTransientSessionID, sessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)

        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)
        while modelLoadContinuation.value == nil {
            await Task.yield()
        }
        await store.receive(\.inspector.setInspectorVisible)
        XCTAssertNotNil(store.state.pendingAiChatInspectorOpen)

        let userContext = AiChatCurrentContextSnapshot(summary: "User context")
        await store.send(.inspector(.aiChat(.draftTextChanged("User question"))))
        await store.send(.inspector(.aiChat(.currentContextChanged(userContext))))
        await store.send(.inspector(.aiChat(.attachmentPickerSelection(sessionID, [
            URL(fileURLWithPath: "/tmp/inspector-race.txt"),
        ]))))

        modelLoadContinuation.withValue { continuation in
            continuation?.resume(returning: [model])
            continuation = nil
        }
        await store.receive(\.inspector.aiChat.modelListLoaded)
        await store.receive(\.internal.aiChatNewChatDefaultsLoaded)
        await store.receive(\.internal.applyInspectorNewChatSeed)

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertNil(store.state.pendingAiChatNewChat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "User question")
        XCTAssertEqual(store.state.inspector.aiChat.currentContext, userContext)
        XCTAssertEqual(store.state.inspector.aiChat.addedAttachments.count, 1)
        XCTAssertNil(store.state.inspector.aiChat.preparedTransientSessionID)
        XCTAssertTrue(savedSnapshots.value.isEmpty)

        await store.send(.inspector(.aiChat(.selectedModelChanged(model.id))))
        await store.send(.inspector(.aiChat(.selectedThinkingChanged(.effort(.high)))))
        await store.send(.inspector(.aiChat(.submitTapped)))
        await store.receive(\.inspector.aiChat.requestContextResolved)
        await store.receive(\.inspector.aiChat.sessionSnapshotUpdated)

        let request = try XCTUnwrap(requests.value.first)
        let snapshot = try XCTUnwrap(savedSnapshots.value.first)
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertEqual(savedSnapshots.value.count, 1)
        XCTAssertEqual(request.context.sessionID, sessionID)
        XCTAssertEqual(request.context.currentContext, userContext)
        XCTAssertEqual(request.context.requestContext.addedAttachments.count, 1)
        XCTAssertEqual(request.context.selectedThinking, .effort(.high))
        let submittedMessage = AiChatMessage(
            role: .user,
            content: "User question",
            createdAtMs: 1_700_000_000_000,
        )
        XCTAssertEqual(request.messages.last, submittedMessage)
        XCTAssertEqual(snapshot.sessionID, sessionID)
        XCTAssertEqual(snapshot.transcriptHistory.last, submittedMessage)

        await store.send(.inspector(.aiChat(.cancelTapped)))
        await store.finish()
        XCTAssertEqual(savedSnapshots.value.count, 1)
    }

    /// 실제 toolbar New Chat은 저장된 대화가 있어도 새 transient session을 연다.
    /// - 검증 내용: `.content` wrapper, submit/final 저장, close 이후 새 session identity와 빈 transcript
    /// - 사전 조건: Directory Content Tab에서 연결된 model로 Inspector 대화를 완료한다.
    /// - 기대 결과: 명시적 New Chat 버튼은 저장된 session을 복원하지 않는다.
    func testActualToolbarFlowStartsNewChatAfterCompletedPersistedInspectorSession() async throws {
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let connectionsFile: AIConnectionsFile = .testFixture(
            lastUsedProviderId: .openai,
            providers: [.testFixture(provider: .openai, authMethod: .apiKey)],
        )
        let savedSnapshots = LockIsolated<[AiChatSessionSnapshot]>([])
        let loadedSessionIDs = LockIsolated<[AiChatSessionID]>([])
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: model.id,
            thinking: .effort(.high),
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.aiChatDefaultSettingsClient.load = { .default }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { _, _ in [model] })
            $0.aiChatContextPartResolverClient = .live()
            $0.aiChatExecutionClient = AiChatExecutionClient { request in
                AsyncStream { continuation in
                    continuation.yield(.started(context: request.context))
                    continuation.yield(.final(response: AiChatResponse(
                        context: request.context,
                        assistantMessage: AiChatMessage(role: .assistant, content: "Persisted answer"),
                        completedAtMs: 1_700_000_000_000,
                    )))
                    continuation.finish()
                }
            }
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { sessionID in
                    loadedSessionIDs.withValue { $0.append(sessionID) }
                    return savedSnapshots.value.last(where: { $0.sessionID == sessionID })
                },
                saveSession: { snapshot in
                    savedSnapshots.withValue { $0.append(snapshot) }
                    return snapshot
                },
                deleteSession: { _ in },
            )
        }
        // 실제 parent→child→persistence action 중 사용자 결과와 session identity만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.content(.view(.newChatTapped)))
        await store.receive(\.internal.applyInspectorNewChatSeed)

        let sessionID = try XCTUnwrap(store.state.inspector.aiChat.sessionID)
        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, model.id)

        await store.send(.inspector(.aiChat(.draftTextChanged("Persisted question"))))
        await store.send(.inspector(.aiChat(.submitTapped)))
        await store.receive { action in
            guard case let .inspector(.aiChat(.executionEvent(.final(response)))) = action else {
                return false
            }
            return response.context.sessionID == sessionID
        }
        await store.receive(\.inspector.aiChat.sessionSnapshotSaved)

        let completedTranscript = store.state.inspector.aiChat.transcriptHistory
        XCTAssertEqual(completedTranscript.map(\.content), ["Persisted question", "Persisted answer"])
        XCTAssertEqual(store.state.inspector.aiChat.sessionStatus, .active)

        await store.send(.inspector(.closeChat))
        XCTAssertFalse(store.state.inspector.inspectorVisible)

        await store.send(.content(.view(.newChatTapped)))
        await store.receive(\.request.newChat)
        await store.receive(\.internal.applyInspectorNewChatSeed)
        await store.finish()

        let newSessionID = try XCTUnwrap(store.state.inspector.aiChat.sessionID)
        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertNotEqual(newSessionID, sessionID)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
        XCTAssertTrue(loadedSessionIDs.value.isEmpty)
    }

    func testVisibleInspectorNewChatUsesWindowLastBeforePersistedDefaultWithoutSaving() async {
        let windowModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let persistedModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded([windowModel, persistedModel]),
        )
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: windowModel.id,
            thinking: .effort(.high),
        )
        let saveCount = LockIsolated(0)
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000090"),
            connectionsFile: .empty(),
            defaultSettings: makeDefaultSettings(model: persistedModel, thinking: .none),
            savedSessionCount: saveCount,
        )

        await store.send(.request(.newChat))
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  let seed = application.seed
            else {
                return false
            }
            return seed == AiChatNewChatSelectionSeed(
                modelHandle: windowModel.id,
                selectedThinking: .effort(.high),
            )
        }

        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, windowModel.id)
        XCTAssertEqual(store.state.inspector.aiChat.selectedThinking, .effort(.high))
        XCTAssertEqual(saveCount.value, 0)
    }

    /// OpenAI failure evidence가 Anthropic-only aggregate에 가려져도 window-last seed를 보존한다.
    func testVisibleInspectorNewChatPreservesWindowLastWhenProviderFailureIsExcludedFromAggregateCatalog() async {
        let windowModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let aggregateModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        let failure = AiModelListFailure(message: "OpenAI model list request failed.")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded([aggregateModel]),
            modelListProviderOrder: [.openai, .anthropic],
            modelListLoadedModelsByProvider: [.anthropic: [aggregateModel]],
            modelListFailedProviders: [.openai: failure],
            providerConnectionSnapshot: .known([.openai, .anthropic]),
        )
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: windowModel.id,
            thinking: .effort(.high),
        )
        let saveCount = LockIsolated(0)
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-0000000000A1"),
            connectionsFile: .empty(),
            defaultSettings: makeDefaultSettings(model: aggregateModel, thinking: .none),
            savedSessionCount: saveCount,
        )

        await store.send(.request(.newChat))
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action else {
                return false
            }
            return application.seed == AiChatNewChatSelectionSeed(
                modelHandle: windowModel.id,
                selectedThinking: .effort(.high),
            )
        }

        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, windowModel.id)
        XCTAssertEqual(store.state.inspector.aiChat.selectedThinking, .effort(.high))
        XCTAssertNil(store.state.pendingAiChatNewChat)
        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(saveCount.value, 0)
    }

    func testInspectorHeaderFallsBackToPersistedModelAndDropsIncompatibleThinking() async {
        let invalidWindowModel = makeAiModel(
            provider: .openai,
            rawValue: "missing",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let persistedModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded([persistedModel]),
            modelListLoadedModelsByProvider: [
                .openai: [],
                .anthropic: [persistedModel],
            ],
        )
        initialState.lastExplicitAiChatSelection = FileManagerAiChatSelection(
            modelHandle: invalidWindowModel.id,
            thinking: .effort(.high),
        )
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000091"),
            connectionsFile: .empty(),
            defaultSettings: makeDefaultSettings(model: persistedModel, thinking: .effort("high")),
        )

        await store.send(.inspector(.sessionHeaderNewChatTapped))
        await store.receive(\.inspector.delegate.newChatRequested)
        await store.receive(\.request.newChat)
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  let seed = application.seed
            else {
                return false
            }
            return seed.modelHandle == persistedModel.id && seed.selectedThinking == nil
        }

        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, persistedModel.id)
        XCTAssertNil(store.state.inspector.aiChat.selectedThinking)
    }

    func testContentHistoryNewChatUsesLatestDefaultOnceWithoutMutatingCurrentDraft() async throws {
        let firstModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let nextModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        let firstSettings = makeDefaultSettings(model: firstModel, thinking: .providerDefault)
        let nextSettings = makeDefaultSettings(model: nextModel, thinking: .none)
        let settings = LockIsolated(firstSettings)
        let saveCount = LockIsolated(0)
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(sessionID: "history")
        initialState.content.aiChat = AiChatFeature.State(
            mode: .sessions,
            sessionID: makeSessionID("00000000-0000-0000-0000-000000000092"),
            draftText: "Existing draft",
            modelListState: .loaded([firstModel, nextModel]),
            selectedModelHandle: firstModel.id,
            selectedThinking: .effort(.high),
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiChatDefaultSettingsClient.load = { settings.value }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                saveCount.withValue { $0 += 1 }
                return snapshot
            }
        }
        // store.exhaustivity = .off: Content에서 window seed pipeline과 durable save 경계만 선별 검증한다.
        store.exhaustivity = .off

        settings.withValue { $0 = nextSettings }
        XCTAssertEqual(store.state.content.aiChat.draftText, "Existing draft")
        XCTAssertEqual(store.state.content.aiChat.selectedModelHandle, firstModel.id)

        await store.send(.content(.view(.aiChatNewChatTapped)))
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.durableNewChatRequested)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .internal(.applyContentNewChatSeed(application)) = action,
                  let seed = application.seed
            else { return false }
            return seed.modelHandle == nextModel.id && seed.selectedThinking == nil
        }
        await store.receive(\.content.aiChat.newChatCreated)

        XCTAssertEqual(store.state.content.aiChat.selectedModelHandle, nextModel.id)
        XCTAssertNil(store.state.content.aiChat.selectedThinking)
        XCTAssertTrue(store.state.content.aiChat.draftText.isEmpty)
        XCTAssertEqual(saveCount.value, 1)
    }

    func testPendingContentNewChatIgnoresLateCatalogAfterSessionNavigation() async throws {
        let model = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        let requestID = makeUUID("00000000-0000-0000-0000-000000000094")
        let originalSessionID = makeSessionID("00000000-0000-0000-0000-000000000095")
        let navigatedSessionID = makeSessionID("00000000-0000-0000-0000-000000000096")
        let defaultSettings = makeDefaultSettings(model: model, thinking: .none)
        let saveCount = LockIsolated(0)
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.contentTabs.tabs[id: activeTabID]?.anchor = .aiChat(
            sessionID: originalSessionID.rawValue.uuidString,
        )
        initialState.content.aiChat = AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(selectedSessionID: originalSessionID),
            sessionID: originalSessionID,
            modelListState: .loading,
            modelListRequestID: requestID,
            modelListProviderOrder: [.anthropic],
            modelListPendingProviders: [.anthropic],
        )
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiChatDefaultSettingsClient.load = { defaultSettings }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                saveCount.withValue { $0 += 1 }
                return snapshot
            }
        }
        // store.exhaustivity = .off: pending durable seed와 session navigation provenance만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.content(.view(.aiChatNewChatTapped)))
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.durableNewChatRequested)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.internal.aiChatNewChatDefaultsLoaded)

        await store.send(.content(.aiChat(.showSessionsForChat(navigatedSessionID))))
        await store.send(.content(.aiChat(.modelListLoaded(
            requestID: requestID,
            provider: .anthropic,
            models: [model],
        ))))

        XCTAssertEqual(store.state.content.aiChat.sessionID, navigatedSessionID)
        XCTAssertEqual(store.state.content.aiChat.sessionList.selectedSessionID, navigatedSessionID)
        XCTAssertEqual(store.state.content.aiChat.mode, .sessions)
        XCTAssertEqual(saveCount.value, 0)
    }

    func testFinalContentSeedApplicationRevalidatesActiveAnchorBeforeChildMutation() async throws {
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000097")
        let saveCount = LockIsolated(0)
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        let expectedAnchor = ContentTabPageAnchor.aiChat(sessionID: sessionID.rawValue.uuidString)
        initialState.contentTabs.tabs[id: activeTabID]?.anchor = expectedAnchor
        initialState.content.aiChat = AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(selectedSessionID: sessionID),
            sessionID: sessionID,
            modelListState: .loaded([model]),
        )
        let provenance = initialState.content.aiChat.newChatPreparationProvenance
        let seed = AiChatNewChatSelectionSeed(modelHandle: model.id, selectedThinking: .effort(.high))
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                saveCount.withValue { $0 += 1 }
                return snapshot
            }
        }
        // store.exhaustivity = .off: final parent gate의 tab/anchor provenance만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.contentTabs(.updateActivePageAnchor(activeTabID, .homeDefault)))
        await store.send(.internal(.applyContentNewChatSeed(.init(
            tabID: activeTabID,
            expectedAnchor: expectedAnchor,
            sessionID: nil,
            provenance: provenance,
            seed: seed,
        ))))

        XCTAssertEqual(store.state.contentTabs.tabs[id: activeTabID]?.anchor, .homeDefault)
        XCTAssertEqual(store.state.content.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.content.aiChat.sessionList.selectedSessionID, sessionID)
        XCTAssertEqual(saveCount.value, 0)
    }

    func testPendingInspectorNewChatIgnoresStaleCatalogCompletion() async throws {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000093")
        let staleRequestID = makeUUID("00000000-0000-0000-0000-000000000094")
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loading,
            modelListRequestID: requestID,
            modelListProvider: .openai,
            modelListProviderOrder: [.openai],
            modelListPendingProviders: [.openai],
        )
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000095"),
            connectionsFile: .empty(),
            defaultSettings: makeDefaultSettings(model: model, thinking: .effort("high")),
        )

        await store.send(.request(.newChat))
        let transientSessionID = try XCTUnwrap(store.state.inspector.aiChat.sessionID)
        let pending = try XCTUnwrap(store.state.pendingAiChatNewChat)
        await store.send(.inspector(.aiChat(.modelListLoaded(
            requestID: staleRequestID,
            provider: .openai,
            models: [model],
        ))))
        XCTAssertEqual(store.state.pendingAiChatNewChat?.requestID, pending.requestID)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, transientSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.preparedTransientSessionID, transientSessionID)

        await store.send(.inspector(.aiChat(.modelListLoaded(
            requestID: requestID,
            provider: .openai,
            models: [model],
        ))))
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  let seed = application.seed
            else {
                return false
            }
            return seed.modelHandle == model.id && seed.selectedThinking == .effort(.high)
        }

        XCTAssertNil(store.state.pendingAiChatNewChat)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, model.id)
    }

    private enum PendingInspectorSeedMutation {
        case draft
        case attachment
        case model
        case thinking
        case context
    }

    private struct PendingInspectorSeedMutationContext {
        let requestID: UUID
        let transientSessionID: AiChatSessionID
        let seededModel: AiProviderModel
        let alternateModel: AiProviderModel
    }

    private func assertPendingInspectorSeedMutationIsIgnored(
        _ mutation: PendingInspectorSeedMutation,
    ) async throws {
        let requestID = makeUUID("00000000-0000-0000-0000-000000000098")
        let seededModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: nil),
        )
        let alternateModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        var aiChat = AiChatFeature.State(
            mode: .sessions,
            modelListState: .loaded([seededModel, alternateModel]),
            selectedModelHandle: seededModel.id,
            selectedThinking: .effort(.high),
        )
        aiChat.modelListState = .loading
        aiChat.modelListRequestID = requestID
        aiChat.modelListProvider = .openai
        aiChat.modelListProviderOrder = [.openai]
        aiChat.modelListPendingProviders = [.openai]

        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat = aiChat
        let saveCount = LockIsolated(0)
        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000099"),
            connectionsFile: .empty(),
            defaultSettings: makeDefaultSettings(model: seededModel, thinking: .effort("high")),
            savedSessionCount: saveCount,
        )
        // store.exhaustivity = .off: mutation provenance와 late completion no-op만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.newChat))
        let transientSessionID = try XCTUnwrap(store.state.inspector.aiChat.sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.preparedTransientSessionID, transientSessionID)
        await store.receive(\.internal.aiChatNewChatDefaultsLoaded)
        let context = PendingInspectorSeedMutationContext(
            requestID: requestID,
            transientSessionID: transientSessionID,
            seededModel: seededModel,
            alternateModel: alternateModel,
        )

        await sendPendingInspectorSeedMutation(mutation, to: store, context: context)
        await completePendingInspectorSeedMutation(mutation, to: store, context: context)
        await store.finish()

        assertPendingInspectorSeedMutation(mutation, state: store.state.inspector.aiChat, context: context)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, transientSessionID)
        XCTAssertNil(store.state.inspector.aiChat.preparedTransientSessionID)
        XCTAssertNil(store.state.pendingAiChatNewChat)
        XCTAssertEqual(saveCount.value, 0)
    }

    private func sendPendingInspectorSeedMutation(
        _ mutation: PendingInspectorSeedMutation,
        to store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        context: PendingInspectorSeedMutationContext,
    ) async {
        switch mutation {
        case .draft:
            await store.send(.inspector(.aiChat(.draftTextChanged("User draft"))))
        case .attachment:
            await store.send(.inspector(.aiChat(.attachmentPickerSelection(context.transientSessionID, [
                URL(fileURLWithPath: "/tmp/inspector-pending.txt"),
            ]))))
        case .model:
            await sendPendingInspectorModelSelection(
                alternateModelID: context.alternateModel.id,
                to: store,
                context: context,
            )
        case .thinking:
            await sendPendingInspectorThinkingSelection(to: store, context: context)
        case .context:
            await store.send(.inspector(.aiChat(.currentContextChanged(.init(summary: "User context")))))
        }
    }

    private func sendPendingInspectorModelSelection(
        alternateModelID: AiModelHandle,
        to store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        context: PendingInspectorSeedMutationContext,
    ) async {
        await sendPendingInspectorModelList(to: store, context: context)
        await store.send(.inspector(.aiChat(.selectedModelChanged(alternateModelID))))
    }

    private func sendPendingInspectorThinkingSelection(
        to store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        context: PendingInspectorSeedMutationContext,
    ) async {
        await sendPendingInspectorModelList(to: store, context: context)
        await store.send(.inspector(.aiChat(.selectedModelChanged(context.seededModel.id))))
        await store.send(.inspector(.aiChat(.selectedThinkingChanged(.effort(.low)))))
    }

    private func completePendingInspectorSeedMutation(
        _ mutation: PendingInspectorSeedMutation,
        to store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        context: PendingInspectorSeedMutationContext,
    ) async {
        switch mutation {
        case .model, .thinking:
            break
        case .draft, .attachment, .context:
            await sendPendingInspectorModelList(to: store, context: context)
        }
    }

    private func sendPendingInspectorModelList(
        to store: TestStore<FileManagerFeature.State, FileManagerWindowAction>,
        context: PendingInspectorSeedMutationContext,
    ) async {
        await store.send(.inspector(.aiChat(.modelListLoaded(
            requestID: context.requestID,
            provider: .openai,
            models: [context.seededModel, context.alternateModel],
        ))))
    }

    private func assertPendingInspectorSeedMutation(
        _ mutation: PendingInspectorSeedMutation,
        state: AiChatFeature.State,
        context: PendingInspectorSeedMutationContext,
    ) {
        switch mutation {
        case .draft:
            XCTAssertEqual(state.draftText, "User draft")
        case .attachment:
            XCTAssertEqual(state.addedAttachments.count, 1)
        case .model:
            XCTAssertEqual(state.selectedModelHandle, context.alternateModel.id)
        case .thinking:
            XCTAssertEqual(state.selectedModelHandle, context.seededModel.id)
            XCTAssertEqual(state.selectedThinking, .effort(.low))
        case .context:
            XCTAssertEqual(state.currentContext.summary, "User context")
        }
    }

    func testContentExplicitModelSelectionCapturesPostReductionNormalizedPair() async {
        let effortModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let noThinkingModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-haiku",
            thinkingCapability: .unsupported(reason: .init(message: "Unsupported")),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.aiChat = AiChatFeature.State(
            modelListState: .loaded([effortModel, noThinkingModel]),
            selectedModelHandle: effortModel.id,
            selectedThinking: .effort(.high),
        )
        guard let activeTabID = initialState.contentTabs.activeTabID else {
            return XCTFail("Expected active content tab")
        }
        let store = makeSelectionStore(initialState: initialState)

        await store.send(.tabContent(
            tabID: activeTabID,
            action: .aiChat(.selectedModelChanged(noThinkingModel.id)),
        ))

        XCTAssertEqual(store.state.content.aiChat.selectedModelHandle, noThinkingModel.id)
        XCTAssertNil(store.state.content.aiChat.selectedThinking)
        XCTAssertEqual(
            store.state.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: noThinkingModel.id, thinking: nil),
        )
    }

    func testInspectorExplicitThinkingSelectionUpdatesSharedWindowPair() async {
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.aiChat = AiChatFeature.State(
            modelListState: .loaded([model]),
            selectedModelHandle: model.id,
        )
        let store = makeSelectionStore(initialState: initialState)

        await store.send(.inspector(.aiChat(.selectedThinkingChanged(.effort(.high)))))

        XCTAssertEqual(
            store.state.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: model.id, thinking: .effort(.high)),
        )
    }

    func testPassiveAndBackgroundAiChatActionsDoNotReplaceExplicitSelection() async {
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.aiChat = AiChatFeature.State(
            modelListState: .loaded([model]),
            selectedModelHandle: model.id,
        )
        let expected = FileManagerAiChatSelection(modelHandle: model.id, thinking: .effort(.high))
        initialState.lastExplicitAiChatSelection = expected
        let store = makeSelectionStore(initialState: initialState)

        await store.send(.content(.aiChat(.setup(.init(
            catalogRows: [],
            selectedModelHandle: nil,
            selectedThinking: nil,
        )))))
        await store.send(.content(.aiChat(.providerConnectionsUpdated(.empty()))))
        await store.send(.content(.aiChat(.currentContextChanged(.init(summary: "Updated")))))
        await store.send(.content(.aiChat(.modelListLoadFailed(
            requestID: UUID(),
            provider: .openai,
            failure: .init(message: "Failed"),
        ))))
        await store.send(.backgroundAiChat(.selectedModelChanged(nil)))
        await store.send(.backgroundInspectorAiChat(.selectedThinkingChanged(nil)))

        XCTAssertEqual(store.state.lastExplicitAiChatSelection, expected)
    }

    func testFreshWindowsStartWithoutSelectionAndRemainIsolated() async {
        let openAIModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let anthropicModel = makeAiModel(
            provider: .anthropic,
            rawValue: "claude-sonnet",
            thinkingCapability: .effort(values: [.medium], defaultValue: nil),
        )
        var firstState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        firstState.content.aiChat = AiChatFeature.State(modelListState: .loaded([openAIModel]))
        var secondState = FileManagerFeature.State.makeInitial(path: "/Users/test/Downloads")
        secondState.content.aiChat = AiChatFeature.State(modelListState: .loaded([anthropicModel]))
        guard let firstTabID = firstState.contentTabs.activeTabID,
              let secondTabID = secondState.contentTabs.activeTabID
        else {
            return XCTFail("Expected active content tabs")
        }
        let firstStore = makeSelectionStore(initialState: firstState)
        let secondStore = makeSelectionStore(initialState: secondState)

        XCTAssertNil(firstStore.state.lastExplicitAiChatSelection)
        XCTAssertNil(secondStore.state.lastExplicitAiChatSelection)

        await firstStore.send(.tabContent(
            tabID: firstTabID,
            action: .aiChat(.selectedModelChanged(openAIModel.id)),
        ))
        await secondStore.send(.tabContent(
            tabID: secondTabID,
            action: .aiChat(.selectedModelChanged(anthropicModel.id)),
        ))

        XCTAssertEqual(
            firstStore.state.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: openAIModel.id, thinking: nil),
        )
        XCTAssertEqual(
            secondStore.state.lastExplicitAiChatSelection,
            FileManagerAiChatSelection(modelHandle: anthropicModel.id, thinking: nil),
        )
    }

    func testShowChatHistoryOpensClosedInspectorWithCurrentContext() async {
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.entries = [selectedEntry]
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

    func testSessionHeaderNewChatUsesLatestFileManagerContext() async {
        let preparedSessionID = makeSessionID("00000000-0000-0000-0000-000000000081")
        let previousState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let staleContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: previousState.content)
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Downloads")
        let expectedContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: initialState.content)
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .sessions
        initialState.inspector.aiChat.currentContext = staleContext

        let store = makeStore(
            initialState: initialState,
            uuid: preparedSessionID.rawValue,
            connectionsFile: .empty(),
        )

        await store.send(.inspector(.sessionHeaderNewChatTapped))
        await store.receive(\.inspector.delegate.newChatRequested)
        await store.receive(\.request.newChat)
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  application.seed == nil
            else {
                return false
            }
            return application.snapshot == expectedContext
        }

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, preparedSessionID)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Downloads")
        XCTAssertTrue(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
    }

    func testOpenInspectorCommandsRefreshCurrentContextWhenSwitchingToNewChat() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000061")
        let previousState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let staleContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: previousState.content)
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Downloads")
        let expectedContext = FileManagerAiChatContextAdapter.makeCurrentContextSnapshot(content: initialState.content)
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .chat
        initialState.inspector.aiChat.sessionID = sessionID
        initialState.inspector.aiChat.sessionStatus = .active
        initialState.inspector.aiChat.draftText = "Preserved draft"
        initialState.inspector.aiChat.currentContext = staleContext

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
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Documents")
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Preserved draft")

        await store.send(.request(.newChat))
        await store.receive { action in
            guard case let .internal(.applyInspectorNewChatSeed(application)) = action,
                  application.seed == nil
            else {
                return false
            }
            return application.snapshot == expectedContext
        }

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Downloads")
        XCTAssertNotEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertTrue(store.state.inspector.aiChat.draftText.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
    }

    func testNewChatFromRestoredInspectorChatClosesDisplayedNewChat() async {
        let restoredSessionID = makeSessionID("00000000-0000-0000-0000-000000000065")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .chat
        initialState.inspector.aiChat.sessionID = restoredSessionID
        initialState.inspector.aiChat.sessionStatus = .active
        initialState.inspector.aiChat.transcriptHistory = [AiChatMessage(role: .user, content: "Persisted question")]

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000066"),
            connectionsFile: .empty(),
        )

        await store.send(.request(.newChat))
        await store.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }

        XCTAssertEqual(store.state.inspector.aiChat.sessionID, restoredSessionID)
        XCTAssertFalse(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
        XCTAssertEqual(store.state.inspector.aiChat.transcriptHistory.count, 1)
    }

    func testNewChatFromPersistedEmptyInspectorChatClosesDisplayedNewChat() async {
        let persistedSessionID = makeSessionID("00000000-0000-0000-0000-000000000067")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .chat
        initialState.inspector.aiChat.sessionID = persistedSessionID
        initialState.inspector.aiChat.sessionStatus = .idle

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000068"),
            connectionsFile: .empty(),
        )

        await store.send(.request(.newChat))
        await store.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }

        XCTAssertEqual(store.state.inspector.aiChat.sessionID, persistedSessionID)
        XCTAssertFalse(store.state.inspector.aiChat.isUntouchedPreparedTransientNewChat)
    }

    func testInspectorTransientNewChatDoesNotCancelContentNewChatPersistence() async throws {
        let saveGate = AiChatSaveGate()
        let initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        let store = TestStore(
            initialState: initialState,
        ) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiChatSessionPersistenceClient.saveSession = { try await saveGate.save($0) }
        }
        // store.exhaustivity = .off: sibling AiChat effect의 cancellation 격리와 완료 action만 선별 검증한다.
        store.exhaustivity = .off

        await store.send(.tabContent(tabID: activeTabID, action: .aiChat(.newChatTapped)))
        await saveGate.waitForPendingSave()
        let contentSessionID = try XCTUnwrap(store.state.content.aiChat.sessionID)

        await store.send(.inspector(.aiChat(.prepareUnpersistedNewChat)))
        await saveGate.resumePendingSave()
        await store.receive { action in
            guard case let .tabContent(tabID, .aiChat(.newChatCreated(snapshot))) = action else { return false }
            return tabID == activeTabID && snapshot.sessionID == contentSessionID
        }

        let cancellationCount = await saveGate.cancellationCount
        XCTAssertEqual(cancellationCount, 0)
        XCTAssertEqual(store.state.content.aiChat.emptyDraftSessionID, contentSessionID)
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

        await newChatStore.send(.request(.newChat))
        await newChatStore.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }
        XCTAssertEqual(newChatStore.state.inspector.aiChat.mode, .chat)

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

        await historyStore.send(.request(.showChatHistory))
        await historyStore.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }
        XCTAssertEqual(historyStore.state.inspector.aiChat.mode, .sessions)
    }

    func testHistoryToNewChatSwitchIgnoresStaleSessionsLifecycle() async {
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true
        initialState.inspector.activeMode = .chat
        initialState.inspector.aiChat.mode = .sessions

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000069"),
            connectionsFile: .empty(),
        )

        await store.send(.request(.newChat))
        await store.receive(\.internal.applyInspectorNewChatSeed)

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)

        await store.send(.inspector(.aiChat(.sessionsAppeared)))
        XCTAssertEqual(store.state.inspector.aiChat.mode, .chat)
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

    func testReopenClosesAlreadyPresentedDurableChat() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000668")
        var initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        initialState.inspector.inspectorVisible = true
        initialState.inspector.inspectorPaneExists = true

        let store = makeStore(
            initialState: initialState,
            uuid: makeUUID("00000000-0000-0000-0000-000000000669"),
            connectionsFile: .empty(),
        )

        await store.send(.request(.reopenChat))
        await store.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }

        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.sessionStatus, .active)
    }

    func testRepeatedPendingReopenCancelsInspectorOpen() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000670")
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: makeClosedDurableInspectorState(sessionID: sessionID),
            gate: gate,
        )

        await store.send(.request(.reopenChat))
        XCTAssertEqual(store.state.pendingAiChatInspectorOpen?.destination, .reopenChat)
        await gate.waitForPendingLoadCount(1)

        await store.send(.request(.reopenChat))
        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)

        await gate.resumeNext(with: .empty())
        await store.finish()
        XCTAssertFalse(store.state.inspector.inspectorVisible)
    }

    func testReopenIgnoresCompletionWithStaleRequestID() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000647")
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: makeClosedDurableInspectorState(sessionID: sessionID),
            gate: gate,
        )

        await store.send(.request(.reopenChat))
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        await gate.waitForPendingLoadCount(1)
        let setup = AiChatSetupState(restoreSessionID: sessionID, mode: .chat)

        await store.send(.internal(.aiChatReopenInspectorOpenLoaded(
            requestID: UUID(),
            setup: setup,
            connectionsFile: .empty(),
        )))

        XCTAssertEqual(store.state.pendingAiChatInspectorOpen, pending)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        await gate.resumeNext(with: .empty())
        await store.finish()
    }

    func testReopenIgnoresCompletionAfterSessionIdentityChanges() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000649")
        let replacementID = makeSessionID("00000000-0000-0000-0000-000000000650")
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: makeClosedDurableInspectorState(sessionID: sessionID),
            gate: gate,
        )

        await store.send(.request(.reopenChat))
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        await gate.waitForPendingLoadCount(1)
        await store.send(.inspector(.aiChat(.showSessionsForChat(replacementID))))
        await store.send(.internal(.aiChatReopenInspectorOpenLoaded(
            requestID: pending.requestID,
            setup: .init(restoreSessionID: sessionID, mode: .chat),
            connectionsFile: .empty(),
        )))

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, replacementID)
        await gate.resumeNext(with: .empty())
        await store.finish()
    }

    func testReopenIgnoresCompletionAfterResumeProvenanceChanges() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000651")
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(
            initialState: makeClosedDurableInspectorState(sessionID: sessionID),
            gate: gate,
        )

        await store.send(.request(.reopenChat))
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        await gate.waitForPendingLoadCount(1)
        await store.send(.inspector(.aiChat(.draftTextChanged("Changed while reopening"))))
        await store.send(.internal(.aiChatReopenInspectorOpenLoaded(
            requestID: pending.requestID,
            setup: .init(restoreSessionID: sessionID, mode: .chat),
            connectionsFile: .empty(),
        )))

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Changed while reopening")
        await gate.resumeNext(with: .empty())
        await store.finish()
    }

    func testReopenIgnoresCompletionAfterActiveTabChanges() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000667")
        let secondTabID = ContentTabID()
        let secondAnchor = ContentTabPageAnchor.directory(path: "/Users/test/Downloads")
        var initialState = makeClosedDurableInspectorState(sessionID: sessionID)
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

        await store.send(.request(.reopenChat))
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        await gate.waitForPendingLoadCount(1)
        await store.send(.contentTabs(.setCurrent(secondTabID)))
        XCTAssertEqual(store.state.contentTabs.activeTabID, secondTabID)

        await store.send(.internal(.aiChatReopenInspectorOpenLoaded(
            requestID: pending.requestID,
            setup: .init(restoreSessionID: sessionID, mode: .chat),
            connectionsFile: .empty(),
        )))

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertNil(store.state.inspector.aiChat.sessionID)
        await gate.resumeNext(with: .empty())
        await store.finish()
    }

    /// 유휴 durable session의 미전송 draft는 Open Chat 재진입 뒤에도 유지된다.
    /// - 검증 내용: same-session fast path, persistence load 미호출, draft 보존
    /// - 사전 조건: lifecycle은 idle이고 active session에 미전송 draft가 남아 있다.
    /// - 기대 결과: 동일 session을 다시 표시하며 draft를 초기화하지 않는다.
    func testReopenPreservesIdleDraftWithoutPersistedRestore() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000671")
        let initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Idle draft reopen must not load persisted state")
                return nil
            }
        }
        // 동일 session의 미전송 draft 보존 결과만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.inspector(.aiChat(.draftTextChanged("Unsent draft"))))
        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Unsent draft")
    }

    /// 유휴 durable session의 미전송 attachment는 Open Chat 재진입 뒤에도 유지된다.
    /// - 검증 내용: same-session fast path, persistence load 미호출, attachment 보존
    /// - 사전 조건: lifecycle은 idle이고 active session에 미전송 attachment가 남아 있다.
    /// - 기대 결과: 동일 session을 다시 표시하며 attachment를 제거하지 않는다.
    func testReopenPreservesIdleAttachmentsWithoutPersistedRestore() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000672")
        let initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Idle attachment reopen must not load persisted state")
                return nil
            }
        }
        // 동일 session의 미전송 attachment 보존 결과만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.inspector(.aiChat(.attachmentPickerSelection(sessionID, [
            URL(fileURLWithPath: "/tmp/idle-reopen.txt"),
        ]))))
        XCTAssertEqual(store.state.inspector.aiChat.addedAttachments.count, 1)
        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.addedAttachments.count, 1)
    }

    /// 유휴 durable session의 모델·Thinking·컨텍스트 변경은 Open Chat 재진입 뒤에도 유지된다.
    /// - 검증 내용: AiChat 사용자 mutation 기반 same-session fast path와 persistence load 미호출
    /// - 사전 조건: active session의 입력은 비어 있고 모델·Thinking·컨텍스트·폴더 모드를 변경했다.
    /// - 기대 결과: 동일 session을 다시 표시하며 변경된 composer 설정을 persisted snapshot으로 덮지 않는다.
    func testReopenPreservesIdleComposerSettingsWithoutPersistedRestore() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000674")
        let originalModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: nil),
        )
        let changedModel = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5-mini",
            thinkingCapability: .effort(values: [.low, .high], defaultValue: nil),
        )
        let originalContext = AiChatCurrentContextSnapshot(
            summary: "Original context",
            references: [
                AiChatContextReference(
                    kind: .folder,
                    identifier: "/tmp/projects",
                    title: "Projects",
                    subtitle: "/tmp/projects",
                    metadata: ["path": "/tmp/projects"],
                ),
            ],
        )
        let changedContext = AiChatCurrentContextSnapshot(
            summary: "Changed context",
            references: originalContext.references,
        )
        var initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        initialState.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: originalContext,
            modelListState: .loaded([originalModel, changedModel]),
            selectedModelHandle: originalModel.id,
            selectedThinking: .effort(.high),
        )
        initialState.syncActiveTabInspectorState()
        let loadedSessionCount = LockIsolated(0)
        let gate = AIConnectionsLoadGate()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { await gate.load() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                loadedSessionCount.withValue { $0 += 1 }
                return nil
            }
        }
        // 동일 session의 사용자 변경 보존 결과만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.inspector(.aiChat(.selectedModelChanged(changedModel.id))))
        await store.send(.inspector(.aiChat(.selectedThinkingChanged(.effort(.low)))))
        await store.send(.inspector(.aiChat(.currentContextChanged(changedContext))))
        await store.send(.inspector(.aiChat(.folderStructureModeChanged(
            .currentContext,
            .includeSubfolders,
        ))))
        XCTAssertTrue(store.state.inspector.aiChat.draftText.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.addedAttachments.isEmpty)

        await store.send(.request(.reopenChat))
        await gate.waitForPendingLoadCount(1)
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)

        XCTAssertTrue(pending.preservesLiveRuntime)
        XCTAssertEqual(pending.resumeSessionID, sessionID)
        XCTAssertEqual(loadedSessionCount.value, 0)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.selectedModelHandle, changedModel.id)
        XCTAssertEqual(store.state.inspector.aiChat.selectedThinking, .effort(.low))
        XCTAssertEqual(store.state.inspector.aiChat.currentContext.summary, "Changed context")
        XCTAssertTrue(store.state.inspector.aiChat.currentContextFolderStructureModes.values.allSatisfy {
            $0 == .includeSubfolders
        })

        await store.send(.request(.reopenChat))
        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        await gate.resumeNext(with: .empty())
        await store.finish()
        XCTAssertEqual(loadedSessionCount.value, 0)
    }

    /// authoritative setup은 과거 mutation revision을 persisted 기준으로 재설정한다.
    /// - 검증 내용: nonzero historical revision 이후 persistence restore와 missing fallback 실행
    /// - 사전 조건: 사용자 변경 뒤 동일 session의 authoritative setup을 적용했다.
    /// - 기대 결과: Open Chat은 live runtime을 보존하지 않고 persisted session을 조회한다.
    func testReopenLoadsPersistenceAfterAuthoritativeSetupRebasesHistoricalMutation() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000675")
        let gate = AIConnectionsLoadGate()
        let loadedSessionCount = LockIsolated(0)
        let store = TestStore(initialState: makeClosedDurableInspectorState(sessionID: sessionID)) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { await gate.load() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                loadedSessionCount.withValue { $0 += 1 }
                return nil
            }
        }
        // persisted 기준 재설정 뒤 restore/fallback 결과만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.inspector(.aiChat(.draftTextChanged("Historical mutation"))))
        await store.send(.inspector(.aiChat(.setup(.init(
            sessionID: sessionID,
            mode: .chat,
            sessionStatus: .active,
        )))))
        await store.send(.request(.reopenChat))
        await gate.waitForPendingLoadCount(1)
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(pending.preservesLiveRuntime)
        XCTAssertEqual(pending.resumeSessionID, sessionID)

        await gate.resumeNext(with: .empty())
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertEqual(loadedSessionCount.value, 1)
        XCTAssertNotEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.restoreFailure, .missingRecord)
    }

    /// 유휴 composer session 재진입 중 draft mutation은 stale completion을 무효화한다.
    /// - 검증 내용: live provenance mutation guard, 최신 draft 보존, Inspector 미표시
    /// - 사전 조건: 미전송 draft를 가진 active session의 connections load가 pending이다.
    /// - 기대 결과: 늦은 completion은 무시되고 변경된 draft가 유지된다.
    func testIdleComposerReopenIgnoresCompletionAfterDraftMutation() async throws {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000673")
        let initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(initialState: initialState, gate: gate)

        await store.send(.inspector(.aiChat(.draftTextChanged("Original draft"))))
        await store.send(.request(.reopenChat))
        let pending = try XCTUnwrap(store.state.pendingAiChatInspectorOpen)
        XCTAssertTrue(pending.preservesLiveRuntime)
        await gate.waitForPendingLoadCount(1)
        await store.send(.inspector(.aiChat(.draftTextChanged("Changed while reopening"))))
        await store.send(.internal(.aiChatReopenInspectorOpenLoaded(
            requestID: pending.requestID,
            setup: .init(sessionID: sessionID, mode: .chat),
            connectionsFile: .empty(),
        )))

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertFalse(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Changed while reopening")
        await gate.resumeNext(with: .empty())
        await store.finish()
    }

    func testReopenPreservesLivePendingRequestWithoutPersistedRestore() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000656")
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let pendingRequest = AiChatPendingRequestStart(
            resolutionID: makeUUID("00000000-0000-0000-0000-000000000657"),
            kind: .submit,
            sessionID: sessionID,
            selectedModel: model,
            selectedRow: nil,
            preparedRequest: AiChatPreparedRequest(
                prompt: "Live prompt",
                messages: [],
                assistantReplacementIndex: nil,
                historyTruncation: .init(
                    includedMessageCount: 0,
                    excludedMessageCount: 0,
                    budget: 1,
                    truncationReason: nil,
                ),
            ),
        )
        var initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        initialState.inspector.aiChat.pendingRequestStart = pendingRequest
        initialState.inspector.aiChat.draftText = "Preserved draft"
        initialState.syncActiveTabInspectorState()
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiConnectionsFileClient.load = { .empty() }
            $0.aiChatSessionPersistenceClient.loadSession = { _ in
                XCTFail("Live runtime reopen must not load persisted state")
                return nil
            }
        }
        // 동일 session fast path의 lifecycle 보존과 restore 미호출만 선별 검증한다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.request(.reopenChat))
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.pendingRequestStart, pendingRequest)
        XCTAssertEqual(store.state.inspector.aiChat.draftText, "Preserved draft")
    }

    func testReopenAllowsLiveStreamingProgressBeforeInspectorOpenCompletes() async {
        let sessionID = makeSessionID("00000000-0000-0000-0000-000000000668")
        let requestID = AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000669"))
        let runID = AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000670"))
        let model = makeAiModel(
            provider: .openai,
            rawValue: "gpt-5",
            thinkingCapability: .effort(values: [.high], defaultValue: nil),
        )
        let requestContext = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: requestID,
            runID: runID,
            provider: model.provider,
            model: model.id,
            selectedModel: model,
            sessionStatus: .active,
        )
        let request = AiChatRequest(context: requestContext, messages: [])
        let lock = AiChatRequestLock(
            kind: .submit,
            requestID: requestID,
            runID: runID,
            context: requestContext,
            request: request,
            selectedModelHandle: model.id,
            selectedModelRow: nil,
            assistantReplacementIndex: nil,
        )
        var initialState = makeClosedDurableInspectorState(sessionID: sessionID)
        initialState.inspector.aiChat.executionPhase = .processing(lock)
        initialState.syncActiveTabInspectorState()
        let gate = AIConnectionsLoadGate()
        let store = makeDelayedConnectionsStore(initialState: initialState, gate: gate)

        await store.send(.request(.reopenChat))
        await gate.waitForPendingLoadCount(1)
        await store.send(.inspector(.aiChat(.executionEvent(
            .delta(context: requestContext, text: "partial"),
        ))))
        XCTAssertEqual(store.state.inspector.aiChat.streamingAssistantDraft, "partial")

        await gate.resumeNext(with: .empty())
        await store.skipReceivedActions()
        await store.finish()

        XCTAssertTrue(store.state.inspector.inspectorVisible)
        XCTAssertEqual(store.state.inspector.aiChat.sessionID, sessionID)
        XCTAssertEqual(store.state.inspector.aiChat.streamingAssistantDraft, "partial")
        XCTAssertTrue(store.state.inspector.aiChat.executionPhase.isProcessing)
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
        await store.receive(\.inspector.aiChat.setup)
        await store.receive(\.inspector.aiChat.providerConnectionsUpdated)
        await store.receive(\.inspector.setInspectorVisible)
        await store.receive(\.internal.applyInspectorNewChatSeed)

        XCTAssertNil(store.state.pendingAiChatInspectorOpen)
        XCTAssertEqual(store.state.contentTabs.activeTabID, secondTabID)
        XCTAssertEqual(store.state.inspector.activeMode, .chat)
    }

    func testToolbarSparklesWithoutConfiguredProviderShowsSettingsGate() async throws {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000030")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.navigation.seedInitialFolderPath("/Users/test/Documents")
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.tabContentStates[activeTabID] = initialState.content

        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: .empty())

        await store.send(.tabContent(tabID: activeTabID, action: .view(.newChatTapped)))
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.newChatRequested)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.request.newChat)
        await assertOpenNewChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: .empty())
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: .empty())
        await store.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = true
        }
        await store.receive(\.internal.applyInspectorNewChatSeed)

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

    func testAiConnectionUpdateForwardsProviderFileToOpenInspectorChat() async {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000032")
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

        let updatedFile: AIConnectionsFile = .testFixture(lastUsedProviderId: .anthropic, providers: [
            .testFixture(provider: .anthropic, authMethod: .apiKey),
        ])

        await store.send(.aiConnectionsFileUpdated(updatedFile))
        await store.receive { action in
            guard case let .inspector(.aiChat(.providerConnectionsUpdated(file))) = action else { return false }
            return file == updatedFile
        }
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
        initialState.syncActiveTabInspectorState()

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.inspector(.closeChat)) {
            $0.inspector.inspectorVisible = false
            $0.syncActiveTabInspectorState()
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
        initialState.syncActiveTabInspectorState()

        let store = makeStore(
            initialState: initialState,
            uuid: sessionID.rawValue,
            connectionsFile: .empty(),
        )

        await store.send(.inspector(.closeChat)) {
            $0.inspector.inspectorVisible = false
            $0.syncActiveTabInspectorState()
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

    func testToolbarSparklesOpensAndClosesNewChat() async throws {
        let fixedUUID = makeUUID("00000000-0000-0000-0000-000000000010")
        let selectedEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [selectedEntry]
        initialState.content.entryViewLayout.entries = [selectedEntry]
        initialState.content.entryViewLayout.selectedIds = [selectedEntry.id]
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.tabContentStates[activeTabID] = initialState.content

        let connectionsFile = AIConnectionsFile.empty()
        let expectedSetup = FileManagerAiChatContextAdapter.makeAiChatSetupState(content: initialState.content)

        let store = makeStore(initialState: initialState, uuid: fixedUUID, connectionsFile: connectionsFile)

        await store.send(.tabContent(tabID: activeTabID, action: .view(.newChatTapped)))
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.newChatRequested)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.request.newChat)
        await assertOpenNewChat(on: store, expectedSetup: expectedSetup, expectedConnectionsFile: connectionsFile)
        await assertAiChatSetup(on: store, expectedSetup: expectedSetup)
        await assertProviderConnectionsUpdated(on: store, expectedFile: connectionsFile)
        await store.receive(\.inspector.setInspectorVisible) {
            $0.inspector.inspectorVisible = true
        }
        await store.receive(\.internal.applyInspectorNewChatSeed)

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

        await store.send(.tabContent(tabID: activeTabID, action: .view(.newChatTapped)))
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.newChatRequested)) = action else { return false }
            return tabID == activeTabID
        }
        await store.receive(\.request.newChat)
        await store.receive(\.inspector.closeChat) {
            $0.inspector.inspectorVisible = false
        }

        XCTAssertEqual(store.state.inspector.activeMode, .chat)
        XCTAssertTrue(store.state.inspector.aiChat.transcriptHistory.isEmpty)
        XCTAssertTrue(store.state.inspector.aiChat.draftText.isEmpty)
    }

    func testSelectionStateChangesRouteIntoOpenAiChatContext() async throws {
        let firstEntry = makeEntry(name: "Draft.md", fullPath: "/Users/test/Documents/Draft.md")
        let secondEntry = makeEntry(name: "Notes.md", fullPath: "/Users/test/Documents/Notes.md")
        var initialState = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        initialState.content.entryViewLayout.entryOperations.items = [firstEntry, secondEntry]
        initialState.content.entryViewLayout.entries = [firstEntry, secondEntry]
        initialState.content.entryViewLayout.selectedIds = [firstEntry.id]
        let activeTabID = try XCTUnwrap(initialState.contentTabs.activeTabID)
        initialState.tabContentStates[activeTabID] = initialState.content

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

        await store.send(.tabContent(
            tabID: activeTabID,
            action: .entryViewLayout(.internal(.setSelectionState(
                ids: [secondEntry.id],
                lastSelectedId: secondEntry.id,
                rangeAnchorId: secondEntry.id,
                shouldScrollToSelection: false,
            ))),
        )) {
            $0.content.entryViewLayout.selectedIds = [secondEntry.id]
            $0.content.entryViewLayout.lastSelectedId = secondEntry.id
            $0.content.entryViewLayout.rangeAnchorId = secondEntry.id
            $0.content.entryViewLayout.shouldScrollToSelection = false
            $0.tabContentStates[activeTabID]?.entryViewLayout.selectedIds = [secondEntry.id]
            $0.tabContentStates[activeTabID]?.entryViewLayout.lastSelectedId = secondEntry.id
            $0.tabContentStates[activeTabID]?.entryViewLayout.rangeAnchorId = secondEntry.id
            $0.tabContentStates[activeTabID]?.entryViewLayout.shouldScrollToSelection = false
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .entryViewLayout(.delegate(.selectionChanged))) = action else {
                return false
            }
            return tabID == activeTabID
        }
        await store.receive { action in
            guard case let .tabContent(tabID, .delegate(.currentContextChanged(snapshot))) = action else {
                return false
            }
            return tabID == activeTabID && snapshot == rawUpdatedContext
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

    private func makeSelectionStore(
        initialState: FileManagerFeature.State,
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // store.exhaustivity = .off: FileManager와 AiChat 통합 상태 중 window-local selection 계약만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func makeAiModel(
        provider: AiProvider,
        rawValue: String,
        thinkingCapability: AiModelThinkingCapability,
    ) -> AiProviderModel {
        AiProviderModel(
            id: AiModelHandle(provider: provider, rawValue: rawValue),
            provider: provider,
            rawModelID: rawValue,
            displayName: rawValue,
            providerDisplayName: ProviderDescriptor.descriptor(for: provider)?.displayName ?? provider.rawValue,
            thinkingCapability: thinkingCapability,
            unavailableReason: nil,
        )
    }

    private func makeStore(
        initialState: FileManagerFeature.State,
        uuid: UUID,
        connectionsFile: AIConnectionsFile,
        aiProviderModels: [AiProviderModel] = [],
        defaultSettings: AiChatDefaultSettings = .default,
        savedSessionCount: LockIsolated<Int>? = nil,
    ) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.uuid = .constant(uuid)
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.aiConnectionsFileClient.load = { connectionsFile }
            $0.aiChatDefaultSettingsClient.load = { defaultSettings }
            $0.aiChatSessionPersistenceClient.saveSession = { snapshot in
                savedSessionCount?.withValue { $0 += 1 }
                return snapshot
            }
            $0.aiProviderModelListClient = AiProviderModelListClient(loadModels: { provider, _ in
                aiProviderModels.filter { $0.provider == provider }
            })
            $0.entryQuickLookClient = .init(quickLook: { _, _ in }, syncQuickLookSelection: { _, _ in })
        }
        // store.exhaustivity = .off: FileManager부터 AiChat까지의 통합 action 중 목적지 계약만 선별 검증한다.
        store.exhaustivity = .off
        return store
    }

    private func makeClosedDurableInspectorState(
        sessionID: AiChatSessionID,
    ) -> FileManagerFeature.State {
        var state = FileManagerFeature.State.makeInitial(path: "/Users/test/Documents")
        state.inspector.activeMode = .chat
        state.inspector.aiChat = AiChatFeature.State(
            mode: .chat,
            sessionID: sessionID,
            sessionStatus: .active,
        )
        state.syncActiveTabInspectorState()
        return state
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

    private func makeDefaultSettings(
        model: AiProviderModel,
        thinking: PersistedAIThinkingSelection,
    ) -> AiChatDefaultSettings {
        AiChatDefaultSettings(
            provider: PersistedAIProviderSelection(rawValue: model.provider.rawValue),
            model: PersistedAIModelSelection(
                providerRawValue: model.provider.rawValue,
                modelRawValue: model.rawModelID,
            ),
            thinking: thinking,
        )
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

private struct PendingAiChatSave {
    let snapshot: AiChatSessionSnapshot
    let continuation: CheckedContinuation<AiChatSessionSnapshot, Error>
}

private actor AiChatSaveGate {
    private var pendingSaves: [UUID: PendingAiChatSave] = [:]
    private(set) var cancellationCount = 0

    func save(_ snapshot: AiChatSessionSnapshot) async throws -> AiChatSessionSnapshot {
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingSaves[token] = PendingAiChatSave(snapshot: snapshot, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(token: token) }
        }
    }

    func waitForPendingSave() async {
        while pendingSaves.isEmpty {
            await Task.yield()
        }
    }

    func resumePendingSave() {
        guard let token = pendingSaves.keys.first,
              let pendingSave = pendingSaves.removeValue(forKey: token)
        else { return }
        pendingSave.continuation.resume(returning: pendingSave.snapshot)
    }

    private func cancel(token: UUID) {
        cancellationCount += 1
        pendingSaves.removeValue(forKey: token)?.continuation.resume(throwing: CancellationError())
    }
}
