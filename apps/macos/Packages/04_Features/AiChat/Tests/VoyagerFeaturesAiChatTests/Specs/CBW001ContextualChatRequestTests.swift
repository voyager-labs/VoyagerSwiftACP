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
        applyObservationFocusedExhaustivity(to: store)
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

    // MARK: - CBW-001-open_contextual_chat

    /// CBW-001-open_contextual_chat: current context summary fixture가 진입 표면 계약과 일치한다.
    /// context summary가 selection 유무에 따라 title/detail을 안정적으로 구성하는지 검증합니다.
    /// - 검증 내용: selected entries, location only, empty context의 summary title/detail을 확인합니다.
    /// - 사전 조건: provider는 연결되어 있고 current context fixture만 서로 다르게 주입됩니다.
    /// - 기대 결과: summary display는 inspector와 동일한 텍스트 계약을 유지합니다.
    func testOpenContextualChatUsesCurrentContextSummaryFixturesThatMatchInspectorContract() {
        let selectedHandle = makeCatalogRows()[0].handle

        let selectedEntriesState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Documents · 2 selected",
                references: [],
                items: [],
                attachments: [],
            ),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(selectedEntriesState.currentContextSummaryDisplayModel.title, "Documents · 2 selected")
        XCTAssertNil(selectedEntriesState.currentContextSummaryDisplayModel.detail)

        let locationOnlyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(locationOnlyState.currentContextSummaryDisplayModel.title, "Documents")
        XCTAssertNil(locationOnlyState.currentContextSummaryDisplayModel.detail)

        let emptyContextState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: makeCatalogRows(),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )
        XCTAssertEqual(emptyContextState.currentContextSummaryDisplayModel.title, "No current selection")
        XCTAssertNil(emptyContextState.currentContextSummaryDisplayModel.detail)
    }

    /// CBW-001-open_contextual_chat: provider unavailable 상태는 고정 배너와 비활성 composer로 노출된다.
    /// 모델이 전혀 없는 진입 상태에서 사용자가 submit할 수 없고 빈 모델 라벨을 보는지 검증합니다.
    /// - 검증 내용: connectionState, canSubmit, modelLabel, empty surface summary를 확인합니다.
    /// - 사전 조건: current context는 존재하지만 catalogRows와 selectedModelHandle은 비어 있습니다.
    /// - 기대 결과: provider unavailable banner와 No models available composer label이 유지됩니다.
    func testOpenContextualChatShowsProviderUnavailableSurfaceAndEmptyComposerModelLabel() {
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        XCTAssertEqual(state.connectionState, .connected)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertEqual(state.chatInputDisplayModel.effortLabel, "No models available")

        if case let .empty(summary, selectedModel) = state.surfaceState {
            XCTAssertNil(selectedModel)
            XCTAssertEqual(summary.title, "Documents")
        } else {
            XCTFail("Expected empty surface with no loaded models")
        }
    }

    /// CBW-001-open_contextual_chat: 연결되지 않은 provider CTA는 AI Settings 열기로 위임된다.
    /// 빈 provider 상태에서 사용자가 fix action을 눌렀을 때 delegate 이벤트가 올바르게 발생하는지 검증합니다.
    /// - 검증 내용: openSettingsTapped 이후 delegate(.openAISettings)와 connectionState를 확인합니다.
    /// - 사전 조건: active session은 존재하지만 providerConnectionSnapshot은 빈 known 상태입니다.
    /// - 기대 결과: 표면은 그대로 유지되고 Settings 열기 delegate만 방출됩니다.
    func testOpenContextualChatDelegatesOpenAISettingsForNoProviderCTA() async {
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            providerConnectionSnapshot: .known([]),
        )) {
            AiChatFeature()
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.openSettingsTapped)
        await store.receive(.delegate(.openAISettings))

        XCTAssertEqual(
            store.state.connectionState,
            .unconnected(.init(
                title: "Connect an AI provider",
                detail: "Set up a provider in Settings to chat with this context.",
                fixLabel: "Open Settings",
            )),
        )
    }

    // MARK: - CBW-001-submit_chat_request

    /// CBW-001-submit_chat_request: 선택 모델이 현재 loaded catalog에 없으면 submit은 시작되지 않는다.
    /// stale selectedModelHandle이 남아 있어도 잘못된 실행 요청이 만들어지지 않는지 검증합니다.
    /// - 검증 내용: canSubmit, execution request count, executionPhase, draftText 보존을 확인합니다.
    /// - 사전 조건: selectedModelHandle은 존재하지만 loaded model list와 catalogRows가 서로 불일치합니다.
    /// - 기대 결과: submitTapped는 no-op이고 request는 한 건도 생성되지 않습니다.
    func testSubmitChatRequestDoesNotStartWhenSelectedModelIsMissingFromLoadedCatalog() async {
        final class RequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let spy = RequestSpy()
        let catalogRows = makeCatalogRows()
        let loadedModels = [makeThinkingCapableProviderModels()[1]]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("dddddddd-dddd-dddd-dddd-dddddddddddd")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [catalogRows[1]],
            modelListState: .loaded(loadedModels),
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                spy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(spy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
    }

    /// CBW-001-submit_chat_request: canSubmit이 false면 submitTapped는 no-op이다.
    /// provider/model 미선택 상태에서 submit 액션이 side effect를 만들지 않는지 검증합니다.
    /// - 검증 내용: execution request count, draftText, executionPhase, lockedModelHandle을 확인합니다.
    /// - 사전 조건: current context는 있으나 catalogRows와 selectedModelHandle이 비어 있어 canSubmit이 false입니다.
    /// - 기대 결과: submitTapped 이후에도 상태 변화 없이 기존 draft가 유지됩니다.
    func testSubmitChatRequestIsNoOpWhenCanSubmitIsFalse() async {
        final class ExecutionRequestSpy: @unchecked Sendable {
            private(set) var requests: [AiChatRequest] = []

            func append(_ request: AiChatRequest) {
                requests.append(request)
            }
        }

        let requestSpy = ExecutionRequestSpy()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                requestSpy.append(request)
                return AsyncStream { continuation in
                    continuation.finish()
                }
            })
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.submitTapped)

        XCTAssertTrue(requestSpy.requests.isEmpty)
        XCTAssertEqual(store.state.draftText, "Hello")
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
        await store.finish()
    }

    /// CBW-001-submit_chat_request: 두 번째 submit은 이전 assistant turn을 포함한 contiguous history를 전달한다.
    /// 한 번 완료된 assistant 응답 이후 후속 질문을 보낼 때 provider request history가 누락 없이 이어지는지 검증합니다.
    /// - 검증 내용: 첫 번째 final 이후 두 번째 request.messages와 transcriptHistory 누적을 확인합니다.
    /// - 사전 조건: 동일 session에서 첫 요청이 완료된 뒤 두 번째 user draft를 입력합니다.
    /// - 기대 결과: 두 번째 provider request는 user-assistant-user 순서의 history를 포함합니다.
    func testSubmitChatRequestIncludesPreviousAssistantTurnInSecondExecutionRequest() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111121"))
        let fixedMs: Int64 = 1_700_000_000_260

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
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
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        guard let firstRequest = stream.requests.first else {
            XCTFail("Expected first execution request")
            return
        }
        stream.yield(.final(response: AiChatResponse(
            context: firstRequest.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "First answer"),
            completedAtMs: fixedMs,
        )))
        await store.receive(.executionEvent(.final(response: AiChatResponse(
            context: firstRequest.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "First answer"),
            completedAtMs: fixedMs,
        )))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "First answer"),
            ]
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
        }

        await store.send(.draftTextChanged("Second question")) { state in
            state.draftText = "Second question"
        }
        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "First answer"),
                AiChatMessage(role: .user, content: "Second question"),
            ]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        XCTAssertEqual(stream.requests.count, 2)
        XCTAssertEqual(stream.requests[1].messages, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "First answer"),
            AiChatMessage(role: .user, content: "Second question"),
        ])

        stream.finish()
        stream.finish(at: 1)
        await store.finish()
    }

    /// CBW-001-submit_chat_request: oversized recent turn은 contiguous context를 지키기 위해 잘린다.
    /// history budget을 초과한 turn이 있어도 가장 최신 연속 대화만 provider request에 포함되는지 검증합니다.
    /// - 검증 내용: request.messages, historyTruncation included/excluded count와 truncationReason을 확인합니다.
    /// - 사전 조건: transcript에는 oversized recent turn과 latest turn이 함께 존재하고 draft가 추가됩니다.
    /// - 기대 결과: request는 latest contiguous turn과 current draft만 포함하고 truncation metadata가 기록됩니다.
    func testSubmitChatRequestTruncatesHistoryAtOversizedRecentTurnToKeepContiguousContext() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let fixedMs: Int64 = 1_700_000_001_000
        let olderUser = String(repeating: "o", count: 500)
        let olderAssistant = String(repeating: "p", count: 500)
        let oversizedRecentUser = String(repeating: "x", count: 11000)
        let oversizedRecentAssistant = String(repeating: "y", count: 11000)
        let latestUser = String(repeating: "u", count: 1700)
        let latestAssistant = String(repeating: "a", count: 1800)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111119")),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: olderUser),
                AiChatMessage(role: .assistant, content: olderAssistant),
                AiChatMessage(role: .user, content: oversizedRecentUser),
                AiChatMessage(role: .assistant, content: oversizedRecentAssistant),
                AiChatMessage(role: .user, content: latestUser),
                AiChatMessage(role: .assistant, content: latestAssistant),
            ],
            draftText: draft,
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase
        else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: latestUser),
            AiChatMessage(role: .assistant, content: latestAssistant),
            AiChatMessage(role: .user, content: draft),
        ])
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .user, content: olderUser)))
        XCTAssertFalse(request.messages.contains(AiChatMessage(role: .assistant, content: olderAssistant)))
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 4)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
    }

    /// CBW-001-submit_chat_request: submit 시점의 context timing과 truncation 계산은 요청 동안 고정된다.
    /// 사용자가 제출 후 thinking 선택을 바꾸더라도 실제 request context와 observability summary는 흔들리지 않는지 검증합니다.
    /// - 검증 내용: frozen currentContext, selectedThinking, submittedAtMs, request.messages, historyTruncation을 확인합니다.
    /// - 사전 조건: 긴 transcript, medium thinking, deterministic clock이 설정된 상태에서 submit을 시작합니다.
    /// - 기대 결과: request는 submit 시점 값으로 고정되고 이후 UI 변경은 in-flight request에 영향을 주지 않습니다.
    func testSubmitChatRequestFreezesContextTimingAndDeterministicHistoryTruncation() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let fixedMs: Int64 = 1_700_000_000_800
        let frozenContext = makeContextSnapshot(summary: "Before submit")
        let largeUser1 = String(repeating: "u", count: 9000)
        let largeAssistant1 = String(repeating: "a", count: 9000)
        let largeUser2 = String(repeating: "x", count: 9000)
        let largeAssistant2 = String(repeating: "y", count: 9000)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111117")),
            sessionStatus: .active,
            currentContext: frozenContext,
            transcriptHistory: [
                AiChatMessage(role: .user, content: largeUser1),
                AiChatMessage(role: .assistant, content: largeAssistant1),
                AiChatMessage(role: .user, content: largeUser2),
                AiChatMessage(role: .assistant, content: largeAssistant2),
            ],
            draftText: draft,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: largeUser1),
                AiChatMessage(role: .assistant, content: largeAssistant1),
                AiChatMessage(role: .user, content: largeUser2),
                AiChatMessage(role: .assistant, content: largeAssistant2),
                AiChatMessage(role: .user, content: draft),
            ]
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase
        else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.context.currentContext, frozenContext)
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: largeUser2),
            AiChatMessage(role: .assistant, content: largeAssistant2),
            AiChatMessage(role: .user, content: draft),
        ])
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 2)
        XCTAssertEqual(lock.historyTruncation.budget, 24000)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
        XCTAssertEqual(lock.observabilitySummary.submittedAtMs, fixedMs)

        await store.send(.selectedThinkingChanged(.effort(.high))) { state in
            state.selectedThinking = .effort(.high)
        }
        XCTAssertEqual(request.context.currentContext.summary, "Before submit")
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
    }

    /// CBW-001-submit_chat_request: 빈 context에서도 deterministic submitted timestamp로 요청이 준비된다.
    /// current context가 비어 있어도 실행 request 자체는 안정적으로 준비되는지 검증합니다.
    /// - 검증 내용: request.context.currentContext, submittedAtMs, request.messages를 확인합니다.
    /// - 사전 조건: empty current context와 non-empty draft를 가진 active session입니다.
    /// - 기대 결과: request는 empty context snapshot과 단일 user message로 생성됩니다.
    func testSubmitChatRequestPreparesEmptyContextWithDeterministicSubmittedTimestamp() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let fixedMs: Int64 = 1_700_000_000_900
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111118")),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "Hello empty context",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello empty context")]
            state.lockedModelHandle = catalogRows[0].handle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            return XCTFail("Expected request for empty context")
        }

        XCTAssertEqual(request.context.currentContext, .init())
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello empty context")])
    }

    // MARK: - CBW-001-show_request_processing_state

    /// CBW-001-show_request_processing_state: empty/ready/processing/error surface는 실행 단계에 맞춰 전환된다.
    /// request 전후와 terminal failure에서 message area와 skeleton surface가 각각 어떤 상태를 노출하는지 검증합니다.
    /// - 검증 내용: surfaceState, skeletonSurfaceDisplayModel, chatInputDisplayModel, canSubmit을 확인합니다.
    /// - 사전 조건: 동일 spec에서 empty, current-context draft, ready, processing, disconnected, failed state를 각각 구성합니다.
    /// - 기대 결과: 각 상태는 user-visible surface contract를 유지하며 processing 중 stop affordance를 노출합니다.
    func testShowRequestProcessingStateCoversEmptyReadyProcessingAndErrorSurfaces() {
        let catalogRows = makeCatalogRows()
        let summary = makeContextSnapshot()
        let selectedHandle = catalogRows[0].handle

        let emptyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: .init(),
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .empty(summaryDisplay, selectedModel) = emptyState.surfaceState {
            XCTAssertTrue(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected empty surface state")
        }
        if case let .empty(emptyDisplay) = emptyState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(emptyDisplay.title, "Ask about this context")
            XCTAssertEqual(emptyDisplay.detail, "Send a message to start a contextual chat.")
        } else {
            XCTFail("Expected skeleton empty surface state")
        }

        let currentContextInitialState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "What changed?",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .empty(summaryDisplay, selectedModel) = currentContextInitialState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(summaryDisplay.title, "Four files selected")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected current-context draft to keep empty surface state")
        }
        XCTAssertTrue(currentContextInitialState.canSubmit)
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.placeholder, "Ask anything…")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.modelLabel, "GPT-4.1 Mini")
        XCTAssertEqual(currentContextInitialState.chatInputDisplayModel.effortLabel, "Thinking unavailable")
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.canSubmit)
        XCTAssertTrue(currentContextInitialState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertFalse(currentContextInitialState.chatInputDisplayModel.isStopVisible)
        XCTAssertNil(currentContextInitialState.modelCatalogState.rows.first?.providerBadge)

        let readyState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        if case let .ready(summaryDisplay, selectedModel) = readyState.surfaceState {
            XCTAssertFalse(summaryDisplay.isEmpty)
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected ready surface state")
        }
        if case .ready = readyState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected ready skeleton surface state")
        }

        let processingState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: .processing(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: catalogRows[1].handle,
                        selectedRow: catalogRows[1],
                    ),
                    messages: [],
                ),
                selectedHandle: catalogRows[1].handle,
                selectedRow: catalogRows[1],
                assistantReplacementIndex: nil,
            )),
        )

        if case let .processing(processing, _, selectedModel) = processingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.lockedModel.title, "Claude Sonnet 4")
            XCTAssertEqual(processing.cancelAffordance.title, "Cancel request")
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected processing surface state")
        }
        if case let .processing(processing) = processingState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
        } else {
            XCTFail("Expected processing skeleton surface state")
        }
        XCTAssertFalse(processingState.canSubmit)
        XCTAssertTrue(processingState.chatInputDisplayModel.isStopVisible)
        XCTAssertFalse(processingState.chatInputDisplayModel.isSubmitVisible)
        XCTAssertTrue(processingState.chatInputDisplayModel.canStop)

        let refreshedProcessingState = AiChatFeature.State(
            sessionID: processingState.sessionID,
            sessionStatus: .active,
            currentContext: summary,
            transcriptHistory: processingState.transcriptHistory,
            draftText: processingState.draftText,
            catalogRows: [],
            selectedModelHandle: nil,
            lockedModelHandle: catalogRows[1].handle,
            lastExecutionFailure: nil,
            executionPhase: processingState.executionPhase,
        )

        if case let .processing(processing, _, selectedModel) = refreshedProcessingState.surfaceState {
            XCTAssertEqual(processing.lockedModel.label.title, "Claude Sonnet 4")
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected processing surface state to survive model refresh")
        }
        XCTAssertTrue(refreshedProcessingState.isProcessing)
        XCTAssertEqual(refreshedProcessingState.chatInputDisplayModel.modelLabel, "No models available")
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.isStopVisible)
        XCTAssertTrue(refreshedProcessingState.chatInputDisplayModel.canStop)

        let errorState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: summary,
            transcriptHistory: [],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: selectedHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: selectedHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )

        if case let .ready(_, selectedModel) = errorState.surfaceState {
            XCTAssertEqual(selectedModel?.label.title, "GPT-4.1 Mini")
            XCTAssertEqual(selectedModel?.title, "GPT-4.1 Mini")
            XCTAssertNil(selectedModel?.label.subtitle)
        } else {
            XCTFail("Expected terminal failure to remain in message-area ready surface")
        }
        if case .ready = errorState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected terminal failure skeleton to remain in ready surface")
        }
        XCTAssertEqual(errorState.requestStatusText, "The chat service response could not be read.")
    }

    /// CBW-001-show_request_processing_state: completed session은 provider 연결이 끊겨도 ready surface를 유지한다.
    /// terminal completion 이후 모델 선택만 unavailable이 되었을 때 transcript 표면이 오류 상태로 후퇴하지 않는지 검증합니다.
    /// - 검증 내용: ready surface, skeleton ready, selectedModel nil, canSubmit false를 확인합니다.
    /// - 사전 조건: completed execution lock은 존재하지만 catalogRows는 비어 있습니다.
    /// - 기대 결과: message area는 ready 상태를 유지하고 composer만 submit 불가로 남습니다.
    func testShowRequestProcessingStateKeepsCompletedSessionReadyWhenProviderBecomesDisconnected() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let disconnectedState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi"),
            ],
            draftText: "Follow up",
            catalogRows: [],
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock),
        )

        if case let .ready(summary, selectedModel) = disconnectedState.surfaceState {
            XCTAssertFalse(summary.isEmpty)
            XCTAssertNil(selectedModel)
        } else {
            XCTFail("Expected completed session to remain ready while model selection is unavailable")
        }
        if case .ready = disconnectedState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected skeleton surface to remain ready after request completion")
        }
        XCTAssertFalse(disconnectedState.canSubmit)
        XCTAssertFalse(disconnectedState.chatInputDisplayModel.canSubmit)
    }

    /// CBW-001-show_request_processing_state: legacy sessionStatus error는 restore flow가 없으면 terminal surface를 오염시키지
    /// 않는다.
    /// 완료된 request가 있는 session에서 오래된 failed status만으로 에러 표면이 다시 나타나지 않는지 검증합니다.
    /// - 검증 내용: ready surface, skeleton ready, canSubmit true, sessionStatusText nil을 확인합니다.
    /// - 사전 조건: executionPhase는 completed이고 sessionStatus만 failed로 설정됩니다.
    /// - 기대 결과: terminal surface는 ready 상태를 유지하고 restore 전용 상태 문구는 노출되지 않습니다.
    func testShowRequestProcessingStateIgnoresLegacySessionStatusErrorWithoutRestoreFlow() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let failedSessionState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .failed,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(lock),
        )

        if case let .ready(summary, selectedModel) = failedSessionState.surfaceState {
            XCTAssertFalse(summary.isEmpty)
            XCTAssertEqual(selectedModel?.handle, selectedHandle)
        } else {
            XCTFail("Expected terminal surface to remain ready when restore flow is disabled")
        }
        if case .ready = failedSessionState.skeletonSurfaceDisplayModel {
        } else {
            XCTFail("Expected skeleton surface to remain ready when restore flow is disabled")
        }
        XCTAssertTrue(failedSessionState.canSubmit)
        XCTAssertNil(failedSessionState.sessionStatusText)
    }

    /// CBW-001-show_request_processing_state: persistence recovery는 execution failure를 error surface로 노출한다.
    /// final 응답은 확보됐지만 session persistence가 실패한 경우 retry affordance가 사용자에게 드러나는지 검증합니다.
    /// - 검증 내용: surfaceState.error, skeleton error, requestStatusText, canSubmit false를 확인합니다.
    /// - 사전 조건: transcript는 존재하고 executionPhase는 persistenceRecovery(.unknown)입니다.
    /// - 기대 결과: surface는 Chat unavailable과 Retry affordance를 노출합니다.
    func testShowRequestProcessingStateReflectsPersistenceRecoveryFailureOnSurface() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: makeRequestContext(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    model: selectedHandle,
                    selectedRow: catalogRows[0],
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let recoveryState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Recovered locally")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )

        if case let .error(connection, summary) = recoveryState.surfaceState {
            XCTAssertEqual(connection.title, "Chat unavailable")
            XCTAssertEqual(connection.detail, "An unknown chat error occurred.")
            XCTAssertFalse(summary.isEmpty)
        } else {
            XCTFail("Expected persistence recovery to surface execution error")
        }
        if case let .error(connection) = recoveryState.skeletonSurfaceDisplayModel {
            XCTAssertEqual(connection.fixLabel, "Retry")
        } else {
            XCTFail("Expected skeleton surface to expose persistence recovery error")
        }
        XCTAssertEqual(recoveryState.requestStatusText, "Finalized locally; An unknown chat error occurred.")
        XCTAssertFalse(recoveryState.canSubmit)
    }

    // MARK: - CBW-001-recover_failed_chat_request

    /// CBW-001-recover_failed_chat_request: connections file load 실패는 provider 실행 없이 unknown failure로 전환된다.
    /// credential 조회가 실패한 경우 provider client가 호출되지 않고 terminal failure만 남는지 검증합니다.
    /// - 검증 내용: provider request count, failed executionPhase, lastExecutionFailure, requestStatusText를 확인합니다.
    /// - 사전 조건: submit 가능한 상태이지만 aiConnectionsFileClient.load가 unreadable error를 던집니다.
    /// - 기대 결과: provider execution은 0회이며 UI는 unknown failure recovery 상태로 전환됩니다.
    func testRecoverFailedChatRequestEmitsUnknownFailureWhenConnectionsFileLoadFails() async {
        actor ProviderDriver {
            var requestCount = 0

            func increment() {
                requestCount += 1
            }

            func snapshot() -> Int {
                requestCount
            }
        }

        enum LoadFailure: Error {
            case unreadable
        }

        let driver = ProviderDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111122"))
        let fixedMs: Int64 = 1_700_000_000_700
        let providerClient = AiChatProviderExecutionClient(execute: { request, _ in
            AsyncThrowingStream { continuation in
                Task {
                    await driver.increment()
                    continuation.yield(.started(context: request.context))
                    continuation.finish()
                }
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
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
            $0.aiChatExecutionClient = .live(providerExecutionClient: providerClient)
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { throw LoadFailure.unreadable },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.selectedModelHandle = selectedHandle
            state.lockedModelHandle = selectedHandle
            state.lastExecutionFailure = nil
            state.streamingAssistantDraft = nil
        }

        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let failedLock = lock.recordingTerminal(at: fixedMs, failure: .unknown, wasCancelled: false)
        await store.receive(.executionEvent(.failed(context: lock.request.context, reason: .unknown))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = .unknown
            state.executionPhase = .failed(failedLock, .unknown)
        }

        let requestCount = await driver.snapshot()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(store.state.requestStatusText, "An unknown chat error occurred.")
    }

    /// CBW-001-recover_failed_chat_request: failure surface가 남아 있으면 submit 재시도는 차단된다.
    /// stale failure banner가 존재하는 동안 사용자가 바로 submit을 다시 누르지 못하는지 검증합니다.
    /// - 검증 내용: canSubmit이 false인지 확인합니다.
    /// - 사전 조건: active session, non-empty draft, transportError failure가 idle phase 위에 남아 있습니다.
    /// - 기대 결과: composer는 retry surface를 지우기 전까지 submit 불가 상태를 유지합니다.
    func testRecoverFailedChatRequestDisallowsSubmitWhileFailureSurfaceExists() {
        let catalogRows = makeCatalogRows()
        let state = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry after failure",
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            lockedModelHandle: nil,
            lastExecutionFailure: .transportError,
            executionPhase: .idle,
        )
        let store = TestStore(initialState: state) {
            AiChatFeature()
        }
        XCTAssertFalse(store.state.canSubmit)
    }

    /// CBW-001-recover_failed_chat_request: draft 수정과 reset은 stale failure surface를 제거한다.
    /// 사용자가 새 prompt를 입력하거나 reset을 눌렀을 때 이전 transport failure가 더 이상 composer를 막지 않는지 검증합니다.
    /// - 검증 내용: draftTextChanged 후 canSubmit 복구와 reset 후 transcript/lock/failure 초기화를 확인합니다.
    /// - 사전 조건: failed execution lock과 stale draft, transcript가 존재합니다.
    /// - 기대 결과: 새 입력은 failure를 지우고 reset은 대화 상태를 완전히 초기화합니다.
    func testRecoverFailedChatRequestClearsStaleFailureOnDraftChangeAndReset() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Draft",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: selectedHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: selectedHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.draftTextChanged("Updated")) { state in
            state.draftText = "Updated"
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)

        await store.send(.resetTapped) { state in
            state.draftText = ""
            state.transcriptHistory = []
            state.lastExecutionFailure = nil
            state.lockedModelHandle = nil
            state.executionPhase = .idle
        }

        await store.finish()
    }

    /// CBW-001-recover_failed_chat_request: 모델 변경은 stale failure를 지우고 submit 가능 상태를 복원한다.
    /// 사용자가 다른 모델을 고르면 이전 failure surface가 즉시 내려가고 재시도 가능해지는지 검증합니다.
    /// - 검증 내용: selectedModelHandle 변경, lastExecutionFailure 초기화, executionPhase idle 복귀를 확인합니다.
    /// - 사전 조건: firstHandle로 실패한 뒤 secondHandle이 같은 catalog에 존재합니다.
    /// - 기대 결과: 새 모델 선택 후 canSubmit은 true가 됩니다.
    func testRecoverFailedChatRequestClearsStaleFailureWhenModelChanges() async {
        let catalogRows = makeCatalogRows()
        let firstHandle = catalogRows[0].handle
        let secondHandle = catalogRows[1].handle
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Documents", references: [], items: [], attachments: []),
            transcriptHistory: [],
            draftText: "Retry me",
            catalogRows: catalogRows,
            selectedModelHandle: firstHandle,
            lastExecutionFailure: .transportError,
            executionPhase: .failed(makeRequestLock(
                kind: .submit,
                request: AiChatRequest(
                    context: makeRequestContext(
                        sessionID: AiChatSessionID(rawValue: UUID()),
                        requestID: AiChatRequestID(rawValue: UUID()),
                        runID: AiChatRunID(rawValue: UUID()),
                        model: firstHandle,
                        selectedRow: catalogRows[0],
                    ),
                    messages: [],
                ),
                selectedHandle: firstHandle,
                selectedRow: catalogRows[0],
                assistantReplacementIndex: nil,
            ), .transportError),
        )) {
            AiChatFeature()
        }

        XCTAssertFalse(store.state.canSubmit)

        await store.send(.selectedModelChanged(secondHandle)) { state in
            state.selectedModelHandle = secondHandle
            state.lastExecutionFailure = nil
            state.executionPhase = .idle
        }

        XCTAssertTrue(store.state.canSubmit)
        await store.finish()
    }

    // MARK: - CBW-001-retry_failed_chat_request

    /// CBW-001-retry_failed_chat_request: authentication failure는 같은 user prompt로 retry를 시작한다.
    /// authentication terminal failure 이후 recovery tap이 regenerate flow로 재실행되는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 authentication failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 lastExecutionFailure를 제거합니다.
    func testRetryFailedChatRequestSupportsAuthenticationRecovery() async {
        await assertFailureRecovery(reason: .authentication, sessionIDRaw: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    }

    /// CBW-001-retry_failed_chat_request: model unavailable failure는 같은 user prompt로 retry를 시작한다.
    /// 모델 가용성 오류 이후 recovery tap이 사용자 입력을 보존한 채 재실행되는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 modelUnavailable failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 recovery surface를 닫습니다.
    func testRetryFailedChatRequestSupportsModelUnavailableRecovery() async {
        await assertFailureRecovery(reason: .modelUnavailable, sessionIDRaw: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    /// CBW-001-retry_failed_chat_request: network failure는 같은 user prompt로 retry를 시작한다.
    /// 네트워크 terminal failure 이후 recovery tap이 재시도 경로를 정상적으로 여는지 검증합니다.
    /// - 검증 내용: retry request messages, processing lock, locked model, failure cleanup을 확인합니다.
    /// - 사전 조건: active session에서 첫 submit이 network failure로 종료됩니다.
    /// - 기대 결과: errorRecoveryTapped는 동일 prompt의 새 request를 만들고 processing 상태로 복귀합니다.
    func testRetryFailedChatRequestSupportsNetworkRecovery() async {
        await assertFailureRecovery(reason: .network, sessionIDRaw: "cccccccc-cccc-cccc-cccc-cccccccccccc")
    }

    // MARK: - CBW-001-recover_persisted_chat_state

    /// CBW-001-recover_persisted_chat_state: final transcript persistence 실패는 recovery state를 만든다.
    /// assistant final까지는 성공했지만 snapshot 저장이 실패한 경우 로컬 finalized 상태와 recovery 배너가 남는지 검증합니다.
    /// - 검증 내용: executionEvent.final 이후 persistenceFailed, transcript 보존, requestStatusText를 확인합니다.
    /// - 사전 조건: saveSession dependency는 항상 throw하고 provider stream은 final response를 반환합니다.
    /// - 기대 결과: executionPhase는 persistenceRecovery로 전환되고 transcript는 손실되지 않습니다.
    func testRecoverPersistedChatStateCreatesRecoveryStateWhenPersistenceFails() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111114"))
        let fixedMs: Int64 = 1_700_000_000_400

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
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
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in
                    struct PersistenceBoom: Error {}
                    throw PersistenceBoom()
                },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.lockedModelHandle = selectedHandle
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi"),
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi"),
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(finalizedLock)
        }

        await store.receive(.persistenceFailed(finalizedLock, .unknown)) { state in
            state.lastExecutionFailure = .unknown
            state.executionPhase = .persistenceRecovery(finalizedLock, .unknown)
        }

        XCTAssertEqual(store.state.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi"),
        ])
        XCTAssertEqual(store.state.requestStatusText, "Finalized locally; An unknown chat error occurred.")

        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: persistence retry는 저장을 다시 시도하고 recovery state를 제거한다.
    /// errorRecoveryTapped가 persistenceRecovery 경로에서 saveSession을 재실행해 completed로 복귀하는지 검증합니다.
    /// - 검증 내용: persistence snapshot count, persisted transcript, persistenceRecoverySucceeded 이후 상태를 확인합니다.
    /// - 사전 조건: transcript와 completed lock은 이미 있고 executionPhase는 persistenceRecovery(.unknown)입니다.
    /// - 기대 결과: snapshot이 한 번 저장되고 lastExecutionFailure는 nil로 초기화됩니다.
    func testRecoverPersistedChatStateRetriesSaveAndClearsRecoveryState() async {
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333"))
        let fixedMs: Int64 = 1_700_000_001_000
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("44444444-4444-4444-4444-444444444444")),
                runID: AiChatRunID(rawValue: makeUUID("55555555-5555-5555-5555-555555555555")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        let transcript = [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "Hi"),
        ]
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: transcript,
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }

        await store.send(.errorRecoveryTapped)

        await store.receive(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.sessionID, sessionID)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, transcript)
        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: 이미 성공한 persistence retry 뒤에 늦은 실패 이벤트가 와도 무시된다.
    /// recovery success와 retry failure가 경합할 때 success state가 다시 오염되지 않는지 검증합니다.
    /// - 검증 내용: persistenceRecoverySucceeded 이후 lastExecutionFailure nil, executionPhase completed 유지 여부를 확인합니다.
    /// - 사전 조건: executionPhase는 persistenceRecovery이며 뒤이어 success와 stale retry failure를 순서대로 보냅니다.
    /// - 기대 결과: completed 상태가 유지되고 stale retry failure는 무시됩니다.
    func testRecoverPersistedChatStateIgnoresRetryFailureAfterSuccess() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("77777777-7777-7777-7777-777777777777"))
        let request = AiChatRequest(
            context: makeRequestContext(
                sessionID: sessionID,
                requestID: AiChatRequestID(rawValue: makeUUID("88888888-8888-8888-8888-888888888888")),
                runID: AiChatRunID(rawValue: makeUUID("99999999-9999-9999-9999-999999999999")),
                model: selectedHandle,
                selectedRow: catalogRows[0],
            ),
            messages: [AiChatMessage(role: .user, content: "Hello")],
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastExecutionFailure: .unknown,
            executionPhase: .persistenceRecovery(lock, .unknown),
        )) {
            AiChatFeature()
        }

        await store.send(.persistenceRecoverySucceeded(lock)) { state in
            state.lastExecutionFailure = nil
            state.executionPhase = .completed(lock)
        }

        await store.send(.persistenceRecoveryRetryFailed(lock, .unknown))

        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertEqual(store.state.executionPhase, .completed(lock))
        await store.finish()
    }

    /// CBW-001-recover_persisted_chat_state: retryable recovery state가 없으면 errorRecoveryTapped는 no-op이다.
    /// idle surface에서 recovery action이 잘못 실행되어 상태를 바꾸지 않는지 검증합니다.
    /// - 검증 내용: executionPhase idle과 lastExecutionFailure nil 유지 여부를 확인합니다.
    /// - 사전 조건: sessionStatus는 idle이고 executionPhase도 idle입니다.
    /// - 기대 결과: errorRecoveryTapped 이후에도 아무 상태 변화가 없습니다.
    func testRecoverPersistedChatStateDoesNothingWithoutRetryableState() async {
        let catalogRows = makeCatalogRows()
        let store = TestStore(initialState: AiChatFeature.State(
            sessionStatus: .idle,
            currentContext: makeContextSnapshot(),
            catalogRows: catalogRows,
            selectedModelHandle: catalogRows[0].handle,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        }

        await store.send(.errorRecoveryTapped)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lastExecutionFailure)
        await store.finish()
    }

    // MARK: - CBW-001-continue_inflight_chat_request

    /// CBW-001-continue_inflight_chat_request: 다른 session을 열람했다가 돌아와도 원 request completion은 원 session에 저장된다.
    /// in-flight request 중 session 전환이 발생해도 원래 request lock과 persistence snapshot이 active session 기준으로 마무리되는지 검증합니다.
    /// - 검증 내용: restore 이후 processing lock 유지, final completion transcript, saved session summary, persistence
    /// snapshots를 확인합니다.
    /// - 사전 조건: active session에서 submit을 시작한 뒤 target session으로 이동하고 다시 active session으로 복귀합니다.
    /// - 기대 결과: 원 request final은 active session transcript와 session row를 갱신하고 target session을 오염시키지 않습니다.
    func testContinueInFlightChatRequestPreservesOriginalSessionCompletionAcrossSessionSwitch() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111221"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222221"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_221
        let activeRow = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Active request",
            preview: "Question A",
            messageCount: 1,
            contextTitle: "Docs",
            provider: selectedHandle.provider,
            model: selectedHandle,
            createdAtMs: fixedMs - 10,
            updatedAtMs: fixedMs - 10,
            status: .active,
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Earlier target chat")],
            updatedAtMs: fixedMs - 1,
        )
        let targetRow = AiChatSessionSummary(snapshot: targetSnapshot)
        let activeRestoreSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A")],
            updatedAtMs: fixedMs,
        )
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { id in
            switch id {
            case targetSessionID:
                targetSnapshot
            case activeSessionID:
                activeRestoreSnapshot
            default:
                nil
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [activeRow, targetRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question A",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { try await persistence.loadSession($0) },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Question A")]
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let activeRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A")],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        await store.send(.sessionRowTapped(activeSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.restoreSessionID = activeSessionID
            state.currentContextFolderStructureModes = [:]
        }

        await store.receive(.restoreOutcome(
            requestedSessionID: activeSessionID,
            .restored(snapshot: activeRequestStartSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRequestStartSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRequestStartSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = activeRequestStartSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .processing(lock)
            state.selectedModelHandle = activeRequestStartSnapshot.model
            state.selectedThinking = activeRequestStartSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRequestStartSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertEqual(store.state.surfaceState, .processing(
            processing: AiChatProcessingState(
                lockedModel: AiChatLockedModelDisplayModel(
                    handle: selectedHandle,
                    label: AiChatModelLabel(title: catalogRows[0].displayName),
                ),
                cancelAffordance: AiChatCancelAffordance(title: "Cancel request", isEnabled: true),
            ),
            summary: store.state.currentContextSummaryDisplayModel,
            selectedModel: store.state.selectedModelDisplayModel,
        ))
        XCTAssertTrue(store.state.isProcessing)

        let assistantMessage = AiChatMessage(role: .assistant, content: "Original request completed")
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Question A"),
                assistantMessage,
            ]
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = lock.context.requestContext
            state.lastRequestContextModelHandle = selectedHandle
            state.executionPhase = .completed(finalizedLock)
            state.transcriptAutoScrollVersion = 2
        }

        let expectedOriginalSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Question A"),
                assistantMessage,
            ],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedOriginalSummary = AiChatSessionSummary(snapshot: expectedOriginalSnapshot)
        await store.receive(.sessionSnapshotSaved(
            AiChatSessionSummary(snapshot: expectedOriginalSnapshot),
            snapshot: expectedOriginalSnapshot,
            requestID: finalizedLock.requestID,
            runID: finalizedLock.runID,
        )) { state in
            state.sessionList.replaceRow(expectedOriginalSummary)
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.sessionList.errorMessage = nil
        }

        await store.finish()
        XCTAssertEqual(store.state.sessionID, activeSessionID)
        XCTAssertEqual(store.state.transcriptHistory, expectedOriginalSnapshot.transcriptHistory)
        if case .processing = store.state.surfaceState {
            XCTFail("The restored original session must leave processing after final completion")
        }
        XCTAssertFalse(store.state.isProcessing)
        XCTAssertEqual(persistence.snapshots, [activeRequestStartSnapshot, expectedOriginalSnapshot])
    }

    /// CBW-001-continue_inflight_chat_request: offscreen session failure는 현재 보이는 session을 오염시키지 않는다.
    /// 다른 session을 보는 동안 원 request가 failure로 끝나도 visible session의 transcript와 error surface가 변하지 않는지 검증합니다.
    /// - 검증 내용: target session visible state 보호, active session 복귀 후 original failure 복원, persistence snapshot count를
    /// 확인합니다.
    /// - 사전 조건: active session submit 후 target session으로 이동한 상태에서 원 request가 network failure로 종료됩니다.
    /// - 기대 결과: target session은 깨끗하게 유지되고 active session 복귀 시에만 original failure가 드러납니다.
    func testContinueInFlightChatRequestDoesNotPolluteVisibleSessionWhenOffscreenFailureArrives() async {
        let activeSessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111241"))
        let targetSessionID = AiChatSessionID(rawValue: makeUUID("22222222-2222-2222-2222-222222222241"))
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let fixedMs: Int64 = 1_700_000_001_241
        let activeRow = AiChatSessionSummary(
            sessionID: activeSessionID,
            title: "Active request",
            preview: "Question A",
            messageCount: 1,
            contextTitle: "Docs",
            provider: selectedHandle.provider,
            model: selectedHandle,
            createdAtMs: fixedMs - 10,
            updatedAtMs: fixedMs - 10,
            status: .active,
        )
        let targetSnapshot = AiChatSessionSnapshot(
            sessionID: targetSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Earlier target chat")],
            updatedAtMs: fixedMs - 1,
        )
        let targetRow = AiChatSessionSummary(snapshot: targetSnapshot)
        let activeRestoreSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A")],
            updatedAtMs: fixedMs,
        )
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy(loadHandler: { id in
            switch id {
            case targetSessionID:
                targetSnapshot
            case activeSessionID:
                activeRestoreSnapshot
            default:
                nil
            }
        })

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .sessions,
            sessionList: .init(allRows: [activeRow, targetRow], selectedSessionID: activeSessionID),
            sessionID: activeSessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current docs"),
            draftText: "Question A",
            catalogRows: catalogRows,
            modelListState: .loaded(makeThinkingCapableProviderModels()),
            selectedModelHandle: selectedHandle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                listSessions: { _, _ in [] },
                loadSession: { try await persistence.loadSession($0) },
                saveSession: { snapshot in await persistence.save(snapshot) },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { AIConnectionsFile.empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Question A")]
            state.lockedModelHandle = selectedHandle
            state.sessionList.unreadCompletedSessionIDs = []
            state.transcriptAutoScrollVersion = 1
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let activeRequestStartSnapshot = AiChatSessionSnapshot(
            sessionID: activeSessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [AiChatMessage(role: .user, content: "Question A")],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
            state.backgroundExecutionPhases[lock.requestID] = .processing(lock)
            state.executionPhase = .idle
            state.lockedModelHandle = nil
            state.streamingAssistantDraft = nil
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: targetSessionID,
            .restored(snapshot: targetSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = targetSessionID
            state.sessionStatus = .active
            state.transcriptHistory = targetSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = targetSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.selectedModelHandle = targetSnapshot.model
            state.selectedThinking = targetSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: targetSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }
        XCTAssertNil(store.state.requestStatusText)

        stream.yield(.failed(context: request.context, reason: .network))
        stream.finish()

        let failedLock = lock.recordingTerminal(at: fixedMs, failure: .network, wasCancelled: false)
        await store.receive(.executionEvent(.failed(context: request.context, reason: .network))) { state in
            state.backgroundExecutionPhases[lock.requestID] = .failed(failedLock, .network)
        }
        XCTAssertEqual(store.state.sessionID, targetSessionID)
        XCTAssertEqual(store.state.transcriptHistory, targetSnapshot.transcriptHistory)
        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertNil(store.state.requestStatusText)
        if case .processing = store.state.surfaceState {
            XCTFail("The visible target session must not show another session's failed request as processing")
        }

        await store.send(.sessionRowTapped(activeSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = activeSessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.restoreSessionID = activeSessionID
            state.currentContextFolderStructureModes = [:]
        }
        await store.receive(.restoreOutcome(
            requestedSessionID: activeSessionID,
            .restored(snapshot: activeRequestStartSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRequestStartSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRequestStartSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = activeRequestStartSnapshot.model
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .failed(failedLock, .network)
            state.selectedModelHandle = activeRequestStartSnapshot.model
            state.selectedThinking = activeRequestStartSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRequestStartSnapshot)
            state.restoreFailure = nil
            state.mode = .chat
            state.sessionList.errorMessage = nil
        }

        XCTAssertEqual(store.state.requestStatusText, AiChatExecutionFailure.network.displayMessage)
        XCTAssertEqual(persistence.snapshots.count, 1)
        await store.finish()
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

    func assertFailureRecovery(reason: AiChatExecutionFailure, sessionIDRaw: String) async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let selectedHandle = catalogRows[0].handle
        let prompt = "Retry me"
        let sessionID = AiChatSessionID(rawValue: makeUUID(sessionIDRaw))
        let fixedMs: Int64 = 1_700_000_001_100

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: prompt,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: fixedMs))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { _ in },
                deleteSession: { _ in },
            )
        }
        applyObservationFocusedExhaustivity(to: store)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: prompt)]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        guard let request = stream.requests.first else {
            return XCTFail("Expected execution request")
        }

        let failedLock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        ).recordingTerminal(at: fixedMs, failure: reason, wasCancelled: false)

        stream.yield(.failed(context: request.context, reason: reason))

        await store.receive(.executionEvent(.failed(context: request.context, reason: reason))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = reason
            state.executionPhase = .failed(failedLock, reason)
        }

        if case .ready = store.state.surfaceState {
        } else {
            XCTFail("Expected ready surface state after failure")
        }

        XCTAssertEqual(store.state.requestStatusText, reason.displayMessage)
        XCTAssertEqual(store.state.lastExecutionFailure, reason)

        await store.send(.errorRecoveryTapped)

        guard let retryRequest = stream.requests.last, stream.requests.count == 2 else {
            return XCTFail("Expected a retry request")
        }

        let retryLock = makeRequestLock(
            kind: .regenerate,
            request: retryRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        XCTAssertEqual(retryRequest.messages, [AiChatMessage(role: .user, content: prompt)])
        XCTAssertEqual(store.state.executionPhase, .processing(retryLock))
        XCTAssertEqual(store.state.lockedModelHandle, selectedHandle)
        XCTAssertNil(store.state.lastExecutionFailure)

        stream.finish(at: 1)
        await store.finish()
    }
}
