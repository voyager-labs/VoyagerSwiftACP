import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class CBW001ContextualChatRequestTests: XCTestCase {
    // MARK: - CBW-001-open_contextual_chat

    /// CBW-001-open_contextual_chat: context 기반 채팅 진입 표면을 구성한다.
    /// 현재 context와 provider 연결 상태를 기반으로 chat shell, composer, model field가 사용자에게 보이는 초기 상태로 정렬되는지 검증합니다.
    /// - 검증 내용: setup/onAppear 이후 context summary, unconnected CTA, composer placeholder, model selector label을 확인합니다.
    /// - 사전 조건: provider 선택은 없고 current context는 reference/item/attachment를 각각 하나씩 포함합니다.
    /// - 기대 결과: 채팅 표면은 Open Settings CTA와 비활성 composer를 노출하고 submit은 불가능합니다.
    func testOpenContextualChatBuildsEntrySurfaceAndComposerContract() async {
        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        }
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()

        await store.send(.setup(makeOpenSetupState(catalogRows: catalogRows, summary: summary))) { state in
            self.applyOpenSetupState(&state, catalogRows: catalogRows, summary: summary)
        }
        await store.send(.onAppear)

        assertOpenContextualChatSurface(store.state)
    }

    // MARK: - CBW-001-submit_chat_request

    /// CBW-001-submit_chat_request: 선택한 provider executor로 요청을 위임하고 완료 응답을 transcript에 반영한다.
    /// submit 동작이 선택 모델, credential, session persistence까지 포함한 실제 실행 체인을 deterministic하게 통과하는지 검증합니다.
    /// - 검증 내용: request context model/credential, streaming delta, final assistant message, persistence snapshot을
    /// 확인합니다.
    /// - 사전 조건: OpenAI 모델과 API key credential이 연결되어 있고 draft에는 사용자 prompt가 있습니다.
    /// - 기대 결과: 사용자 메시지와 assistant 응답이 저장되며 실행 phase는 completed terminal lock으로 종료됩니다.
    func testSubmitChatRequestStreamsFinalAssistantMessageAndPersistsSession() async {
        let fixture = makeSubmitFixture()
        let store = makeSubmitStore(fixture: fixture)
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            self.applySubmitStartedState(&state, selectedHandle: fixture.selectedHandle, sessionID: fixture.sessionID)
        }
        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let completedLock = await receiveSuccessfulSubmitEvents(on: store, lock: lock, fixture: fixture)
        await store.finish()
        await assertSuccessfulSubmitResult(store: store, lock: lock, completedLock: completedLock, fixture: fixture)
    }

    /// CBW-001-submit_chat_request: 완료된 요청은 상태 문구를 제거하고 다음 submit을 허용한다.
    /// completed terminal state가 사용자에게 오류/진행 문구를 남기지 않고 다음 prompt 입력을 받을 수 있는지 검증합니다.
    /// - 검증 내용: requestStatusText와 canSubmit 계산 결과를 확인합니다.
    /// - 사전 조건: 이전 요청은 completed 상태이고 draft에는 후속 메시지가 있습니다.
    /// - 기대 결과: 상태 문구는 nil이고 composer는 submit 가능한 상태입니다.
    func testSubmitChatRequestClearsStatusTextAfterCompletion() {
        let state = makeCompletedStatusState()

        XCTAssertNil(state.requestStatusText)
        XCTAssertTrue(state.canSubmit)
    }

    // MARK: - CBW-001-show_request_processing_state

    /// CBW-001-show_request_processing_state: stream 실패 시 부분 assistant draft와 실패 상태를 함께 보여준다.
    /// processing 중 수신한 delta가 실패 terminal event 이후에도 사용자에게 partial response로 보존되는지 검증합니다.
    /// - 검증 내용: streamingAssistantDraft, failed executionPhase, requestStatusText, display model failure를 확인합니다.
    /// - 사전 조건: submit 이후 provider stream이 partial delta를 보낸 뒤 transportError로 실패합니다.
    /// - 기대 결과: partial draft는 보존되고 transcript에는 사용자 메시지만 남으며 실패 배너가 표시됩니다.
    func testShowRequestProcessingStatePreservesPartialDraftWhenStreamFails() async {
        let fixture = makeStreamFixture(draftText: "Partial failure", fixedMs: 1_700_000_000_250)
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.submitTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyProcessingFailureStartedState(&state, selectedHandle: fixture.selectedHandle)
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeSubmitLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        await receiveProcessingFailureEvents(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        assertProcessingFailureResult(fixture.store.state)
        await fixture.store.finish()
    }

    // MARK: - CBW-001-cancel_active_chat_request

    /// CBW-001-cancel_active_chat_request: 취소 이후 늦게 도착한 terminal event는 transcript를 변경하지 않는다.
    /// 사용자가 active request를 취소한 뒤 stale delta/final/failure가 durable state를 오염시키지 않는지 검증합니다.
    /// - 검증 내용: cancelled executionPhase, assistant message 부재, locked model/draft/failure cleanup을 확인합니다.
    /// - 사전 조건: provider stream이 partial delta를 보낸 뒤 사용자가 cancel을 누릅니다.
    /// - 기대 결과: late event는 무시되고 transcript에는 취소 전 사용자 메시지만 유지됩니다.
    func testCancelActiveChatRequestRejectsLateTerminalEvents() async {
        let fixture = makeStreamFixture(draftText: "Cancel me", fixedMs: 1_700_000_000_200)
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.submitTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyCancelStartedState(&state, selectedHandle: fixture.selectedHandle)
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeSubmitLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        let streamingLock = await receiveCancelStreamingDelta(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        await sendCancelAndLateTerminalEvents(
            on: fixture.store,
            request: request,
            streamingLock: streamingLock,
            fixedMs: fixture.fixedMs,
        )
        assertCancelResult(fixture.store.state, streamingLock: streamingLock, fixedMs: fixture.fixedMs)
        await fixture.store.finish()
    }

    // MARK: - CBW-001-regenerate_chat_response

    /// CBW-001-regenerate_chat_response: 기존 assistant 응답을 새 응답으로 교체하고 user turn은 중복하지 않는다.
    /// regenerate 요청이 마지막 assistant turn을 replacement target으로 고정하고 원래 user prompt만 provider에 전달하는지 검증합니다.
    /// - 검증 내용: regenerate request messages, assistantReplacementIndex, final transcript, persistence snapshot을 확인합니다.
    /// - 사전 조건: transcript에는 user 한 개와 기존 assistant 답변 한 개가 있습니다.
    /// - 기대 결과: provider 요청은 user turn만 포함하고 최종 transcript는 새 assistant 답변으로 교체됩니다.
    func testRegenerateChatResponseReplacesAssistantWithoutDuplicatingUserTurn() async {
        let persistence = AiChatSessionPersistenceSpy()
        let fixture = makeStreamFixture(
            draftText: "",
            fixedMs: 1_700_000_000_300,
            transcriptHistory: regenerationTranscript,
            persistence: persistence,
        )
        applyObservationFocusedExhaustivity(to: fixture.store)

        await fixture.store.send(.regenerateTapped)
        await resolvePendingRequestContext(fixture.store) { state in
            self.applyRegenerateStartedState(&state, selectedHandle: fixture.selectedHandle)
        }
        guard let request = fixture.stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let lock = makeRegenerateLock(
            request: request,
            catalogRows: fixture.catalogRows,
            selectedHandle: fixture.selectedHandle,
        )
        assertRegenerateRequest(request, store: fixture.store, lock: lock)
        await receiveRegenerateFinal(
            on: fixture.store,
            stream: fixture.stream,
            request: request,
            lock: lock,
            fixedMs: fixture.fixedMs,
        )
        await fixture.store.finish()
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, regeneratedTranscript)
    }
}

