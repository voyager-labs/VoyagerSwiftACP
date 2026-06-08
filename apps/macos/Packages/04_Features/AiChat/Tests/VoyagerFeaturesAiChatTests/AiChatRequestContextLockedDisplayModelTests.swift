import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatRequestContextLockedDisplayModelTests: XCTestCase {
    func testRequestContextDisplayModelUsesLockedSnapshotDuringProcessingAndTerminalStates() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedRequestContextForDisplayTest()
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
                    submittedAtMs: nil,
                ),
                messages: [],
            ),
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil,
        )

        let processingState = makeProcessingDisplayModelState(
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            lock: lock,
        )

        let processingDisplayModel = AiChatStateDisplayModelBuilder(state: processingState).requestContextDisplayModel
        assertProcessingLockedDisplayModel(processingDisplayModel)

        let completedState = makeCompletedDisplayModelState(
            processingState: processingState,
            catalogRows: catalogRows,
            selectedHandle: selectedHandle,
            lock: lock,
        )

        let completedDisplayModel = AiChatStateDisplayModelBuilder(state: completedState).requestContextDisplayModel
        XCTAssertEqual(completedDisplayModel.source, AiChatRequestContextDisplaySource.draft)
        XCTAssertEqual(completedDisplayModel.currentContext?.title, "LiveOnly.txt")
        XCTAssertEqual(completedDisplayModel.addedAttachments.map(\.title), ["LiveOnly.txt"])
    }
}

func makeLockedRequestContextForDisplayTest() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeContextSnapshot(
            summary: "Locked request context",
            references: [
                makeContextReference(
                    title: "Locked request context",
                    metadata: ["folderStructureMode": "includeSubfolders"],
                ),
            ],
        ),
        addedAttachments: makeLockedDisplayTestAttachments(),
        parts: makeLockedDisplayTestParts(),
    )
}

func makeLockedDisplayTestAttachments() -> [AiChatAttachmentSnapshot] {
    [
        makeLockedAttachment(
            id: "locked-ref",
            result: .resolvedReference(metadata: [
                "collectionItemPaths": "/tmp/One\n/tmp/Two",
                "folderStructureMode": "includeSubfolders",
            ]),
            source: .collectionDocument,
            displayTitle: "Workspace.voycoll",
            filePath: "/tmp/Workspace.voycoll",
            metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two", "folderStructureMode": "includeSubfolders"],
        ),
        makeLockedAttachment(
            id: "locked-native",
            result: .resolvedReference(metadata: [:]),
            displayTitle: "Design.pdf",
            filePath: "/tmp/Design.pdf",
        ),
        makeLockedAttachment(
            id: "locked-fail",
            result: .failure(reason: .permissionDenied, metadata: [:]),
            filePath: "/tmp/Secret.txt",
        ),
    ]
}

func makeLockedDisplayTestParts() -> [AiChatLockedContextPartSnapshot] {
    [
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .collectionPathList(
                paths: ["/tmp/One", "/tmp/Two"],
                metadata: ["attachmentID": "locked-ref", "folderStructureMode": "includeSubfolders"],
            ),
            fileKind: .attachment,
            displayTitle: "Workspace.voycoll",
        ),
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .providerNativeFile(
                kind: .pdf,
                mimeType: "application/pdf",
                metadata: ["attachmentID": "locked-native"],
            ),
            fileKind: .file,
            displayTitle: "Design.pdf",
            mimeType: "application/pdf",
        ),
        AiChatLockedContextPartSnapshot(
            source: .attachment,
            resolution: .failure(
                reason: .permissionDenied,
                metadata: ["attachmentID": "locked-fail"],
            ),
            fileKind: .file,
            displayTitle: "Secret.txt",
        ),
    ]
}

func makeProcessingDisplayModelState(
    catalogRows: [AiModelCatalogRow],
    selectedHandle: AiModelHandle,
    lock: AiChatRequestLock,
) -> AiChatFeature.State {
    AiChatFeature.State(
        sessionID: AiChatSessionID(rawValue: UUID()),
        sessionStatus: .active,
        currentContext: makeContextSnapshot(summary: "Live context"),
        addedAttachments: [
            makeDraftAttachment(
                id: "draft-only",
                status: .resolved(.resolvedText(text: "Draft", metadata: [:])),
                displayTitle: "DraftOnly.txt",
            ),
        ],
        transcriptHistory: [AiChatMessage(role: .user, content: "Hello")],
        draftText: "Follow up",
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .processing(lock),
    )
}

func assertProcessingLockedDisplayModel(_ displayModel: AiChatRequestContextDisplayModel) {
    XCTAssertEqual(displayModel.source, AiChatRequestContextDisplaySource.locked)
    XCTAssertEqual(displayModel.currentContext?.title, "VoyagerEntitiesAi.swift")
    XCTAssertEqual(displayModel.addedAttachments.map(\.title), ["Workspace", "Design.pdf", "Secret.txt"])
    XCTAssertEqual(
        displayModel.addedAttachments.map(\.statusLabel),
        ["Collection paths", "Uploaded/native", "Failed"],
    )
    XCTAssertEqual(displayModel.addedAttachments.map(\.statusDetail), [
        "Collection paths only; contents not included",
        "Uploaded natively as application/pdf",
        "Not sent: permissionDenied",
    ])
    XCTAssertEqual(displayModel.addedAttachments[0].iconFilePath, "/tmp/Workspace.voycoll")
    XCTAssertEqual(displayModel.addedAttachments[0].iconAssetName, "voycollFileIcon")
    XCTAssertTrue(displayModel.addedAttachments.allSatisfy { !$0.isRemovable })
    XCTAssertNil(displayModel.currentContext?.folderStructureMode)
    XCTAssertEqual(displayModel.currentContext?.supportsFolderStructureMode, false)
    XCTAssertEqual(displayModel.addedAttachments[0].folderStructureMode, .includeSubfolders)
}

func makeCompletedDisplayModelState(
    processingState: AiChatFeature.State,
    catalogRows: [AiModelCatalogRow],
    selectedHandle: AiModelHandle,
    lock: AiChatRequestLock,
) -> AiChatFeature.State {
    AiChatFeature.State(
        sessionID: processingState.sessionID,
        sessionStatus: .active,
        currentContext: makeCompletedLiveContextSnapshot(),
        addedAttachments: makeCompletedLiveAttachments(),
        transcriptHistory: [AiChatMessage(role: .assistant, content: "Done")],
        draftText: "",
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .completed(lock),
    )
}

func makeCompletedLiveContextSnapshot() -> AiChatContextSnapshot {
    makeContextSnapshot(
        summary: "Edited live context",
        references: [
            makeContextReference(
                title: "Documents",
                metadata: ["folderStructureMode": "includeSubfolders"],
            ),
        ],
        items: [makeContextItem(title: "LiveOnly.txt")],
    )
}

func makeCompletedLiveAttachments() -> [AiChatAttachmentDraft] {
    [
        makeDraftAttachment(
            id: "live-only",
            status: .resolved(.resolvedText(text: "Live", metadata: [:])),
            displayTitle: "LiveOnly.txt",
            metadata: ["folderStructureMode": "includeSubfolders"],
        ),
    ]
}
