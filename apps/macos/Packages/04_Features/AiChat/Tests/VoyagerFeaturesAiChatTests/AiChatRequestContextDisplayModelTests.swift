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
        XCTAssertTrue(AiChatStateDisplayModelBuilder(state: emptyState).requestContextDisplayModel.addedAttachments
            .isEmpty)

        let displayModel = AiChatStateDisplayModelBuilder(state: makeLiveStateForGroupSeparation())
            .requestContextDisplayModel
        assertDraftDisplayModelGroupSeparation(displayModel)

        let multiSelectState = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Documents",
                references: [makeContextReference(title: "Documents")],
                items: [
                    makeContextItem(title: "One.txt"),
                    makeContextItem(title: "Two.txt"),
                    makeContextItem(title: "Three.txt"),
                ],
            ),
            addedAttachments: [],
        )
        XCTAssertEqual(
            AiChatStateDisplayModelBuilder(state: multiSelectState).requestContextDisplayModel.currentContext?.title,
            "3 Selected",
        )
    }

    func testCurrentFolderContextUsesFinderFolderIconPath() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Desktop",
                references: [
                    makeContextReference(
                        title: "Desktop",
                        metadata: ["route": "folder", "path": "/Users/test/Desktop"],
                    ),
                ],
                items: [],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext
        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "ChatGPT Codex",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .chatgptCodex),
            statusDetail: aiChatCurrentContextStatusDetail(
                for: state.currentContext,
                destinationProvider: .chatgptCodex,
            ),
        )

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconFilePath, "/Users/test/Desktop")
        XCTAssertTrue(currentContextTooltip.contains("Source: Current context"))
        XCTAssertTrue(currentContextTooltip.contains("Destination: ChatGPT Codex"))
        XCTAssertTrue(currentContextTooltip.contains("Status: Reference only"))
        XCTAssertTrue(currentContextTooltip.contains("contents not included"))
    }

    func testLockedCurrentContextChipUsesResolvedFolderMetadataDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let (state, currentContext) = makeLockedFolderProcessingState(catalogRows: catalogRows)

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconSystemName, "folder")
        XCTAssertEqual(currentContext?.iconFilePath, "/tmp/Desktop")
        XCTAssertEqual(currentContext?.folderStructureMode, .includeSubfolders)
    }

    func testCurrentFileContextDoesNotExposeFolderStructureMode() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected file",
                references: [],
                items: [
                    makeContextItem(
                        title: "Notes.pdf",
                        metadata: ["path": "/Users/test/Notes.pdf", "folderStructureMode": "includeSubfolders"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, false)
    }

    func testCurrentFileContextTooltipMentionsProviderInclusion() {
        let state = AiChatFeature.State(
            currentContext: makeContextSnapshot(
                summary: "Selected file",
                references: [],
                items: [
                    makeContextItem(
                        title: "Notes.pdf",
                        metadata: ["path": "/Users/test/Notes.pdf"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContextTooltip = aiChatRequestContextTooltipText(
            sourceLabel: "Current context",
            destinationLabel: "OpenAI",
            statusLabel: aiChatCurrentContextStatusLabel(for: state.currentContext, destinationProvider: .openai),
            statusDetail: aiChatCurrentContextStatusDetail(for: state.currentContext, destinationProvider: .openai),
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
                        metadata: ["path": "/tmp/Workspace.voycoll"],
                    ),
                ],
                attachments: [],
            ),
            addedAttachments: [],
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
                        metadata: ["route": "collection", "path": "/tmp/Workspace.voycoll"],
                    ),
                ],
                items: [],
                attachments: [],
            ),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Workspace")
        XCTAssertEqual(currentContext?.iconAssetName, "voycollFileIcon")
    }

    func testContextPartResolutionMapsToClosedChipStates() {
        let fixtures = makeContextPartResolutionFixtures()

        for fixture in fixtures {
            XCTAssertEqual(aiChatContextPartStatusLabel(for: fixture.resolution), fixture.expectedLabel)
            XCTAssertEqual(aiChatContextPartStatusDetail(for: fixture.resolution), fixture.expectedDetail)
        }
    }
}

struct ContextPartResolutionFixture {
    let resolution: AiChatContextPartResolution
    let expectedLabel: String
    let expectedDetail: String
}

