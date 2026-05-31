import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureExecutionFailureTests: XCTestCase {
    func testFailedRequestWithAuthenticationReasonSupportsRetryAndRecovery() async {
        await assertFailureRecovery(reason: .authentication, sessionIDRaw: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    }

    func testFailedRequestWithModelUnavailableReasonSupportsRetryAndRecovery() async {
        await assertFailureRecovery(reason: .modelUnavailable, sessionIDRaw: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    }

    func testFailedRequestWithNetworkReasonSupportsRetryAndRecovery() async {
        await assertFailureRecovery(reason: .network, sessionIDRaw: "cccccccc-cccc-cccc-cccc-cccccccccccc")
    }

    func testSubmitDoesNotStartRequestWhenSelectedModelIsMissingFromLoadedCatalog() async {
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

    // swiftlint:disable:next function_body_length
    private func assertFailureRecovery(reason: AiChatExecutionFailure, sessionIDRaw: String) async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

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