private actor CBW001ProviderDriver {
    var requests: [(AiChatRequest, StoredCredentialPayload?)] = []

    func append(request: AiChatRequest, credential: StoredCredentialPayload?) {
        requests.append((request, credential))
    }

    func snapshot() -> [(AiChatRequest, StoredCredentialPayload?)] {
        requests
    }
}

private struct CBW001SubmitFixture {
    let persistence: AiChatSessionPersistenceSpy
    let driver: CBW001ProviderDriver
    let catalogRows: [AiModelCatalogRow]
    let selectedHandle: AiModelHandle
    let credential: StoredCredentialPayload
    let sessionID: AiChatSessionID
    let fixedMs: Int64
    let expectedAssistantMessage: String
    let providerClient: AiChatProviderExecutionClient
}

private struct CBW001StreamFixture {
    let stream: AiChatExecutionStreamDriver
    let catalogRows: [AiModelCatalogRow]
    let selectedHandle: AiModelHandle
    let fixedMs: Int64
    let store: TestStore<AiChatFeature.State, AiChatFeature.Action>
}

private extension CBW001ContextualChatRequestTests {
    var regenerationTranscript: [AiChatMessage] {
        [AiChatMessage(role: .user, content: "Hello"), AiChatMessage(role: .assistant, content: "Old answer")]
    }

