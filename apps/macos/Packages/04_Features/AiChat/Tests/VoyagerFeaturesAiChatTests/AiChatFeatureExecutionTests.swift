import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatFeatureExecutionTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testSubmitStreamsDraftOnlyAndFinalizesExactlyOnce() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111111"))

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.streamDraftText = ""
            state.selectedModelHandle = selectedHandle
            state.lockedModelHandle = selectedHandle
            state.lastExecutionFailure = nil
            XCTAssertEqual(state.sessionID, sessionID)
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

        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello")])
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        stream.yield(.streamChunk(context: request.context, delta: "Hel"))
        await store.receive(.executionEvent(.streamChunk(context: request.context, delta: "Hel"))) { state in
            state.streamDraftText = "Hel"
        }

        stream.yield(.streamChunk(context: request.context, delta: "lo"))
        await store.receive(.executionEvent(.streamChunk(context: request.context, delta: "lo"))) { state in
            state.streamDraftText = "Hello"
        }

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hello back"),
            completedAtMs: 0,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.streamDraftText = ""
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hello back")
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock)
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory.count, 2)
        XCTAssertEqual(persistence.snapshots.first?.lastRequestID, request.context.requestID)
        XCTAssertEqual(persistence.snapshots.first?.lastRunID, request.context.runID)
    }

    // swiftlint:disable:next function_body_length
    func testCancelRejectsLateStreamAndFinalEvents() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111112"))

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Cancel me",
            streamDraftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
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

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.streamDraftText = ""
            state.executionPhase = .cancelled(lock)
        }

        await store.send(.executionEvent(.streamChunk(context: request.context, delta: "late")))
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late final"),
            completedAtMs: 0,
        ))))

        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .user, content: "Cancel me")])
        XCTAssertEqual(store.state.streamDraftText, "")
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertEqual(store.state.executionPhase, .cancelled(lock))

        await store.finish()
    }
}