func makeContextPartResolutionFixtures() -> [ContextPartResolutionFixture] {
    makeContextPartSuccessResolutionFixtures() + makeContextPartFailureResolutionFixtures()
}

func makeContextPartSuccessResolutionFixtures() -> [ContextPartResolutionFixture] {
    [
        ContextPartResolutionFixture(
            resolution: .inlineText(text: "Hello", metadata: [:]),
            expectedLabel: "Included",
            expectedDetail: "Included as text",
        ),
        ContextPartResolutionFixture(
            resolution: .partialText(text: "Hello", truncated: true, metadata: [:]),
            expectedLabel: "Partial",
            expectedDetail: "Included first 64 KiB as text",
        ),
        ContextPartResolutionFixture(
            resolution: .partialText(text: "Hello", truncated: false, metadata: [:]),
            expectedLabel: "Included",
            expectedDetail: "Included as text",
        ),
        ContextPartResolutionFixture(
            resolution: .referenceOnly(metadata: [:]),
            expectedLabel: "Reference only",
            expectedDetail: "Reference only; contents not included",
        ),
        ContextPartResolutionFixture(
            resolution: .referenceOnly(metadata: ["collectionItemPaths": "/tmp/A\n/tmp/B"]),
            expectedLabel: "Collection paths",
            expectedDetail: "Collection paths only; contents not included",
        ),
    ]
}

func makeContextPartFailureResolutionFixtures() -> [ContextPartResolutionFixture] {
    [
        ContextPartResolutionFixture(
            resolution: .collectionPathList(paths: ["/tmp/A", "/tmp/B"], metadata: [:]),
            expectedLabel: "Collection paths",
            expectedDetail: "Collection paths only; contents not included",
        ),
        ContextPartResolutionFixture(
            resolution: .providerNativeFile(kind: .plainTextDocument, mimeType: "text/plain", metadata: [:]),
            expectedLabel: "Uploaded/native",
            expectedDetail: "Uploaded natively as text/plain",
        ),
        ContextPartResolutionFixture(
            resolution: .providerNativeFile(kind: .codexPathScope, mimeType: "text/plain", metadata: [:]),
            expectedLabel: "Codex path",
            expectedDetail: "Codex path reference; not uploaded",
        ),
        ContextPartResolutionFixture(
            resolution: .failure(reason: .unsupportedType, metadata: [:]),
            expectedLabel: "Unsupported",
            expectedDetail: "Not sent: unsupported type",
        ),
        ContextPartResolutionFixture(
            resolution: .failure(reason: .permissionDenied, metadata: [:]),
            expectedLabel: "Failed",
            expectedDetail: "Not sent: permissionDenied",
        ),
    ]
}

func makeDraftAttachment(
    id: String,
    status: AiChatAttachmentDraftStatus,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
) -> AiChatAttachmentDraft {
    AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        currentStatus: status,
    )
}

func makeLockedAttachment(
    id: String,
    result: AiChatAttachmentResolutionResult,
    source: AiChatAttachmentSource = .file,
    displayTitle: String? = nil,
    filePath: String? = nil,
    metadata: [String: String] = [:],
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: source,
        displayTitle: displayTitle,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        metadata: metadata,
        resolutionResult: result,
    )
}