    var regeneratedTranscript: [AiChatMessage] {
        [AiChatMessage(role: .user, content: "Hello"), AiChatMessage(role: .assistant, content: "New answer")]
    }

    func applyObservationFocusedExhaustivity(to store: TestStore<AiChatFeature.State, AiChatFeature.Action>) {
        // 사용자 관찰 상태와 terminal 상태를 검증하기 위해 store.exhaustivity = .off를 사용합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)
    }

    func makeOpenSetupState(
        catalogRows: [AiModelCatalogRow],
        summary: AiChatCurrentContextSnapshot,
    ) -> AiChatSetupState {
        AiChatSetupState(
            sessionID: nil,
            sessionStatus: .idle,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
        )
    }

    func applyOpenSetupState(
        _ state: inout AiChatFeature.State,
        catalogRows: [AiModelCatalogRow],
        summary: AiChatCurrentContextSnapshot,
    ) {
        state.sessionID = nil
        state.sessionStatus = .idle
        state.currentContext = summary
        state.transcriptHistory = []
        state.draftText = ""
        state.catalogRows = catalogRows
        state.modelListState = .loaded(makeProviderModels())
        state.selectedModelHandle = nil
        state.selectedThinking = nil
        state.unavailableSelectedModelHandle = nil
        state.lockedModelHandle = nil
        state.lastExecutionFailure = nil
        state.executionPhase = .idle
    }

