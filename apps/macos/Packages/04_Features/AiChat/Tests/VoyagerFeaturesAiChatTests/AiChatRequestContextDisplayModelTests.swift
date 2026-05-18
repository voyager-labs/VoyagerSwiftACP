import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatRequestContextDisplayModelTests: XCTestCase {
    func testRequestContextDisplayModelSeparatesGroupsAndHidesEmptyPlaceholder() {
        let emptyState = AiChatFeature.State(currentContext: .init(), addedAttachments: [])
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.isEmpty)
        XCTAssertNil(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.currentContext)
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.addedAttachments.isEmpty)

        let liveState = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Inspector selection",
                references: [makeContextReference(title: "Documents")],
                items: [makeContextItem(title: "ProjectPlan.md")]
            ),
            addedAttachments: [
                makeDraftAttachment(
                    id: "notes",
                    displayTitle: "Notes.txt",
                    status: .resolved(.resolvedText(text: "Hello", metadata: [:]))
                ),
                makeDraftAttachment(
                    id: "folder",
                    filePath: "/tmp/Workspace.voycoll",
                    status: .resolved(.resolvedReference(metadata: [:]))
                ),
                makeDraftAttachment(
                    id: "pending",
                    filePath: "/tmp/Pending.txt",
                    status: .pending
                ),
                makeDraftAttachment(
                    id: "partial",
                    filePath: "/tmp/Long.txt",
                    status: .resolved(.resolvedPartial(text: "Trimmed", truncated: true, metadata: [:]))
                ),
                makeDraftAttachment(
                    id: "failed",
                    filePath: "/tmp/Broken.txt",
                    status: .resolved(.failure(reason: .brokenReference, metadata: [:]))
                ),
            ]
        )

        let displayModel = AiChatStateDisplayModelBuilder(state: liveState).requestContextDisplayModel

        XCTAssertEqual(displayModel.source, AiChatRequestContextDisplaySource.draft)
        XCTAssertEqual(displayModel.currentContext?.title, "ProjectPlan.md")
        XCTAssertEqual(displayModel.addedAttachments.map { $0.title }, [
            "Notes.txt", "Workspace.voycoll", "Pending.txt", "Long.txt", "Broken.txt",
        ])
        XCTAssertEqual(displayModel.addedAttachments.map { $0.statusLabel }, [
            "normal", "참조만 포함 · 내용 미확장", "resolving", "truncated", "failed · brokenReference",
        ])
        XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))

        let multiSelectState = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Documents",
                references: [makeContextReference(title: "Documents")],
                items: [
                    makeContextItem(title: "One.txt"),
                    makeContextItem(title: "Two.txt"),
                    makeContextItem(title: "Three.txt"),
                ]
            ),
            addedAttachments: []
        )
        XCTAssertEqual(AiChatStateDisplayModelBuilder(state: multiSelectState).requestContextDisplayModel.currentContext?.title, "3 Selected")
    }


    func testCurrentFolderContextUsesFinderFolderIconPath() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Desktop",
                references: [
                    makeContextReference(
                        title: "Desktop",
                        metadata: ["route": "folder", "path": "/Users/test/Desktop"]
                    ),
                ],
                items: [],
                attachments: []
            ),
            addedAttachments: []
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconFilePath, "/Users/test/Desktop")
    }

    func testRequestContextDisplayModelUsesLockedSnapshotDuringProcessingAndTerminalStates() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeContextSnapshot(summary: "Locked request context"),
            addedAttachments: [
                makeLockedAttachment(
                    id: "locked-ref",
                    displayTitle: "Workspace.voycoll",
                    result: .resolvedReference(metadata: [:])
                ),
                makeLockedAttachment(
                    id: "locked-fail",
                    filePath: "/tmp/Secret.txt",
                    result: .failure(reason: .permissionDenied, metadata: [:])
                ),
            ]
        )
        let lock = makeRequestLock(
            kind: .submit,
            request: AiChatRequest(
                context: AiChatRequestContextSnapshot(
                    sessionID: AiChatSessionID(rawValue: UUID()),
                    requestID: AiChatRequestID(rawValue: UUID()),
                    runID: AiChatRunID(rawValue: UUID()),
                    provider: selectedHandle.provider,
                    model: selectedHandle,
                    selectedModel: nil,
                    selectedModelRow: catalogRows[0],
                    selectedThinking: nil,
                    sessionStatus: .active,
                    currentContext: makeContextSnapshot(summary: "Live context"),
                    requestContext: lockedRequestContext,
                    promptSummary: "Hello",
                    submittedAtMs: nil
                ),
                messages: []
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )

        let processingState = AiChatFeature.State(
            sessionID: AiChatSessionID(rawValue: UUID()),
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Live context"),
            addedAttachments: [
                makeDraftAttachment(
                    id: "draft-only",
                    displayTitle: "DraftOnly.txt",
                    status: .resolved(.resolvedText(text: "Draft", metadata: [:]))
                ),
            ],
            transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
            draftText: "Follow up",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock)
        )

        let processingDisplayModel = AiChatStateDisplayModelBuilder(state: processingState).requestContextDisplayModel
        XCTAssertEqual(processingDisplayModel.source, AiChatRequestContextDisplaySource.locked)
        XCTAssertEqual(processingDisplayModel.currentContext?.title, "VoyagerEntitiesAi.swift")
        XCTAssertEqual(processingDisplayModel.addedAttachments.map { $0.title }, ["Workspace.voycoll", "Secret.txt"])
        XCTAssertEqual(processingDisplayModel.addedAttachments.map { $0.statusLabel }, ["참조만 포함 · 내용 미확장", "failed · permissionDenied"])
        XCTAssertTrue(processingDisplayModel.addedAttachments.allSatisfy { !$0.isRemovable })

        let completedState = AiChatFeature.State(
            sessionID: processingState.sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(
                summary: "Edited live context",
                references: [makeContextReference(title: "Documents")],
                items: [makeContextItem(title: "LiveOnly.txt")]
            ),
            addedAttachments: [
                makeDraftAttachment(
                    id: "live-only",
                    displayTitle: "LiveOnly.txt",
                    status: .resolved(.resolvedText(text: "Live", metadata: [:]))
                ),
            ],
            transcriptHistory: [AiChatMessage(role: .assistant, content: "Done")],
            draftText: "",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(lock)
        )

        let completedDisplayModel = AiChatStateDisplayModelBuilder(state: completedState).requestContextDisplayModel
        XCTAssertEqual(completedDisplayModel.source, AiChatRequestContextDisplaySource.draft)
        XCTAssertEqual(completedDisplayModel.currentContext?.title, "LiveOnly.txt")
        XCTAssertEqual(completedDisplayModel.addedAttachments.map { $0.title }, ["LiveOnly.txt"])
    }
}

private func makeDraftAttachment(
    id: String,
    displayTitle: String? = nil,
    filePath: String? = nil,
    status: AiChatAttachmentDraftStatus
) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        currentStatus: status
    )
}

private func makeLockedAttachment(
    id: String,
    displayTitle: String? = nil,
    filePath: String? = nil,
    result: AiChatAttachmentResolutionResult
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        resolutionResult: result
    )
}

private func makeContextReference(
    title: String,
    metadata: [String: String] = [:]
) -> AiChatContextReference {
    AiChatContextReference(kind: .reference, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

private func makeContextItem(title: String) -> AiChatContextItem {
    AiChatContextItem(kind: .file, identifier: title, title: title, subtitle: nil, metadata: [:])
}
