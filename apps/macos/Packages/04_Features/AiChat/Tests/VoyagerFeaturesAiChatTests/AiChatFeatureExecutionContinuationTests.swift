import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW-001 spec-owner suite로 이관하지 않은 session continuity와 snapshot contract 회귀 테스트만 남긴다.

@MainActor
final class AiChatFeatureExecutionContinuationTests: XCTestCase {
    /// back-to-sessions 후 같은 session 재진입과 off-chat final completion을 보존하는지 검증
    func testInFlightChatContinuesFromSessionHistoryAndUpdatesSessionRow() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111120"))
        let fixedMs: Int64 = 1_700_000_001_200

        let store = TestStore(initialState: AiChatFeature.State(
            mode: .chat,
            sessionList: .init(selectedSessionID: sessionID, unreadCompletedSessionIDs: [sessionID]),
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello while browsing history",
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
                listSessions: { _, _ in
                    persistence.snapshots.map(AiChatSessionSummary.init(snapshot:))
                },
                loadSession: { _ in nil },
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in },
            )
        }
        // store.exhaustivity = .off: session row 갱신과 unread 마킹만 관찰하고 내부 보조 액션 전부를 열거하지 않기 위함입니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)
        await resolvePendingRequestContext(store) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello while browsing history")]
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
        XCTAssertEqual(store.state.executionPhase, .processing(lock))
        XCTAssertEqual(store.state.sessionList.selectedSessionID, sessionID)
        XCTAssertEqual(store.state.sessionList.unreadCompletedSessionIDs, [])
        XCTAssertEqual(store.state.sessionList.allRows.first?.sessionID, sessionID)
        XCTAssertEqual(store.state.sessionList.allRows.first?.title, "Hello while browsing history")
        XCTAssertEqual(store.state.sessionList.allRows.first?.status, .active)

        let userMessage = AiChatMessage(role: .user, content: "Hello while browsing history")
        let expectedStartSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedStartSummary = AiChatSessionSummary(snapshot: expectedStartSnapshot)
        XCTAssertEqual(expectedStartSummary.title, "Hello while browsing history")
        await store.receive(.sessionSnapshotUpdated(
            expectedStartSummary,
            requestID: lock.requestID,
            runID: lock.runID,
        )) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = []
            state.sessionList.errorMessage = nil
        }

        await store.send(.sessionsAppeared) { state in
            state.mode = .sessions
            state.sessionList.isLoading = true
            state.sessionList.errorMessage = nil
        }
        await store.receive(.sessionListLoaded([expectedStartSummary])) { state in
            state.sessionList.allRows = [expectedStartSummary]
            state.sessionList.rows = [expectedStartSummary]
            state.sessionList.isLoading = false
            state.sessionList.errorMessage = nil
        }

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.sessionRowTapped(sessionID)) { state in
            state.mode = .chat
        }
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        await store.send(.backToSessionsTapped) { state in
            state.mode = .sessions
        }

        let assistantMessage = AiChatMessage(role: .assistant, content: "Still completed")
        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: assistantMessage,
            completedAtMs: fixedMs,
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [userMessage, assistantMessage]
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = lock.context.requestContext
            state.lastRequestContextModelHandle = selectedHandle
            state.executionPhase = .completed(finalizedLock)
            state.transcriptAutoScrollVersion = 2
        }

        let expectedFinalSnapshot = AiChatSessionSnapshot(
            sessionID: sessionID,
            status: .active,
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            transcriptHistory: [userMessage, assistantMessage],
            lastRequestID: lock.requestID,
            lastRunID: lock.runID,
            lastRequestContext: lock.context.requestContext,
            updatedAtMs: fixedMs,
        )
        let expectedFinalSummary = AiChatSessionSummary(snapshot: expectedFinalSnapshot)
        await store.receive(.sessionSnapshotSaved(expectedFinalSummary)) { state in
            state.sessionList.allRows = [expectedFinalSummary]
            state.sessionList.rows = [expectedFinalSummary]
            state.sessionList.selectedSessionID = sessionID
            state.sessionList.unreadCompletedSessionIDs = [sessionID]
            state.sessionList.errorMessage = nil
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots, [expectedStartSnapshot, expectedFinalSnapshot])
    }

    /// 현재 loaded model 목록에 없는 선택 모델로 regenerate가 차단되는지 검증
    func testRegenerateIsBlockedWhenSelectedModelIsNotInCurrentLoadedList() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = [makeThinkingCapableProviderModels()[1]]
        let missingHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111115"))

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Old answer"),
            ],
            draftText: "",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: missingHandle,
            selectedThinking: .effort(.medium),
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
        }
        // store.exhaustivity = .off: regenerate guard가 no-op인지와 request 미생성만 확인하면 충분합니다.
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped)

        XCTAssertTrue(stream.requests.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
    }

    /// session snapshot이 다음 요청 선택값 대신 locked model/thinking을 사용하는지 검증
    func testMakeSessionSnapshotUsesLockedModelAndThinkingInsteadOfNextRequestSelection() async {
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111116"))
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let feature = makeFeatureWithFrozenRequestDependencies()
        var state = AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [],
            draftText: "Hello",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle,
        )

        _ = withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_500))
        } operation: {
            feature.startRequest(kind: .submit, state: &state)
        }

        guard let pendingRequest = state.pendingRequestStart else {
            return XCTFail("Expected pending request context resolution")
        }
        let resolverInput = feature.makeRequestContextResolverInput(for: pendingRequest, state: state)
        let resolvedContext = await AiChatContextPartResolverClient.live().resolve(resolverInput)
        _ = feature.completeRequestContextResolution(
            resolutionID: pendingRequest.resolutionID,
            resolvedContext: resolvedContext,
            state: &state,
        )

        guard case let .processing(lock) = state.executionPhase else {
            return XCTFail("Expected processing lock")
        }

        state.selectedModelHandle = catalogRows[1].handle
        state.selectedThinking = .effort(.minimal)

        let snapshot = feature.makeSessionSnapshot(state: state, lock: lock)

        XCTAssertEqual(lock.context.model, catalogRows[0].handle)
        XCTAssertEqual(lock.context.selectedModel, models[0])
        XCTAssertEqual(lock.context.selectedThinking, .effort(.medium))
        XCTAssertEqual(state.selectedModelHandle, catalogRows[1].handle)
        XCTAssertEqual(state.selectedThinking, .effort(.minimal))
        XCTAssertEqual(snapshot.model, catalogRows[0].handle)
        XCTAssertEqual(snapshot.selectedThinking, AiThinkingSelection.effort(.medium))
        XCTAssertEqual(snapshot.selectedModelRow, catalogRows[0])
    }

    /// session snapshot 저장 시 provider-native binary payload metadata가 제거되는지 검증
    func testMakeSessionSnapshotDropsProviderNativeBinaryPayloadMetadata() throws {
        let feature = makeFeatureWithFrozenRequestDependencies()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let requestContext = AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(
                references: [
                    AiChatContextReference(
                        kind: .file,
                        identifier: "ref",
                        title: "Reference.pdf",
                        metadata: ["base64Data": "REFERENCE_BYTES", "path": "/tmp/Reference.pdf"],
                    ),
                ],
                items: [
                    AiChatContextItem(
                        kind: .file,
                        identifier: "item",
                        title: "Item.pdf",
                        metadata: ["nativeBase64Data": "ITEM_BYTES", "path": "/tmp/Item.pdf"],
                        references: [
                            AiChatContextReference(
                                kind: .file,
                                identifier: "nested",
                                title: "Nested.pdf",
                                metadata: ["fileDataBase64": "NESTED_BYTES", "path": "/tmp/Nested.pdf"],
                            ),
                        ],
                    ),
                ],
                attachments: [
                    AiChatContextAttachment(
                        identifier: "current-attachment",
                        title: "CurrentAttachment.pdf",
                        metadata: ["base64Data": "CURRENT_ATTACHMENT_BYTES", "path": "/tmp/CurrentAttachment.pdf"],
                    ),
                ],
            ),
            addedAttachments: [
                AiChatAttachmentSnapshot(
                    id: AiChatAttachmentID(rawValue: "native-attachment"),
                    source: .file,
                    displayTitle: "Native.pdf",
                    sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Native.pdf"),
                    metadata: ["nativeBase64Data": "ATTACHMENT_METADATA_BYTES"],
                    resolutionResult: .resolvedReference(metadata: [
                        "base64Data": "ATTACHMENT_RESULT_BYTES",
                        "path": "/tmp/Native.pdf",
                    ]),
                ),
            ],
            parts: [
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .providerNativeFile(
                        kind: .pdf,
                        mimeType: "application/pdf",
                        metadata: [
                            "base64Data": "PART_BYTES",
                            "nativeBase64Data": "PART_NATIVE_BYTES",
                            "fileDataBase64": "PART_FILE_BYTES",
                            "path": "/tmp/Native.pdf",
                        ],
                    ),
                    canonicalPath: "/tmp/Native.pdf",
                    displayPath: "Native.pdf",
                    fileKind: .file,
                    displayTitle: "Native.pdf",
                    byteCount: 128,
                    mimeType: "application/pdf",
                ),
            ],
        )
        let context = AiChatRequestContextSnapshot(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111161")),
            requestID: AiChatRequestID(rawValue: makeUUID("11111111-1111-1111-1111-111111111162")),
            runID: AiChatRunID(rawValue: makeUUID("11111111-1111-1111-1111-111111111163")),
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModel: makeProviderModels()[0],
            selectedModelRow: catalogRows[0],
            sessionStatus: .active,
            requestContext: requestContext,
            promptSummary: "Hello",
        )
        let request = AiChatRequest(context: context, messages: [AiChatMessage(role: .user, content: "Hello")])
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )
        let state = AiChatFeature.State(
            sessionID: request.context.sessionID,
            sessionStatus: .active,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Done")],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(lock),
        )

        let snapshot = feature.makeSessionSnapshot(state: state, lock: lock)
        let persisted = try XCTUnwrap(snapshot.lastRequestContext)

        XCTAssertEqual(
            persisted.addedAttachments[0].resolutionResult,
            .resolvedReference(metadata: ["path": "/tmp/Native.pdf"]),
        )
        XCTAssertEqual(persisted.parts[0].resolution, .providerNativeFile(
            kind: .pdf,
            mimeType: "application/pdf",
            metadata: ["path": "/tmp/Native.pdf"],
        ))
        XCTAssertNil(persisted.currentContext.references[0].metadata["base64Data"])
        XCTAssertNil(persisted.currentContext.items[0].metadata["nativeBase64Data"])
        XCTAssertNil(persisted.currentContext.items[0].references[0].metadata["fileDataBase64"])
        XCTAssertNil(persisted.currentContext.attachments[0].metadata["base64Data"])
        XCTAssertEqual(lock.context.requestContext.parts[0].resolution, requestContext.parts[0].resolution)
    }
}

private func makeFeatureWithFrozenRequestDependencies() -> AiChatFeature {
    withDependencies {
        $0.uuid = .incrementing
        $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_500))
    } operation: {
        AiChatFeature()
    }
}