    func assertOpenContextualChatSurface(_ state: AiChatFeature.State) {
        XCTAssertEqual(state.currentContextSummaryDisplayModel.title, "Four files selected")
        XCTAssertEqual(state.currentContextSummaryDisplayModel.detail, "1 reference · 1 item · 1 attachment")
        XCTAssertEqual(state.connectionState, .unconnected(.init(
            title: "Connect an AI provider",
            detail: "Set up a provider in Settings to chat with this context.",
            fixLabel: "Open Settings",
        )))
        if case let .unconnected(connection, summaryDisplay) = state.surfaceState {
            XCTAssertEqual(connection.fixLabel, "Open Settings")
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
        } else {
            XCTFail("Expected unconnected surface state")
        }
        XCTAssertEqual(state.skeletonDisplayModel.headerTitle, "Chat")
        XCTAssertEqual(state.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "Select model")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "Select model")
        XCTAssertFalse(state.chatInputDisplayModel.canSubmit)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.modelFieldLabel, "Model")
        XCTAssertEqual(state.modelCatalogState.rows.first?.label.title, "GPT-4.1 Mini")
        XCTAssertNil(state.modelCatalogState.rows.first?.label.subtitle)
        XCTAssertNil(state.modelCatalogState.rows.first?.providerBadge)
        XCTAssertNil(state.selectedModelDisplayModel)
        XCTAssertNil(state.selectedModelHandle)
    }

    func makeSubmitFixture() -> CBW001SubmitFixture {
        let persistence = AiChatSessionPersistenceSpy()
        let driver = CBW001ProviderDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let credential = StoredCredentialPayload.apiKey(APIKeyCredentialFile(secret: "sk-openai"))
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))
        let fixedMs: Int64 = 1_700_000_000_100
        let expectedAssistantMessage = "Hello"
        let providerClient = AiChatProviderExecutionClient(execute: { request, credential in
            AsyncThrowingStream { continuation in
                Task {
                    await driver.append(request: request, credential: credential)
                    continuation.yield(.started(context: request.context))
                    continuation.yield(.delta(context: request.context, text: "Hel"))
                    continuation.yield(.delta(context: request.context, text: "lo"))
                    continuation.yield(.final(response: AiChatResponse(
                        context: request.context,
                        assistantMessage: AiChatMessage(role: .assistant, content: expectedAssistantMessage),
                        completedAtMs: 0,
                    )))
                    continuation.finish()
                }
            }
        })
        return CBW001SubmitFixture(
            persistence: persistence,
            driver: driver,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            credential: credential,
            sessionID: sessionID,
            fixedMs: fixedMs,
            expectedAssistantMessage: expectedAssistantMessage,
            providerClient: providerClient,
        )
    }

    func makeSubmitStore(fixture: CBW001SubmitFixture) -> TestStore<AiChatFeature.State, AiChatFeature.Action> {
        TestStore(initialState: AiChatFeature.State(
            sessionID: fixture.sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: fixture.catalogRows,
            selectedModelHandle: fixture.selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixture.fixedMs))
            $0.aiChatExecutionClient = .live(providerExecutionClient: fixture.providerClient)
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in await fixture.persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: {
                    let providerRecord = makeProviderRecord(provider: .openai, credential: fixture.credential)
                    return makeConnectionsFile(providers: [providerRecord])
                },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
    }

    func applySubmitStartedState(
        _ state: inout AiChatFeature.State,
        selectedHandle: AiModelHandle,
        sessionID: AiChatSessionID,
    ) {
        state.draftText = ""
        state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamingAssistantDraft = nil
        state.transcriptAutoScrollVersion = 1
        XCTAssertEqual(state.sessionID, sessionID)
        XCTAssertFalse(state.canSubmit)
    }

    func receiveSuccessfulSubmitEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
        fixture: CBW001SubmitFixture,
    ) async -> AiChatRequestLock {
        let rawResponse = AiChatResponse(
            context: lock.request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: fixture.expectedAssistantMessage),
            completedAtMs: 0,
        )
        let firstDeltaLock = lock.recordingDelta(at: fixture.fixedMs)
        let secondDeltaLock = firstDeltaLock.recordingDelta(at: fixture.fixedMs)
        await store.receive(.executionEvent(.started(context: lock.request.context)))
        await store.receive(.executionEvent(.delta(context: lock.request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(firstDeltaLock)
            state.transcriptAutoScrollVersion = 2
        }
        await store.receive(.executionEvent(.delta(context: lock.request.context, text: "lo"))) { state in
            state.streamingAssistantDraft = "Hello"
            state.executionPhase = .processing(secondDeltaLock)
            state.transcriptAutoScrollVersion = 3
        }
        await store.receive(.executionEvent(.final(response: rawResponse))) { state in
            state.transcriptHistory = self.submitCompletedTranscript(assistant: fixture.expectedAssistantMessage)
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.executionPhase = .completed(secondDeltaLock.recordingTerminal(
                at: fixture.fixedMs,
                failure: nil,
                wasCancelled: false,
            ))
            state.transcriptAutoScrollVersion = 4
        }
        return secondDeltaLock.recordingTerminal(at: fixture.fixedMs, failure: nil, wasCancelled: false)
    }

    func assertSuccessfulSubmitResult(
        store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
        completedLock: AiChatRequestLock,
        fixture: CBW001SubmitFixture,
    ) async {
        let recorded = await fixture.driver.snapshot()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0.context.model, fixture.selectedHandle)
        XCTAssertEqual(recorded.first?.1, fixture.credential)
        XCTAssertEqual(fixture.persistence.snapshots.count, 2)
        XCTAssertEqual(
            fixture.persistence.snapshots.first?.transcriptHistory,
            [AiChatMessage(role: .user, content: "Hello")],
        )
        XCTAssertEqual(
            fixture.persistence.snapshots.last?.transcriptHistory,
            submitCompletedTranscript(assistant: fixture.expectedAssistantMessage),
        )
        XCTAssertEqual(fixture.persistence.snapshots.last?.lastRequestID, lock.request.context.requestID)
        XCTAssertEqual(fixture.persistence.snapshots.last?.lastRunID, lock.request.context.runID)
        XCTAssertEqual(store.state.executionPhase, .completed(completedLock))
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.submittedAtMs, fixture.fixedMs)
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.terminalAtMs, fixture.fixedMs)
        XCTAssertNil(store.state.streamingAssistantDraft)
    }

    func makeCompletedStatusState() -> AiChatFeature.State {
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111120"))
        let requestContext = makeRequestContext(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000120")),
            runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000121")),
            model: selectedHandle,
            selectedRow: catalogRows[0],
            selectedModel: models[0],
        )
        let request = AiChatRequest(context: requestContext, messages: [AiChatMessage(role: .user, content: "Hello")])
        let completedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: 1_700_000_000_500, failure: nil, wasCancelled: false)
        return AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: submitCompletedTranscript(assistant: "Hi"),
            draftText: "Second message",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(completedLock),
        )
    }

    func makeStreamFixture(
        draftText: String,
        fixedMs: Int64,
        transcriptHistory: [AiChatMessage] = [],
        persistence: AiChatSessionPersistenceSpy? = nil,
    ) -> CBW001StreamFixture {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111112"))
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: transcriptHistory,
            draftText: draftText,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in stream.stream(for: request) })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in await persistence?.save(snapshot) },
                deleteSession: { _ in },
            )
        }
        return CBW001StreamFixture(
            stream: stream,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            fixedMs: fixedMs,
            store: store,
        )
    }

    func makeSubmitLock(
        request: AiChatRequest,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle,
    ) -> AiChatRequestLock {
        makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
    }

    func makeRegenerateLock(
        request: AiChatRequest,
        catalogRows: [AiModelCatalogRow],
        selectedHandle: AiModelHandle,
    ) -> AiChatRequestLock {
        makeRequestLock(
            kind: .regenerate,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: 1,
        )
    }

    func applyProcessingFailureStartedState(_ state: inout AiChatFeature.State, selectedHandle: AiModelHandle) {
        state.draftText = ""
        state.transcriptHistory = [AiChatMessage(role: .user, content: "Partial failure")]
        state.lockedModelHandle = selectedHandle
        state.streamingAssistantDraft = nil
    }

    func receiveProcessingFailureEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(lock.recordingDelta(at: fixedMs))
        }
        stream.yield(.failed(context: request.context, reason: .transportError))
        await store.receive(.executionEvent(.failed(context: request.context, reason: .transportError))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = .transportError
            state.executionPhase = .failed(
                lock.recordingDelta(at: fixedMs).recordingTerminal(
                    at: fixedMs,
                    failure: .transportError,
                    wasCancelled: false,
                ),
                .transportError,
            )
        }
    }

    func assertProcessingFailureResult(_ state: AiChatFeature.State) {
        XCTAssertEqual(state.streamingAssistantDraft, "Hel")
        XCTAssertEqual(state.transcriptHistory, [AiChatMessage(role: .user, content: "Partial failure")])
        XCTAssertEqual(state.requestStatusText, "The chat service response could not be read.")
        XCTAssertEqual(state.streamingAssistantDisplayModel?.content, "Hel")
        XCTAssertEqual(state.streamingAssistantDisplayModel?.failure, .transportError)
    }

    func applyCancelStartedState(_ state: inout AiChatFeature.State, selectedHandle: AiModelHandle) {
        state.draftText = ""
        state.transcriptHistory = [AiChatMessage(role: .user, content: "Cancel me")]
        state.lockedModelHandle = selectedHandle
        state.streamingAssistantDraft = nil
    }

    func receiveCancelStreamingDelta(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async -> AiChatRequestLock {
        let streamingLock = lock.recordingDelta(at: fixedMs)
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(streamingLock)
        }
        return streamingLock
    }

    func sendCancelAndLateTerminalEvents(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        request: AiChatRequest,
        streamingLock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
            state.executionPhase = .cancelled(streamingLock.recordingTerminal(
                at: fixedMs,
                failure: .cancelled,
                wasCancelled: true,
            ))
        }
        await store.send(.executionEvent(.delta(context: request.context, text: "lo")))
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late final"),
            completedAtMs: fixedMs,
        ))))
        await store.send(.executionEvent(.failed(context: request.context, reason: .unknown)))
    }

    func assertCancelResult(_ state: AiChatFeature.State, streamingLock: AiChatRequestLock, fixedMs: Int64) {
        let assistantMessages = state.transcriptHistory.filter { $0.role == .assistant }
        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(state.transcriptHistory, [AiChatMessage(role: .user, content: "Cancel me")])
        XCTAssertNil(state.lockedModelHandle)
        XCTAssertNil(state.lastExecutionFailure)
        XCTAssertNil(state.streamingAssistantDraft)
        XCTAssertEqual(
            state.executionPhase,
            .cancelled(streamingLock.recordingTerminal(at: fixedMs, failure: .cancelled, wasCancelled: true)),
        )
    }

    func applyRegenerateStartedState(_ state: inout AiChatFeature.State, selectedHandle: AiModelHandle) {
        state.selectedModelHandle = selectedHandle
        state.lockedModelHandle = selectedHandle
        state.lastExecutionFailure = nil
        state.streamingAssistantDraft = nil
    }

    func assertRegenerateRequest(
        _ request: AiChatRequest,
        store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        lock: AiChatRequestLock,
    ) {
        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello")])
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
    }

    func receiveRegenerateFinal(
        on store: TestStore<AiChatFeature.State, AiChatFeature.Action>,
        stream: AiChatExecutionStreamDriver,
        request: AiChatRequest,
        lock: AiChatRequestLock,
        fixedMs: Int64,
    ) async {
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "New answer"),
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = self.regeneratedTranscript
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false))
        }
    }

    func submitCompletedTranscript(assistant: String) -> [AiChatMessage] {
        [AiChatMessage(role: .user, content: "Hello"), AiChatMessage(role: .assistant, content: assistant)]
    }
}