func makeContextReference(
    title: String,
    kind: AiChatContextItemKind = .reference,
    metadata: [String: String] = [:],
) -> AiChatContextReference {
    AiChatContextReference(kind: kind, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

func makeContextItem(
    title: String,
    kind: AiChatContextItemKind = .file,
    metadata: [String: String] = [:],
) -> AiChatContextItem {
    AiChatContextItem(kind: kind, identifier: title, title: title, subtitle: nil, metadata: metadata)
}

func makeLiveStateForGroupSeparation() -> AiChatFeature.State {
    AiChatFeature.State(
        currentContext: makeContextSnapshot(
            summary: "Inspector selection",
            references: [
                makeContextReference(
                    title: "Documents",
                    kind: .folder,
                    metadata: ["path": "/tmp", "folderStructureMode": "includeSubfolders"],
                ),
            ],
            items: [makeContextItem(title: "ProjectPlan.md")],
        ),
        addedAttachments: [
            makeDraftAttachment(
                id: "notes",
                status: .resolved(.resolvedText(text: "Hello", metadata: [:])),
                displayTitle: "Notes.txt",
                metadata: ["folderStructureMode": "includeSubfolders"],
            ),
            makeDraftAttachment(
                id: "folder",
                status: .resolved(.resolvedReference(metadata: [
                    "collectionItemPaths": "/tmp/One\n/tmp/Two",
                    "folderStructureMode": "includeSubfolders",
                ])),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                filePath: "/tmp/Workspace.voycoll",
                metadata: ["collectionItemPaths": "/tmp/One\n/tmp/Two", "folderStructureMode": "includeSubfolders"],
            ),
            makeDraftAttachment(
                id: "pending",
                status: .pending,
                filePath: "/tmp/Pending.txt",
            ),
            makeDraftAttachment(
                id: "partial",
                status: .resolved(.resolvedPartial(text: "Trimmed", truncated: true, metadata: [:])),
                filePath: "/tmp/Long.txt",
            ),
            makeDraftAttachment(
                id: "failed",
                status: .resolved(.failure(reason: .brokenReference, metadata: [:])),
                filePath: "/tmp/Broken.txt",
            ),
        ],
    )
}

func assertDraftDisplayModelGroupSeparation(_ displayModel: AiChatRequestContextDisplayModel) {
    XCTAssertEqual(displayModel.source, AiChatRequestContextDisplaySource.draft)
    XCTAssertEqual(displayModel.currentContext?.title, "ProjectPlan.md")
    XCTAssertEqual(displayModel.addedAttachments.map(\.title), [
        "Notes.txt", "Workspace", "Pending.txt", "Long.txt", "Broken.txt",
    ])
    XCTAssertEqual(displayModel.addedAttachments.map(\.statusLabel), [
        "Included", "Collection paths", "", "Partial", "Failed",
    ])
    XCTAssertEqual(displayModel.addedAttachments.map(\.statusDetail), [
        "Included as text",
        "Collection paths only; contents not included",
        "",
        "Included first 64 KiB as text",
        "Not sent: brokenReference",
    ])
    XCTAssertEqual(displayModel.addedAttachments[1].iconFilePath, "/tmp/Workspace.voycoll")
    XCTAssertEqual(displayModel.addedAttachments[1].iconAssetName, "voycollFileIcon")
    XCTAssertTrue(displayModel.addedAttachments.allSatisfy(\.isRemovable))
    XCTAssertEqual(displayModel.currentContext?.folderStructureMode, .includeSubfolders)
    XCTAssertEqual(displayModel.currentContext?.supportsFolderStructureMode, true)
    XCTAssertEqual(displayModel.addedAttachments[1].folderStructureMode, .includeSubfolders)
}

func makeLockedFolderProcessingState(
    catalogRows: [AiModelCatalogRow],
) -> (state: AiChatFeature.State, currentContext: AiChatCurrentContextChipDisplayModel?) {
    let selectedHandle = catalogRows[0].handle
    let lockedRequestContext = makeDesktopLockedRequestContext()
    let lock = makeRequestLock(
        kind: .submit,
        request: AiChatRequest(
            context: AiChatRequestContextSnapshot(
                sessionID: AiChatSessionID(rawValue: UUID()),
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                provider: selectedHandle.provider,
                model: selectedHandle,
                selectedModelRow: catalogRows[0],
                sessionStatus: .active,
                currentContext: makeContextSnapshot(summary: "Live context"),
                requestContext: lockedRequestContext,
                promptSummary: "Hello",
            ),
            messages: [],
        ),
        selectedHandle: selectedHandle,
        selectedRow: catalogRows[0],
        assistantReplacementIndex: nil,
    )
    let state = AiChatFeature.State(
        sessionStatus: .active,
        catalogRows: catalogRows,
        selectedModelHandle: selectedHandle,
        executionPhase: .processing(lock),
    )
    let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext
    return (state, currentContext)
}

func makeDesktopLockedRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeContextSnapshot(
            summary: "Desktop",
            references: [],
            items: [
                makeContextItem(
                    title: "Desktop",
                    kind: .folder,
                    metadata: ["path": "Desktop"],
                ),
            ],
            attachments: [],
        ),
        addedAttachments: [],
        parts: [
            AiChatLockedContextPartSnapshot(
                source: .currentContext,
                resolution: .referenceOnly(metadata: ["folderStructureMode": "includeSubfolders"]),
                canonicalPath: "/tmp/Desktop",
                displayPath: "Desktop",
                fileKind: .folder,
                displayTitle: "Desktop",
            ),
        ],
    )
}
