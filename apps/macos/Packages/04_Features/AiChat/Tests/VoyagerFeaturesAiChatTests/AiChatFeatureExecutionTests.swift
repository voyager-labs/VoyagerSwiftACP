// swiftlint:disable file_length
import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// swiftlint:disable type_body_length
@MainActor
final class AiChatFeatureExecutionTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    // swiftlint:disable:next function_body_length
    func testSubmitWithLiveExecutionClientDelegatesToProviderExecutor() async {
        actor ProviderDriver {
            var requests: [(AiChatRequest, StoredCredentialPayload?)] = []

            func append(request: AiChatRequest, credential: StoredCredentialPayload?) {
                requests.append((request, credential))
            }

            func snapshot() -> [(AiChatRequest, StoredCredentialPayload?)] {
                requests
            }
        }

        let persistence = AiChatSessionPersistenceSpy()
        let driver = ProviderDriver()
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
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: {
                    makeConnectionsFile(providers: [
                        makeProviderRecord(provider: .openai, credential: credential)
                    ])
                },
                save: { .success($0) },
                deleteCredential: { _ in .success(AIConnectionsFile.empty()) },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
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

        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let rawResponse = AiChatResponse(
            context: lock.request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: expectedAssistantMessage),
            completedAtMs: 0,
        )
        let firstDeltaLock = lock.recordingDelta(at: fixedMs)
        let secondDeltaLock = firstDeltaLock.recordingDelta(at: fixedMs)

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
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: expectedAssistantMessage)
            ]
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.executionPhase = .completed(secondDeltaLock.recordingTerminal(
                at: fixedMs,
                failure: nil,
                wasCancelled: false,
            ))
            state.transcriptAutoScrollVersion = 4
        }
        await store.finish()

        let recorded = await driver.snapshot()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.0.context.model, selectedHandle)
        XCTAssertEqual(recorded.first?.1, credential)
        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: expectedAssistantMessage)
        ])
        XCTAssertEqual(persistence.snapshots.first?.lastRequestID, lock.request.context.requestID)
        XCTAssertEqual(persistence.snapshots.first?.lastRunID, lock.request.context.runID)
        XCTAssertEqual(
            store.state.executionPhase,
            .completed(secondDeltaLock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)),
        )
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.submittedAtMs, fixedMs)
        XCTAssertEqual(store.state.executionPhase.lock?.observabilitySummary.terminalAtMs, fixedMs)
        XCTAssertNil(store.state.streamingAssistantDraft)
    }

    // swiftlint:disable:next function_body_length
    func testCancelRejectsLateFinalAndFailureEvents() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111112"))
        let fixedMs: Int64 = 1_700_000_000_200

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Cancel me",
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
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Cancel me")]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
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
        let streamingLock = lock.recordingDelta(at: fixedMs)

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(streamingLock)
        }

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

        let assistantMessages = store.state.transcriptHistory.filter { $0.role == .assistant }
        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .user, content: "Cancel me")])
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertNil(store.state.streamingAssistantDraft)
        XCTAssertEqual(
            store.state.executionPhase,
            .cancelled(streamingLock.recordingTerminal(at: fixedMs, failure: .cancelled, wasCancelled: true)),
        )

        await store.finish()
    }

    // swiftlint:disable:next function_body_length
    func testSubmitConnectionsFileLoadFailureEmitsUnknownFailureWithoutProviderExecution() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
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

    // swiftlint:disable:next function_body_length
    func testFailedStreamPreservesPartialDraftAndMarksPartialFailure() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111119"))
        let fixedMs: Int64 = 1_700_000_000_250

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Partial failure",
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
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Partial failure")]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
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

        stream.yield(.delta(context: request.context, text: "Hel"))
        await store.receive(.executionEvent(.delta(context: request.context, text: "Hel"))) { state in
            state.streamingAssistantDraft = "Hel"
            state.executionPhase = .processing(lock.recordingDelta(at: fixedMs))
        }

        stream.yield(.failed(context: request.context, reason: .transportError))
        let failedLock = lock.recordingDelta(at: fixedMs).recordingTerminal(
            at: fixedMs,
            failure: .transportError,
            wasCancelled: false,
        )
        await store.receive(.executionEvent(.failed(context: request.context, reason: .transportError))) { state in
            state.lockedModelHandle = nil
            state.lastExecutionFailure = .transportError
            state.executionPhase = .failed(failedLock, .transportError)
        }

        XCTAssertEqual(store.state.streamingAssistantDraft, "Hel")
        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .user, content: "Partial failure")])
        XCTAssertEqual(store.state.requestStatusText, "The chat service response could not be read.")
        XCTAssertEqual(store.state.streamingAssistantDisplayModel?.content, "Hel")
        XCTAssertEqual(store.state.streamingAssistantDisplayModel?.failure, .transportError)

        await store.finish()
    }

    // swiftlint:disable:next function_body_length
    func testSecondSubmitIncludesPreviousAssistantTurnInExecutionRequest() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
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
                AiChatMessage(role: .assistant, content: "First answer")
            ]
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
        }

        await store.send(.draftTextChanged("Second question")) { state in
            state.draftText = "Second question"
        }
        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "First answer"),
                AiChatMessage(role: .user, content: "Second question")
            ]
            state.lockedModelHandle = selectedHandle
            state.streamingAssistantDraft = nil
        }

        XCTAssertEqual(stream.requests.count, 2)
        XCTAssertEqual(stream.requests[1].messages, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "First answer"),
            AiChatMessage(role: .user, content: "Second question")
        ])

        stream.finish()
        stream.finish(at: 1)
        await store.finish()
    }

    func testLiveExecutionClientEmitsRawAnthropicDeltaBeforeFinal() async {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[1].handle
        let requestContext = makeRequestContext(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111121")),
            requestID: AiChatRequestID(rawValue: makeUUID("00000000-0000-0000-0000-000000000122")),
            runID: AiChatRunID(rawValue: makeUUID("00000000-0000-0000-0000-000000000123")),
            model: selectedHandle,
            selectedRow: catalogRows[1],
        )
        let request = AiChatRequest(context: requestContext, messages: [AiChatMessage(role: .user, content: "Hello")])
        let largeDelta = "Anthropic can sometimes deliver a large text delta that would otherwise paint in one frame."
        let providerClient = AiChatProviderExecutionClient(execute: { request, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.started(context: request.context))
                continuation.yield(.delta(context: request.context, text: largeDelta))
                continuation.yield(.final(response: AiChatResponse(
                    context: request.context,
                    assistantMessage: AiChatMessage(role: .assistant, content: largeDelta),
                    completedAtMs: 0,
                )))
                continuation.finish()
            }
        })
        let client = AiChatExecutionClient.live(providerExecutionClient: providerClient)

        var events: [AiChatEvent] = []
        for await event in client.execute(request, nil) {
            events.append(event)
        }

        let deltaTexts = events.compactMap { event -> String? in
            if case let .delta(_, text) = event { return text }
            return nil
        }
        XCTAssertEqual(deltaTexts, [largeDelta])
        XCTAssertEqual(events.last?.isFinalResponse, true)
    }

    func testCompletedRequestHasNoStatusTextAndNextSubmitCanStart() {
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

        let state = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi")
            ],
            draftText: "Second message",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .completed(completedLock),
        )

        XCTAssertNil(state.requestStatusText)
        XCTAssertTrue(state.canSubmit)
    }

    func testOpenSettingsTappedDelegatesOpenAISettingsForNoProviderCTA() async {
        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            providerConnectionSnapshot: .known([]),
        )) {
            AiChatFeature()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

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
}

// swiftlint:enable type_body_length

private extension AiChatEvent {
    var isFinalResponse: Bool {
        if case .final = self { return true }
        return false
    }
}
