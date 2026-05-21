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
                    source: .collectionDocument,
                    displayTitle: "Workspace.voycoll",
                    filePath: "/tmp/Workspace.voycoll",
                    metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two"],
                    status: .resolved(.resolvedReference(metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two"]))
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
            "Notes.txt", "Workspace", "Pending.txt", "Long.txt", "Broken.txt",
        ])
        XCTAssertEqual(displayModel.addedAttachments.map { $0.statusLabel }, [
            "Included", "Collection paths", "Will upload", "Partial", "Failed",
        ])
        XCTAssertEqual(displayModel.addedAttachments.map { $0.statusDetail }, [
            "Included as text",
            "Collection paths only; contents not included",
            "Will upload when sent",
            "Included first 64 KiB as text",
            "Not sent: brokenReference",
        ])
        XCTAssertEqual(displayModel.addedAttachments[1].iconFilePath, "/tmp/Workspace.voycoll")
        XCTAssertEqual(displayModel.addedAttachments[1].iconAssetName, "voycollFileIcon")
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
        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "ChatGPT Codex",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .chatgptCodex),
            statusDetail: aiChatCurrentContextStatusDetail(for: state.currentContext, destinationProvider: .chatgptCodex)
        )

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconFilePath, "/Users/test/Desktop")
        XCTAssertTrue(currentContextTooltip.contains("Source: Current context"))
        XCTAssertTrue(currentContextTooltip.contains("Destination: ChatGPT Codex"))
        XCTAssertTrue(currentContextTooltip.contains("Status: Reference only"))
        XCTAssertTrue(currentContextTooltip.contains("contents not included"))
    }

    func testCurrentFileContextTooltipMentionsProviderInclusion() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected file",
                references: [],
                items: [
                    makeContextItem(
                        title: "Notes.pdf",
                        metadata: ["path": "/Users/test/Notes.pdf"]
                    ),
                ],
                attachments: []
            ),
            addedAttachments: []
        )

        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "OpenAI",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .openai),
            statusDetail: aiChatCurrentContextStatusDetail(for: state.currentContext, destinationProvider: .openai)
        )

        XCTAssertTrue(currentContextTooltip.contains("Source: Current context"))
        XCTAssertTrue(currentContextTooltip.contains("Status: Included"))
        XCTAssertTrue(currentContextTooltip.contains("provider-native file when supported"))
    }

    func testSelectedCollectionCurrentContextRemovesVoycollExtension() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected collection",
                references: [makeContextReference(title: "Desktop")],
                items: [
                    makeContextItem(
                        title: "Workspace.voycoll",
                        metadata: ["path": "/tmp/Workspace.voycoll"]
                    ),
                ],
                attachments: []
            ),
            addedAttachments: []
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Workspace")
        XCTAssertEqual(currentContext?.iconAssetName, "voycollFileIcon")
    }

    func testCurrentCollectionRouteRemovesVoycollExtension() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Workspace.voycoll",
                references: [
                    makeContextReference(
                        title: "Workspace.voycoll",
                        metadata: ["route": "collection", "path": "/tmp/Workspace.voycoll"]
                    ),
                ],
                items: [],
                attachments: []
            ),
            addedAttachments: []
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Workspace")
        XCTAssertEqual(currentContext?.iconAssetName, "voycollFileIcon")
    }

    func testRequestContextDisplayModelUsesLockedSnapshotDuringProcessingAndTerminalStates() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeContextSnapshot(summary: "Locked request context"),
            addedAttachments: [
                makeLockedAttachment(
                    id: "locked-ref",
                    source: .collectionDocument,
                    displayTitle: "Workspace.voycoll",
                    filePath: "/tmp/Workspace.voycoll",
                    metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two"],
                    result: .resolvedReference(metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two"])
                ),
                makeLockedAttachment(
                    id: "locked-native",
                    displayTitle: "Design.pdf",
                    filePath: "/tmp/Design.pdf",
                    result: .resolvedReference(metadata: [:])
                ),
                makeLockedAttachment(
                    id: "locked-fail",
                    filePath: "/tmp/Secret.txt",
                    result: .failure(reason: .permissionDenied, metadata: [:])
                ),
            ],
            parts: [
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .collectionPathList(
                        paths: ["/tmp/One", "/tmp/Two"],
                        metadata: ["attachmentID": "locked-ref"]
                    ),
                    fileKind: .attachment,
                    displayTitle: "Workspace.voycoll"
                ),
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .providerNativeFile(
                        kind: .pdf,
                        mimeType: "application/pdf",
                        metadata: ["attachmentID": "locked-native"]
                    ),
                    fileKind: .file,
                    displayTitle: "Design.pdf",
                    mimeType: "application/pdf"
                ),
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .failure(
                        reason: .permissionDenied,
                        metadata: ["attachmentID": "locked-fail"]
                    ),
                    fileKind: .file,
                    displayTitle: "Secret.txt"
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
        XCTAssertEqual(processingDisplayModel.addedAttachments.map { $0.title }, ["Workspace", "Design.pdf", "Secret.txt"])
        XCTAssertEqual(processingDisplayModel.addedAttachments.map { $0.statusLabel }, ["Collection paths", "Uploaded/native", "Failed"])
        XCTAssertEqual(processingDisplayModel.addedAttachments.map { $0.statusDetail }, [
            "Collection paths only; contents not included",
            "Uploaded natively as application/pdf",
            "Not sent: permissionDenied",
        ])
        XCTAssertEqual(processingDisplayModel.addedAttachments[0].iconFilePath, "/tmp/Workspace.voycoll")
        XCTAssertEqual(processingDisplayModel.addedAttachments[0].iconAssetName, "voycollFileIcon")
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

    func testContextPartResolutionMapsToClosedChipStates() {
        let fixtures: [(AiChatContextPartResolution, String, String)] = [
            (.inlineText(text: "Hello", metadata: [:]), "Included", "Included as text"),
            (.partialText(text: "Hello", truncated: true, metadata: [:]), "Partial", "Included first 64 KiB as text"),
            (.partialText(text: "Hello", truncated: false, metadata: [:]), "Included", "Included as text"),
            (.referenceOnly(metadata: [:]), "Reference only", "Reference only; contents not included"),
            (
                .referenceOnly(metadata: ["collectionItemPaths": "/tmp/A\n/tmp/B"]),
                "Collection paths",
                "Collection paths only; contents not included"
            ),
            (.collectionPathList(paths: ["/tmp/A", "/tmp/B"], metadata: [:]), "Collection paths", "Collection paths only; contents not included"),
            (
                .providerNativeFile(kind: .plainTextDocument, mimeType: "text/plain", metadata: [:]),
                "Uploaded/native",
                "Uploaded natively as text/plain"
            ),
            (
                .providerNativeFile(kind: .codexPathScope, mimeType: "text/plain", metadata: [:]),
                "Codex path",
                "Codex path reference; not uploaded"
            ),
            (.failure(reason: .unsupportedType, metadata: [:]), "Unsupported", "Not sent: unsupported type"),
            (.failure(reason: .permissionDenied, metadata: [:]), "Failed", "Not sent: permissionDenied"),
        ]

        for (resolution, expectedLabel, expectedDetail) in fixtures {
            XCTAssertEqual(aiChatContextPartStatusLabel(for: resolution), expectedLabel)
            XCTAssertEqual(aiChatContextPartStatusDetail(for: resolution), expectedDetail)
        }
    }
}

private func makeDraftAttachment(
    id: String,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
    status: AiChatAttachmentDraftStatus
) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        currentStatus: status
    )
}

private func makeLockedAttachment(
    id: String,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
    result: AiChatAttachmentResolutionResult
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        resolutionResult: result
    )
}

private func makeContextReference(
    title: String,
    metadata: [String: String] = [:]
) -> AiChatContextReference {
    AiChatContextReference(kind: .reference, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

private func makeContextItem(
    title: String,
    metadata: [String: String] = [:]
) -> AiChatContextItem {
    AiChatContextItem(kind: .file, identifier: title, title: title, subtitle: nil, metadata: metadata)
}
