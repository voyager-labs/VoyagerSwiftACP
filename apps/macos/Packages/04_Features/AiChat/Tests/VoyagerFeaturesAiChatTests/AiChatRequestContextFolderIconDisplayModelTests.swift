import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatRequestContextFolderIconDisplayModelTests: XCTestCase {
    func testLockedFolderReferenceUsesFinderIconPathDuringProcessing() {
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let lockedRequestContext = makeLockedFolderReferenceContext()
        let lock = makeFolderIconRequestLock(
            context: lockedRequestContext,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
        )
        let state = AiChatFeature.State(
            sessionStatus: .active,
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .processing(lock),
        )

        let currentContext = AiChatStateDisplayModelBuilder(state: state).requestContextDisplayModel.currentContext

        XCTAssertEqual(currentContext?.title, "Desktop")
        XCTAssertEqual(currentContext?.iconSystemName, "folder")
        XCTAssertEqual(currentContext?.iconFilePath, "/tmp/Desktop")
        XCTAssertEqual(currentContext?.folderStructureMode, .includeSubfolders)
    }
}

private func makeLockedFolderReferenceContext() -> AiChatLockedRequestContextSnapshot {
    AiChatLockedRequestContextSnapshot(
        currentContext: makeFolderIconContextSnapshot(),
        addedAttachments: [],
        parts: [makeLockedFolderReferencePart()],
    )
}

private func makeFolderIconContextSnapshot() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Desktop",
        references: [
            AiChatContextReference(
                kind: .reference,
                identifier: "Desktop",
                title: "Desktop",
                subtitle: nil,
                metadata: ["route": "folder", "path": "Desktop"],
            ),
        ],
        items: [],
        attachments: [],
    )
}

private func makeLockedFolderReferencePart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .currentContext,
        resolution: .referenceOnly(metadata: [
            "route": "folder",
            "folderStructureMode": "includeSubfolders",
        ]),
        canonicalPath: "/tmp/Desktop",
        displayPath: "Desktop",
        fileKind: .reference,
        displayTitle: "Desktop",
    )
}

private func makeFolderIconRequestLock(
    context: AiChatLockedRequestContextSnapshot,
    selectedHandle: AiModelHandle,
    selectedRow: AiModelCatalogRow,
) -> AiChatRequestLock {
    makeRequestLock(
        kind: .submit,
        request: makeFolderIconRequest(
            context: context,
            selectedHandle: selectedHandle,
            selectedRow: selectedRow,
        ),
        selectedHandle: selectedHandle,
        selectedRow: selectedRow,
        assistantReplacementIndex: nil,
    )
}

private func makeFolderIconRequest(
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
