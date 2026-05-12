import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

private let expectedMockAssistantMessage = """
Voyager AI
Context checked.
Plan ready.
Provider later.
✓ Context
✓ Queued
★ Mock ready
"""

final class SettingsOpenSpy: @unchecked Sendable {
    var callCount = 0
}

@MainActor
final class AiChatFeatureExecutionTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testSubmitWithLiveExecutionClientStartsThenFinalizesWithSingleMockAssistantResponse() async {
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
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.aiChatExecutionClient = .liveValue
            $0.aiChatSessionPersistenceClient = AiChatSessionPersistenceClient(
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
            state.selectedModelHandle = selectedHandle
            state.lockedModelHandle = selectedHandle
            state.lastExecutionFailure = nil
            XCTAssertEqual(state.sessionID, sessionID)
        }

        guard case let .processing(lock) = store.state.executionPhase else {
            XCTFail("Expected processing state after submit")
            return
        }

        let expectedResponse = AiChatResponse(
            context: lock.request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: expectedMockAssistantMessage),
            completedAtMs: 0
        )

        await store.receive(.executionEvent(.started(context: lock.request.context)))

        await store.receive(.executionEvent(.final(response: expectedResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: expectedMockAssistantMessage)
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock)
        }

        await store.finish()

        let assistantMessages = store.state.transcriptHistory.filter { $0.role == .assistant }
        XCTAssertEqual(assistantMessages, [AiChatMessage(role: .assistant, content: expectedMockAssistantMessage)])
        XCTAssertEqual(persistence.snapshots.count, 1)
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: expectedMockAssistantMessage)
        ])
        XCTAssertEqual(persistence.snapshots.first?.lastRequestID, lock.request.context.requestID)
        XCTAssertEqual(persistence.snapshots.first?.lastRunID, lock.request.context.runID)
    }

    // swiftlint:disable:next function_body_length
    func testCancelRejectsLateFinalAndFailureEvents() async {
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
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
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
                deleteSession: { _ in }
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
            assistantReplacementIndex: nil
        )

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.cancelTapped) { state in
            state.lockedModelHandle = nil
            state.executionPhase = .cancelled(lock)
        }
        await store.send(.executionEvent(.final(response: AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "late final"),
            completedAtMs: 0
        ))))
        await store.send(.executionEvent(.failed(context: request.context, reason: .unknown)))

        let assistantMessages = store.state.transcriptHistory.filter { $0.role == .assistant }
        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(store.state.transcriptHistory, [AiChatMessage(role: .user, content: "Cancel me")])
        XCTAssertNil(store.state.lockedModelHandle)
        XCTAssertNil(store.state.lastExecutionFailure)
        XCTAssertEqual(store.state.executionPhase, .cancelled(lock))

        await store.finish()
    }

    func testOpenSettingsTappedInvokesSettingsClientWhenDisconnected() async {
        let spy = SettingsOpenSpy()

        let store = TestStore(initialState: AiChatFeature.State()) {
            AiChatFeature()
        } withDependencies: {
            $0.aiChatSettingsClient = AiChatSettingsClient(openSettingsWindow: {
                spy.callCount += 1
                return true
            })
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.openSettingsTapped)

        XCTAssertEqual(spy.callCount, 1)
    }
}
