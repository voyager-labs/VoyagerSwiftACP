import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatRequestContextAttachmentIconDisplayModelTests: XCTestCase {
    func testCurrentContextAttachmentUsesAttachmentIconInsteadOfFolderRouteIcon() {
        let state = AiChatFeature.State(
            currentContext: makeImageAttachmentCurrentContext(),
            addedAttachments: [],
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Screenshot.png")
        XCTAssertEqual(currentContext?.iconSystemName, "paperclip")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }

    func testLockedCurrentContextSelectedFileDoesNotFallbackToFolderReferenceIconPath() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedSelectedImageFileRequestContext()
        let lock = makeImageAttachmentRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionID: lock.context.sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "SCR-20260528-suth.png")
        XCTAssertEqual(currentContext?.iconSystemName, "doc")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }

    func testLockedCurrentContextAttachmentKeepsAttachmentIconDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedImageAttachmentRequestContext()
        let lock = makeImageAttachmentRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionID: lock.context.sessionID,
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Screenshot.png")
        XCTAssertEqual(currentContext?.iconSystemName, "paperclip")
        XCTAssertNil(currentContext?.iconFilePath)
        XCTAssertNil(currentContext?.folderStructureMode)
        XCTAssertEqual(currentContext?.supportsFolderStructureMode, true)
    }
}

private func makeLockedSelectedImageFileRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: AiChatCurrentContextSnapshot(
            summary: "Desktop · 1 selected",
            references: [makeImageAttachmentRouteReference()],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: "/Users/test/Desktop/SCR-20260528-suth.png",
                    title: "SCR-20260528-suth.png",
                    subtitle: "/Users/test/Desktop/SCR-20260528-suth.png",
                    metadata: [
                        "kind": "file",
                        "path": "/Users/test/Desktop/SCR-20260528-suth.png",
                        "selected": "true",
                    ],
                    references: [makeImageAttachmentRouteReference()],
                ),
            ],
            attachments: [],
        ),
        addedAttachments: [],
        parts: [
            makeLockedFolderReferencePart(),
            makeLockedSelectedImageFilePart(),
        ],
    )
}

private func makeLockedFolderReferencePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .referenceOnly(metadata: ["route": "folder"]),
        canonicalPath: "/Users/test/Desktop",
        displayPath: "Desktop",
        fileKind: .reference,
        displayTitle: "Desktop",
    )
}

private func makeLockedSelectedImageFilePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .providerNativeFile(
            kind: .image,
            mimeType: "image/png",
            metadata: ["mimeType": "image/png"],
        ),
        canonicalPath: "/Users/test/Desktop/SCR-20260528-suth.png",
        displayPath: "SCR-20260528-suth.png",
        fileKind: .file,
        displayTitle: "SCR-20260528-suth.png",
        mimeType: "image/png",
    )
}

private func makeImageAttachmentCurrentContext() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Screenshot.png",
        references: [makeImageAttachmentRouteReference()],
        items: [],
        attachments: [makeImageContextAttachment()],
    )
}

private func makeImageAttachmentRouteReference() -> AiChatContextReference {
    AiChatContextReference(
        kind: .reference,
        identifier: "Desktop",
        title: "Desktop",
        subtitle: nil,
        metadata: ["route": "folder", "path": "/Users/test/Desktop"],
    )
}

private func makeImageContextAttachment() -> AiChatContextAttachment {
    AiChatContextAttachment(
        identifier: "/Users/test/Desktop/Screenshot.png",
        title: "Screenshot.png",
        subtitle: "/Users/test/Desktop/Screenshot.png",
        kind: .attachment,
        metadata: ["mimeType": "image/png", "path": "/Users/test/Desktop/Screenshot.png"],
    )
}

private func makeLockedImageAttachmentRequestContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeImageAttachmentCurrentContext(),
        addedAttachments: [],
        parts: [makeLockedImageAttachmentPart()],
    )
}

private func makeLockedImageAttachmentPart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .providerNativeFile(
            kind: .image,
            mimeType: "image/png",
            metadata: ["mimeType": "image/png"],
        ),
        canonicalPath: "/Users/test/Desktop/Screenshot.png",
        displayPath: "Screenshot.png",
        fileKind: .attachment,
        displayTitle: "Screenshot.png",
        mimeType: "image/png",
    )
}

private func makeImageAttachmentRequestLock(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: makeImageAttachmentRequest(
            context: context,
            selectedHandle: selectedHandle,
            selectedRow: selectedRow,
        ),
        selectedHandle: selectedHandle,
        selectedRow: selectedRow,
        assistantReplacementIndex: nil,
    )
}

private func makeImageAttachmentRequest(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequest {
    AiChatRequest(
        context: AiChatRequestContextSnapshot(
            sessionID: AiChatSessionID(rawValue: UUID()),
            requestID: AiChatRequestID(rawValue: UUID()),
            runID: AiChatRunID(rawValue: UUID()),
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: selectedRow,
            sessionStatus: .active,
            currentContext: AiChatCurrentContextSnapshot(summary: "Live context"),
            requestContext: context,
            promptSummary: "Hello",
        ),
        messages: [],
    )
}
