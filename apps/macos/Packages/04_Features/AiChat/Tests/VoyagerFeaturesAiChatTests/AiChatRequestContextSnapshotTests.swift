import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
@testable import VoyagerFeaturesAiChat
import XCTest

@MainActor
final class AiChatRequestContextSnapshotTests: XCTestCase {
    func testSubmitLocksResolvedPickerAttachmentsIntoRequestContextSnapshot() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("Notes.txt")
        try "File note body".write(to: fileURL, atomically: true, encoding: .utf8)

        let folderURL = sandbox.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "Folder file body".write(
            to: folderURL.appendingPathComponent("Inside.md"),
            atomically: true,
            encoding: .utf8
        )

        let collectionURL = sandbox.appendingPathComponent("Workspace.voycoll")
        try "Collection body".write(to: collectionURL, atomically: true, encoding: .utf8)

        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111151"))

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Current folder"),
            addedAttachments: [
                makeDraftAttachment(url: fileURL, source: .file),
                makeDraftAttachment(url: folderURL, source: .folder),
                makeDraftAttachment(url: collectionURL, source: .collectionDocument),
            ],
            draftText: "Summarize these",
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_000))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { .empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(.empty()) }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.submitTapped)

        guard let request = stream.requests.first else {
            XCTFail("Expected execution request")
            return
        }

        let attachments = request.context.requestContext.addedAttachments
        XCTAssertEqual(attachments.map(\.source), [.file, .folder, .collectionDocument])
        XCTAssertEqual(attachments.map(\.displayTitle), ["Notes.txt", "Folder", "Workspace.voycoll"])

        XCTAssertResolvedText(attachments[0].resolutionResult, contains: "File note body")
        XCTAssertResolvedReference(attachments[1].resolutionResult)
        XCTAssertResolvedReference(attachments[2].resolutionResult)
    }

    func testRegenerateReusesOriginalLockedRequestContextSnapshot() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111152"))
        let originalLockedContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeContextSnapshot(summary: "Original selection"),
            addedAttachments: [
                AiChatAttachmentSnapshot(
                    id: AiChatAttachmentID(rawValue: "original"),
                    source: .file,
                    displayTitle: "Original.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Original.txt"),
                    resolutionResult: .resolvedText(text: "Original content", metadata: [:])
                )
            ]
        )
        let originalRequestContext = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222222222")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333333333")),
            provider: selectedHandle.provider,
            model: selectedHandle,
            selectedModelRow: catalogRows[0],
            sessionStatus: .active,
            currentContext: originalLockedContext.currentContext,
            requestContext: originalLockedContext,
            promptSummary: "Hello",
            submittedAtMs: 1_700_000_000_000
        )
        let originalRequest = AiChatRequest(
            context: originalRequestContext,
            messages: [AiChatMessage(role: .user, content: "Hello")]
        )
        let completedLock = makeRequestLock(
            kind: .submit,
            request: originalRequest,
            selectedHandle: selectedHandle,
            selectedRow: catalogRows[0],
            assistantReplacementIndex: nil
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Changed live selection"),
            addedAttachments: [makeDraftAttachment(url: URL(fileURLWithPath: "/tmp/Changed.txt"), source: .file)],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Hello"),
                AiChatMessage(role: .assistant, content: "Old answer"),
            ],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            executionPhase: .completed(completedLock)
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_500))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { .empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(.empty()) }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped)

        guard let request = stream.requests.first else {
            XCTFail("Expected regenerate request")
            return
        }
        XCTAssertEqual(request.context.requestContext, originalLockedContext)
        XCTAssertEqual(request.context.currentContext.summary, "Original selection")
        XCTAssertEqual(request.context.requestContext.addedAttachments.map(\.displayTitle), ["Original.txt"])
    }

    func testRegenerateAfterRestoreReusesPersistedLockedRequestContextSnapshot() async {
        let stream = AiChatExecutionStreamDriver()
        let catalogRows = makeCatalogRows()
        let selectedHandle = catalogRows[0].handle
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111153"))
        let restoredLockedContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeContextSnapshot(summary: "Restored original context"),
            addedAttachments: [
                AiChatAttachmentSnapshot(
                    id: AiChatAttachmentID(rawValue: "restored"),
                    source: .file,
                    displayTitle: "Restored.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Restored.txt"),
                    resolutionResult: .resolvedText(text: "Restored content", metadata: [:])
                )
            ]
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Live after restore"),
            addedAttachments: [makeDraftAttachment(url: URL(fileURLWithPath: "/tmp/Live.txt"), source: .file)],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Restore question"),
                AiChatMessage(role: .assistant, content: "Old restored answer"),
            ],
            catalogRows: catalogRows,
            selectedModelHandle: selectedHandle,
            lastRequestContext: restoredLockedContext,
            executionPhase: .idle
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_800))
            $0.aiChatExecutionClient = AiChatExecutionClient(execute: { request in
                stream.stream(for: request)
            })
            $0.aiConnectionsFileClient = AIConnectionsFileClient(
                load: { .empty() },
                save: { .success($0) },
                deleteCredential: { _ in .success(.empty()) }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.regenerateTapped)

        guard let request = stream.requests.first else {
            XCTFail("Expected regenerate request")
            return
        }
        XCTAssertEqual(request.context.requestContext, restoredLockedContext)
        XCTAssertEqual(request.context.currentContext.summary, "Restored original context")
        XCTAssertEqual(request.context.requestContext.addedAttachments.map(\.displayTitle), ["Restored.txt"])
    }

}

private func makeDraftAttachment(url: URL, source: AiChatAttachmentSource) -> AiChatAttachmentDraft {
    let normalizedURL = url.standardizedFileURL
    return AiChatAttachmentDraft(
        id: AiChatAttachmentID(rawValue: normalizedURL.path(percentEncoded: false)),
        source: source,
        displayTitle: normalizedURL.lastPathComponent,
        sourceLocation: AiChatAttachmentSourceLocation(
            fileURL: normalizedURL,
            filePath: normalizedURL.path(percentEncoded: false)
        )
    )
}

private func XCTAssertResolvedText(
    _ result: AiChatAttachmentResolutionResult,
    contains expectedText: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case let .resolvedText(text, _), let .resolvedPartial(text, _, _):
        XCTAssertTrue(text.contains(expectedText), file: file, line: line)
    default:
        XCTFail("Expected resolved text, got \\(result)", file: file, line: line)
    }
}


private func XCTAssertResolvedReference(
    _ result: AiChatAttachmentResolutionResult,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case .resolvedReference:
        break
    default:
        XCTFail("Expected resolved reference, got \(result)", file: file, line: line)
    }
}
