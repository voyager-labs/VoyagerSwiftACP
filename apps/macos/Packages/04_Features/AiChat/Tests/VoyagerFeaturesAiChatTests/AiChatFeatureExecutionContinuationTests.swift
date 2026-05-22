import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
// swiftlint:disable:next type_body_length
final class AiChatFeatureExecutionContinuationTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testRegenerateReplacesAssistantWithoutDuplicatingUserTurn() async {
        let stream = AiChatExecutionStreamDriver()
        let persistence = AiChatSessionPersistenceSpy()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111113"))
        let fixedMs: Int64 = 1_700_000_000_300

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(),
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Old answer")
            ],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
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
                saveSession: { snapshot in
                    await persistence.save(snapshot)
                },
                deleteSession: { _ in }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped) { state in
            state.lockedModelHandle = selectedHandle
        }

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }
        let lock = makeRequestLock(
            kind: .regenerate,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: 1
        )

        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello")])
        XCTAssertEqual(store.state.executionPhase, .processing(lock))

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "New answer"),
            completedAtMs: fixedMs
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "New answer")
            ]
            state.lockedModelHandle = nil
            state.executionPhase = .completed(lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false))
        }

        await store.finish()
        XCTAssertEqual(persistence.snapshots.first?.transcriptHistory, [
            AiChatMessage(role: .user, content: "Hello"),
            AiChatMessage(role: .assistant, content: "New answer")
        ])
    }

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
            executionPhase: .idle
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
                deleteSession: { _ in }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello")]
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

        let finalResponse = AiChatResponse(
            context: request.context,
            assistantMessage: AiChatMessage(role: .assistant, content: "Hi"),
            completedAtMs: fixedMs
        )
        stream.yield(.final(response: finalResponse))
        stream.finish()

        let finalizedLock = lock.recordingTerminal(at: fixedMs, failure: nil, wasCancelled: false)
        await store.receive(.executionEvent(.final(response: finalResponse))) { state in
            state.transcriptHistory = [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Hi")
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
            AiChatMessage(role: .assistant, content: "Hi")
        ])
        XCTAssertEqual(store.state.requestStatusText, "Finalized locally; An unknown chat error occurred.")

        await store.finish()
    }

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
                AiChatMessage(role: .assistant, content: "Old answer")
            ],
            draftText: "",
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: missingHandle,
            selectedThinking: .effort(.medium),
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
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped)

        XCTAssertTrue(stream.requests.isEmpty)
        XCTAssertEqual(store.state.executionPhase, .idle)
        XCTAssertNil(store.state.lockedModelHandle)
    }

    func testMakeSessionSnapshotUsesLockedModelAndThinkingInsteadOfNextRequestSelection() {
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111116"))
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let feature = withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_500))
        } operation: {
            AiChatFeature()
        }
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
            executionPhase: .idle
        )

        _ = withDependencies {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_000_500))
        } operation: {
            feature.startRequest(kind: .submit, state: &state)
        }

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

    func testMakeSessionSnapshotDropsProviderNativeBinaryPayloadMetadata() throws {
        let feature = AiChatFeature()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let requestContext = AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(
                references: [
                    AiChatContextReference(
                        kind: .file,
                        identifier: "ref",
                        title: "Reference.pdf",
                        metadata: ["base64Data": "REFERENCE_BYTES", "path": "/tmp/Reference.pdf"]
                    )
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
                                metadata: ["fileDataBase64": "NESTED_BYTES", "path": "/tmp/Nested.pdf"]
                            )
                        ]
                    )
                ],
                attachments: [
                    AiChatContextAttachment(
                        identifier: "current-attachment",
                        title: "CurrentAttachment.pdf",
                        metadata: ["base64Data": "CURRENT_ATTACHMENT_BYTES", "path": "/tmp/CurrentAttachment.pdf"]
                    )
                ]
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
                    ])
                )
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
                        ]
                    ),
                    canonicalPath: "/tmp/Native.pdf",
                    displayPath: "Native.pdf",
                    fileKind: .file,
                    displayTitle: "Native.pdf",
                    byteCount: 128,
                    mimeType: "application/pdf"
                )
            ]
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
            promptSummary: "Hello"
        )
        let request = AiChatRequest(context: context, messages: [AiChatMessage(role: .user, content: "Hello")])
        let lock = makeRequestLock(
            kind: .submit,
            request: request,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )
        let state = AiChatFeature.State(
            sessionID: request.context.sessionID,
            sessionStatus: .active,
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Done")],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(lock)
        )

        let snapshot = feature.makeSessionSnapshot(state: state, lock: lock)
        let persisted = try XCTUnwrap(snapshot.lastRequestContext)

        XCTAssertEqual(persisted.addedAttachments[0].resolutionResult, .resolvedReference(metadata: ["path": "/tmp/Native.pdf"]))
        XCTAssertEqual(persisted.parts[0].resolution, .providerNativeFile(
            kind: .pdf,
            mimeType: "application/pdf",
            metadata: ["path": "/tmp/Native.pdf"]
        ))
        XCTAssertNil(persisted.currentContext.references[0].metadata["base64Data"])
        XCTAssertNil(persisted.currentContext.items[0].metadata["nativeBase64Data"])
        XCTAssertNil(persisted.currentContext.items[0].references[0].metadata["fileDataBase64"])
        XCTAssertNil(persisted.currentContext.attachments[0].metadata["base64Data"])
        XCTAssertEqual(lock.context.requestContext.parts[0].resolution, requestContext.parts[0].resolution)
    }

    // swiftlint:disable:next function_body_length
    func testSubmitFreezesContextTimingAndDeterministicHistoryTruncation() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let models = makeThinkingCapableProviderModels()
        let fixedMs: Int64 = 1_700_000_000_800
        let frozenContext = makeContextSnapshot(summary: "Before submit")
        let largeUser1 = String(repeating: "u", count: 9_000)
        let largeAssistant1 = String(repeating: "a", count: 9_000)
        let largeUser2 = String(repeating: "x", count: 9_000)
        let largeAssistant2 = String(repeating: "y", count: 9_000)
        let draft = "Current prompt"

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111117")),
            sessionStatus: .active,
            currentContext: frozenContext,
            transcriptHistory: [
                AiChatMessage(role: .user, content: largeUser1),
                AiChatMessage(role: .assistant, content: largeAssistant1),
                AiChatMessage(role: .user, content: largeUser2),
                AiChatMessage(role: .assistant, content: largeAssistant2)
            ],
            draftText: draft,
            catalogRows: catalogRows,
            modelListState: .loaded(models),
            selectedModelHandle: catalogRows[0].handle,
            selectedThinking: .effort(.medium),
            lockedModelHandle: nil,
            lastExecutionFailure: nil,
            executionPhase: .idle
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

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.lockedModelHandle = catalogRows[0].handle
        }

        guard let request = stream.requests.first,
              case let .processing(lock) = store.state.executionPhase else {
            return XCTFail("Expected frozen request lock")
        }

        XCTAssertEqual(request.context.currentContext, frozenContext)
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [
            AiChatMessage(role: .user, content: largeUser2),
            AiChatMessage(role: .assistant, content: largeAssistant2),
            AiChatMessage(role: .user, content: draft)
        ])
        XCTAssertEqual(lock.historyTruncation.includedMessageCount, 3)
        XCTAssertEqual(lock.historyTruncation.excludedMessageCount, 2)
        XCTAssertEqual(lock.historyTruncation.budget, 24_000)
        XCTAssertEqual(lock.historyTruncation.truncationReason, .characterBudgetExceeded)
        XCTAssertEqual(lock.observabilitySummary.submittedAtMs, fixedMs)

        await store.send(.selectedThinkingChanged(.effort(.high))) { state in
            state.selectedThinking = .effort(.high)
        }
        XCTAssertEqual(request.context.currentContext.summary, "Before submit")
        XCTAssertEqual(request.context.selectedThinking, .effort(.medium))
    }

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
            executionPhase: .idle
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

        await store.send(.submitTapped) { state in
            state.draftText = ""
            state.transcriptHistory = [AiChatMessage(role: .user, content: "Hello empty context")]
            state.lockedModelHandle = catalogRows[0].handle
        }

        guard let request = stream.requests.first else {
            return XCTFail("Expected request for empty context")
        }

        XCTAssertEqual(request.context.currentContext, .init())
        XCTAssertEqual(request.context.submittedAtMs, fixedMs)
        XCTAssertEqual(request.messages, [AiChatMessage(role: .user, content: "Hello empty context")])
    }

}
