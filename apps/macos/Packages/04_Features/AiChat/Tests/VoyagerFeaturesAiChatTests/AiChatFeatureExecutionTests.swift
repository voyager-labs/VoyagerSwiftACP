import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW001/CBW003 spec-owner suite 밖에 남긴 provider execution adapter 회귀 테스트.
// connection load failure, raw provider delta, Settings CTA delegation, second submit history contract를 보존한다.

@MainActor
final class AiChatFeatureExecutionTests: XCTestCase {
    /// connections file load 실패가 provider 실행 없이 unknown failure로 전환되는지 검증
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

    /// 두 번째 submit 요청에 이전 assistant turn이 execution request로 포함되는지 검증
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

    /// live execution adapter가 final 전 raw Anthropic delta를 먼저 방출하는지 검증
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

    /// provider 없음 CTA의 Open Settings 동작이 Settings delegate로 전달되는지 검증
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

private extension AiChatEvent {
    var isFinalResponse: Bool {
        if case .final = self { return true }
        return false
    }
}
