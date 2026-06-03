import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

// CBW001/CBW003/CBW005 spec-owner suite로 이관하지 않은 execution continuation 회귀 테스트.
// context freeze, history truncation, persistence failure, session switch cancellation, snapshot redaction contract를
// 보존한다.

// swiftlint:disable type_body_length
@MainActor
final class AiChatFeatureExecutionContinuationTests: XCTestCase {
    // 다른 session을 열람해도 기존 request는 원 session에서 완료되는지 검증
    // swiftlint:disable:next function_body_length
    func testSwitchingToDifferentSessionPreservesCurrentRequestAndSavesOriginalSessionCompletion() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

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

        await store.send(.sessionRowTapped(targetSessionID)) { state in
            state.mode = .sessions
            state.sessionList.selectedSessionID = targetSessionID
            state.restoreSessionID = targetSessionID
            state.currentContextFolderStructureModes = [:]
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
            state.executionPhase = .processing(lock)
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
            .restored(snapshot: activeRestoreSnapshot),
            restoreFailure: nil,
        )) { state in
            state.sessionID = activeSessionID
            state.sessionStatus = .active
            state.transcriptHistory = activeRestoreSnapshot.transcriptHistory
            state.streamingAssistantDraft = nil
            state.lockedModelHandle = nil
            state.lastExecutionFailure = nil
            state.lastRequestContext = activeRestoreSnapshot.lastRequestContext
            state.lastRequestContextModelHandle = nil
            state.addedAttachments = []
            state.currentContextFolderStructureModes = [:]
            state.executionPhase = .processing(lock)
            state.selectedModelHandle = activeRestoreSnapshot.model
            state.selectedThinking = activeRestoreSnapshot.selectedThinking
            state.restoreOutcome = .restored(snapshot: activeRestoreSnapshot)
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
        await store.receive(.sessionSnapshotSaved(expectedOriginalSummary)) { state in
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
        let expectedStartSnapshot = AiChatSessionSnapshot(
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
        XCTAssertEqual(persistence.snapshots, [expectedStartSnapshot, expectedOriginalSnapshot])
    }

    // back-to-sessions 후 같은 session 재진입과 off-chat final completion을 보존하는지 검증
    // swiftlint:disable:next function_body_length
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

    // session 저장 실패가 recovery state로 전환되는지 검증
    // swiftlint:disable:next function_body_length
    func testPersistenceFailureCreatesRecoveryState() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

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

        XCTAssertEqual(store.state.executionPhase, .processing(lock))

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

    // session snapshot 저장 시 provider-native binary payload metadata가 제거되는지 검증
    // swiftlint:disable:next function_body_length
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

    // submit 시 context timing과 deterministic history truncation이 고정되는지 검증
    // swiftlint:disable:next function_body_length
    func testSubmitFreezesContextTimingAndDeterministicHistoryTruncation() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

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

    /// 빈 context 요청도 deterministic submitted timestamp로 준비되는지 검증
    func testEmptyContextStillPreparesRequestWithDeterministicSubmittedTimestamp() async {
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
        store.exhaustivity = .off(showSkippedAssertions: false)

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
}

// swiftlint:enable type_body_length

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool,
    timeout: TimeInterval = 1.0,
    file: StaticString = #filePath,
    line: UInt = #line,
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        await Task.yield()
    }
    if !condition() {
        XCTFail("Timed out waiting for condition", file: file, line: line)
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
