import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerShared
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
        try writeCollectionFile(
            to: collectionURL,
            name: "Workspace",
            snapshotPaths: [
                sandbox.appendingPathComponent("README.md").path,
                sandbox.appendingPathComponent("design.pdf").path,
            ]
        )

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
        XCTAssertResolvedReference(
            attachments[1].resolutionResult,
            collectionPaths: ["Inside.md"],
            included: 1,
            truncated: false
        )
        XCTAssertResolvedReference(
            attachments[2].resolutionResult,
            collectionPaths: ["README.md", "design.pdf"],
            included: 2,
            truncated: false
        )
        XCTAssertEqual(request.context.requestContext.parts.map(\.source), [.attachment, .attachment, .attachment])
        XCTAssertEqual(request.context.requestContext.parts.map(\.displayTitle), ["Notes.txt", "Folder", "Workspace.voycoll"])
    }

    func testSubmitKeepsUnreadableCollectionReferenceWithoutItemPaths() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let collectionURL = sandbox.appendingPathComponent("Broken.voycoll")
        try "not a collection".write(to: collectionURL, atomically: true, encoding: .utf8)

        let request = await submitRequest(attachments: [makeDraftAttachment(url: collectionURL, source: .collectionDocument)])
        let attachment = try XCTUnwrap(request.context.requestContext.addedAttachments.first)
        XCTAssertResolvedReference(attachment.resolutionResult, collectionSnapshotStatus: "unreadable")
    }

    func testSubmitTruncatesCollectionReferenceItemPathsByUTF8Budget() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let paths = (0..<2_000).map { index in
            let filename = "VeryLongCollectionReferencePath_\(index)_"
                + String(repeating: "x", count: 80)
                + ".swift"
            return sandbox.appendingPathComponent(filename).path
        }
        let expectedPaths = collectionPathsWithinUTF8Budget(paths, budget: 64 * 1024)
        XCTAssertLessThan(expectedPaths.count, paths.count)

        let collectionURL = sandbox.appendingPathComponent("Large.voycoll")
        try writeCollectionFile(to: collectionURL, name: "Large", snapshotPaths: paths)

        let request = await submitRequest(attachments: [makeDraftAttachment(url: collectionURL, source: .collectionDocument)])
        let attachment = try XCTUnwrap(request.context.requestContext.addedAttachments.first)
        XCTAssertResolvedReference(
            attachment.resolutionResult,
            collectionPaths: redactedDisplayPaths(expectedPaths),
            included: expectedPaths.count,
            truncated: true,
            utf8ByteBudget: 64 * 1024,
            utf8Bytes: redactedDisplayPaths(expectedPaths).joined(separator: "\n").utf8.count
        )
    }

    func testSubmitCountsCollectionReferenceItemPathsAgainstTotalAttachmentBudget() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("LargeNotes.txt")
        try String(repeating: "a", count: 80 * 1024).write(to: fileURL, atomically: true, encoding: .utf8)

        let paths = (0..<2_000).map { index in
            let filename = "TotalBudgetCollectionReferencePath_\(index)_"
                + String(repeating: "x", count: 80)
                + ".swift"
            return sandbox.appendingPathComponent(filename).path
        }
        let expectedPaths = collectionPathsWithinUTF8Budget(paths, budget: 64 * 1024)
        XCTAssertLessThan(expectedPaths.count, paths.count)

        let collectionURL = sandbox.appendingPathComponent("Budgeted.voycoll")
        try writeCollectionFile(to: collectionURL, name: "Budgeted", snapshotPaths: paths)

        let request = await submitRequest(attachments: [
            makeDraftAttachment(url: fileURL, source: .file),
            makeDraftAttachment(url: collectionURL, source: .collectionDocument),
        ])
        let attachments = request.context.requestContext.addedAttachments
        XCTAssertEqual(attachments.map(\.displayTitle), ["LargeNotes.txt", "Budgeted.voycoll"])
        XCTAssertResolvedPartial(attachments[0].resolutionResult)
        XCTAssertResolvedReference(
            attachments[1].resolutionResult,
            collectionPaths: redactedDisplayPaths(expectedPaths),
            included: expectedPaths.count,
            truncated: true,
            utf8ByteBudget: 64 * 1024,
            utf8Bytes: redactedDisplayPaths(expectedPaths).joined(separator: "\n").utf8.count
        )
    }


    func testSubmitTruncatedUTF8AttachmentBacksUpToValidScalarBoundary() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("MultibyteNotes.txt")
        let prefix = String(repeating: "a", count: 64 * 1024 - 1)
        try (prefix + "😀 trailing").write(to: fileURL, atomically: true, encoding: .utf8)

        let request = await submitRequest(attachments: [makeDraftAttachment(url: fileURL, source: .file)])
        let attachment = try XCTUnwrap(request.context.requestContext.addedAttachments.first)

        switch attachment.resolutionResult {
        case let .resolvedPartial(text, truncated, _):
            XCTAssertTrue(truncated)
            XCTAssertEqual(text, prefix)
            XCTAssertLessThanOrEqual(text.utf8.count, 64 * 1024)
        default:
            XCTFail("Expected resolvedPartial, got \(attachment.resolutionResult)")
        }
    }

    func testSubmitBoundsLargeUTF8AttachmentReadToTextBudget() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("HugeNotes.txt")
        try String(repeating: "h", count: 256 * 1024).write(to: fileURL, atomically: true, encoding: .utf8)

        let request = await submitRequest(attachments: [makeDraftAttachment(url: fileURL, source: .file)])
        let attachment = try XCTUnwrap(request.context.requestContext.addedAttachments.first)

        switch attachment.resolutionResult {
        case let .resolvedPartial(text, truncated, _):
            XCTAssertTrue(truncated)
            XCTAssertLessThanOrEqual(text.utf8.count, 64 * 1024)
            XCTAssertEqual(text, String(repeating: "h", count: 64 * 1024))
        default:
            XCTFail("Expected resolvedPartial, got \(attachment.resolutionResult)")
        }
    }

    func testSubmitDedupesCurrentContextCanonicalPathWhenAttachmentTargetsSameFile() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("Notes.txt")
        try "same file body".write(to: fileURL, atomically: true, encoding: .utf8)

        let symlinkURL = sandbox.appendingPathComponent("Alias.txt")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: fileURL)

        let currentContext = makeContextSnapshot(
            summary: "Current duplicate file",
            references: [],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: symlinkURL.path(percentEncoded: false),
                    title: "Alias.txt",
                    subtitle: nil,
                    metadata: ["path": symlinkURL.path(percentEncoded: false)]
                )
            ],
            attachments: []
        )

        let request = await submitRequest(
            currentContext: currentContext,
            attachments: [makeDraftAttachment(url: fileURL, source: .file)]
        )

        XCTAssertEqual(request.context.requestContext.addedAttachments.count, 1)
        XCTAssertTrue(request.context.requestContext.currentContext.items.isEmpty)
        XCTAssertResolvedText(
            try XCTUnwrap(request.context.requestContext.addedAttachments.first).resolutionResult,
            contains: "same file body"
        )
    }

    func testRemoteCurrentContextCollectionIncludesSnapshotItemPaths() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let readmeURL = sandbox.appendingPathComponent("README.md")
        let designURL = sandbox.appendingPathComponent("Design.pdf")
        let collectionURL = sandbox.appendingPathComponent("Workspace.voycoll")
        try writeCollectionFile(
            to: collectionURL,
            name: "Workspace",
            snapshotPaths: [readmeURL.path, designURL.path]
        )

        let currentContext = makeContextSnapshot(
            summary: "Current collection",
            references: [],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: collectionURL.path(percentEncoded: false),
                    title: "Workspace.voycoll",
                    subtitle: collectionURL.path(percentEncoded: false),
                    metadata: ["path": collectionURL.path(percentEncoded: false)]
                )
            ],
            attachments: []
        )

        let result = AiChatContextPartResolverClient.live().resolve(
            AiChatContextPartResolverInput(
                provider: .openai,
                rawModelID: "gpt-4.1-mini",
                requestFamily: .openAIResponses,
                currentContext: currentContext,
                attachments: []
            )
        )

        XCTAssertEqual(result.parts.count, 1)
        guard case let .referenceOnly(metadata) = result.parts[0].resolution else {
            XCTFail("Expected current context collection to resolve as referenceOnly")
            return
        }
        XCTAssertEqual(metadata["collectionSnapshotStatus"], "usable")
        XCTAssertEqual(metadata["collectionItemCount"], "2")
        XCTAssertEqual(metadata["collectionItemsIncluded"], "2")
        XCTAssertEqual(metadata["collectionItemsTruncated"], "false")
        XCTAssertEqual(
            metadata["collectionItemPaths"]?.split(separator: "\n").map(String.init),
            ["README.md", "Design.pdf"]
        )
    }

    func testRemoteCurrentContextSelectedFileUsesProviderNativeBase64AndRedactedPathMetadata() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("Notes.txt")
        try "remote current context body".write(to: fileURL, atomically: true, encoding: .utf8)

        let currentContext = makeContextSnapshot(
            summary: "Remote selected file",
            references: [],
            items: [
                AiChatContextItem(
                    kind: .file,
                    identifier: fileURL.path(percentEncoded: false),
                    title: "Notes.txt",
                    subtitle: fileURL.path(percentEncoded: false),
                    metadata: ["path": fileURL.path(percentEncoded: false)]
                )
            ],
            attachments: []
        )

        let models = makeProviderModels()
        let rows = makeCatalogRows()
        let cases: [(AiProviderModel, AiModelCatalogRow, AiChatContextPartResolverRequestFamily)] = [
            (models[0], rows[0], .openAIResponses),
            (models[1], rows[1], .anthropicMessages),
        ]

        for (model, row, requestFamily) in cases {
            let result = AiChatContextPartResolverClient.live().resolve(
                AiChatContextPartResolverInput(
                    provider: model.provider,
                    rawModelID: model.rawModelID,
                    requestFamily: requestFamily,
                    currentContext: currentContext,
                    attachments: []
                )
            )

            XCTAssertTrue(result.addedAttachments.isEmpty)
            XCTAssertEqual(result.currentContext.items.count, 1)
            XCTAssertEqual(result.currentContext.items[0].metadata["path"], "Notes.txt")
            XCTAssertFalse(result.currentContext.items[0].identifier.hasPrefix("/"))
            XCTAssertEqual(result.parts.count, 1)
            guard case let .providerNativeFile(kind, mimeType, metadata) = result.parts[0].resolution else {
                XCTFail("Expected remote current context to use providerNativeFile for \(model.provider)")
                continue
            }
            XCTAssertEqual(kind, .plainTextDocument)
            XCTAssertEqual(mimeType, "text/plain")
            XCTAssertEqual(metadata["displayPath"], "Notes.txt")
            XCTAssertEqual(metadata["mimeType"], "text/plain")
            XCTAssertEqual(metadata["filename"], "Notes.txt")
            XCTAssertNotNil(metadata["base64Data"])
            XCTAssertNotNil(metadata["nativeBase64Data"])

            let request = await submitRequest(
                currentContext: currentContext,
                attachments: [],
                selectedHandle: row.handle
            )
            XCTAssertTrue(request.context.requestContext.addedAttachments.isEmpty)
            XCTAssertEqual(request.context.requestContext.currentContext.items.first?.metadata["path"], "Notes.txt")
            XCTAssertFalse(request.context.requestContext.currentContext.items.first?.identifier.hasPrefix("/") ?? true)
            XCTAssertEqual(request.context.requestContext.parts.count, 1)
            guard case let .providerNativeFile(kind, mimeType, lockedMetadata) = request.context.requestContext.parts[0].resolution else {
                XCTFail("Expected locked request current-context part to stay providerNativeFile for \(model.provider)")
                continue
            }
            XCTAssertEqual(kind, .plainTextDocument)
            XCTAssertEqual(mimeType, "text/plain")
            XCTAssertNotNil(lockedMetadata["base64Data"])
            XCTAssertNotNil(lockedMetadata["nativeBase64Data"])
            XCTAssertEqual(lockedMetadata["displayPath"], "Notes.txt")
        }
    }


    func testRemoteProviderAttachmentPartsUseProviderNativeBase64ForSupportedFiles() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("ProviderNative.txt")
        try "provider native body".write(to: fileURL, atomically: true, encoding: .utf8)
        let attachment = makeDraftAttachment(url: fileURL, source: .file)
        let expectedBase64 = try Data(contentsOf: fileURL).base64EncodedString()

        let models = makeProviderModels()
        let rows = makeCatalogRows()
        let cases: [(AiProviderModel, AiModelCatalogRow, AiChatContextPartResolverRequestFamily)] = [
            (models[0], rows[0], .openAIResponses),
            (models[1], rows[1], .anthropicMessages),
        ]

        for (model, row, requestFamily) in cases {
            let result = AiChatContextPartResolverClient.live().resolve(
                AiChatContextPartResolverInput(
                    provider: model.provider,
                    rawModelID: model.rawModelID,
                    requestFamily: requestFamily,
                    currentContext: AiChatCurrentContextSnapshot(),
                    attachments: [attachment]
                )
            )

            XCTAssertEqual(result.parts.count, 1)
            let part = try XCTUnwrap(result.parts.first)
            XCTAssertEqual(part.source, .attachment)
            XCTAssertEqual(part.displayPath, "ProviderNative.txt")
            XCTAssertEqual(part.displayTitle, "ProviderNative.txt")
            switch part.resolution {
            case let .providerNativeFile(kind, mimeType, metadata):
                XCTAssertEqual(kind, .plainTextDocument)
                XCTAssertEqual(mimeType, "text/plain")
                XCTAssertEqual(metadata["filename"], "ProviderNative.txt")
                XCTAssertEqual(metadata["displayPath"], "ProviderNative.txt")
                XCTAssertEqual(metadata["nativeUploadMode"], "requestBase64")
                XCTAssertEqual(metadata["base64Data"], expectedBase64)
                XCTAssertEqual(metadata["nativeBase64Data"], expectedBase64)
                XCTAssertFalse(metadata.values.contains { $0.contains("/Users/") })
            default:
                XCTFail("Expected providerNativeFile for \(model.provider)")
            }

            let request = await submitRequest(
                currentContext: AiChatCurrentContextSnapshot(),
                attachments: [attachment],
                selectedHandle: row.handle
            )
            XCTAssertEqual(request.context.requestContext.parts.count, 1)
            guard case let .providerNativeFile(kind, mimeType, metadata) = request.context.requestContext.parts[0].resolution else {
                XCTFail("Expected locked request part to stay providerNativeFile for \(model.provider)")
                continue
            }
            XCTAssertEqual(kind, .plainTextDocument)
            XCTAssertEqual(mimeType, "text/plain")
            XCTAssertEqual(metadata["filename"], "ProviderNative.txt")
            XCTAssertEqual(metadata["base64Data"], expectedBase64)
            XCTAssertEqual(metadata["nativeBase64Data"], expectedBase64)
            XCTAssertFalse(metadata.values.contains { $0.contains("/Users/") })
        }
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

    func testCodexMissingAttachmentDoesNotBecomePathScopeReference() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-codex-attachment-\(UUID().uuidString).txt")
        let draft = makeDraftAttachment(url: missingURL, source: .file)

        let resolvedContext = AiChatContextPartResolverClient.live().resolve(
            AiChatContextPartResolverInput(
                provider: .chatgptCodex,
                rawModelID: "gpt-5-codex",
                requestFamily: .codexCLI,
                currentContext: .init(),
                attachments: [draft]
            )
        )

        let attachment = try XCTUnwrap(resolvedContext.addedAttachments.first)
        guard case .failure(reason: .readFailed, _) = attachment.resolutionResult else {
            XCTFail("Expected missing file attachment failure, got \(attachment.resolutionResult)")
            return
        }

        let part = try XCTUnwrap(resolvedContext.parts.first)
        guard case .failure(reason: .readFailed, _) = part.resolution else {
            XCTFail("Expected missing file context part failure, got \(part.resolution)")
            return
        }
    }

    func testRegenerateAfterModelSwitchReResolvesLockedRequestContextForSelectedProvider() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let fileURL = sandbox.appendingPathComponent("RegenerateNotes.txt")
        try "provider-specific regenerate body".write(to: fileURL, atomically: true, encoding: .utf8)

        let stream = AiChatExecutionStreamDriver()
        let openAIModel = makeProviderModels()[0]
        let openAIRow = makeCatalogRows()[0]
        let codexHandle = AiModelHandle(provider: .chatgptCodex, rawValue: "gpt-5-codex")
        let codexModel = AiProviderModel(
            id: codexHandle,
            provider: .chatgptCodex,
            rawModelID: "gpt-5-codex",
            displayName: "GPT-5 Codex",
            providerDisplayName: "ChatGPT Codex",
            thinkingCapability: .unknown(reason: .init(message: "Thinking capability metadata is not loaded yet.")),
            unavailableReason: nil
        )
        let codexRow = AiModelCatalogRow(
            handle: codexHandle,
            displayName: "GPT-5 Codex",
            authMethod: .oauth,
            subtitle: "Codex CLI",
            sortOrder: 30,
            isDefault: false,
            isRecommended: true
        )
        let sessionID = AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111155"))
        let attachmentID = AiChatAttachmentID(rawValue: fileURL.path(percentEncoded: false))
        let originalLockedContext = AiChatLockedRequestContextSnapshot(
            currentContext: makeContextSnapshot(summary: "Original regenerate context"),
            addedAttachments: [
                AiChatAttachmentSnapshot(
                    id: attachmentID,
                    source: .file,
                    displayTitle: "RegenerateNotes.txt",
                    sourceLocation: AiChatAttachmentSourceLocation(
                        fileURL: fileURL.standardizedFileURL,
                        filePath: fileURL.path(percentEncoded: false)
                    ),
                    resolutionResult: .resolvedText(text: "provider-specific regenerate body", metadata: [:])
                )
            ],
            parts: [
                AiChatLockedContextPartSnapshot(
                    source: .attachment,
                    resolution: .providerNativeFile(
                        kind: .plainTextDocument,
                        mimeType: "text/plain",
                        metadata: ["base64Data": "stale-openai-native"]
                    ),
                    fileKind: .attachment,
                    displayTitle: "RegenerateNotes.txt"
                )
            ]
        )
        let originalRequestContext = AiChatRequestContextSnapshot(
            sessionID: sessionID,
            requestID: AiChatRequestID(rawValue: makeUUID("22222222-2222-2222-2222-222222222255")),
            runID: AiChatRunID(rawValue: makeUUID("33333333-3333-3333-3333-333333333355")),
            provider: openAIModel.provider,
            model: openAIModel.id,
            selectedModel: openAIModel,
            selectedModelRow: openAIRow,
            sessionStatus: .active,
            currentContext: originalLockedContext.currentContext,
            requestContext: originalLockedContext,
            promptSummary: "Explain this file",
            submittedAtMs: 1_700_000_000_000
        )
        let originalRequest = AiChatRequest(
            context: originalRequestContext,
            messages: [AiChatMessage(role: .user, content: "Explain this file")]
        )
        let completedLock = makeRequestLock(
            kind: .submit,
            request: originalRequest,
            selectedHandle: openAIModel.id,
            selectedRow: openAIRow,
            assistantReplacementIndex: nil
        )

        let store = TestStore(initialState: AiChatFeature.State(
            sessionID: sessionID,
            sessionStatus: .active,
            currentContext: makeContextSnapshot(summary: "Changed live selection"),
            addedAttachments: [],
            transcriptHistory: [
                AiChatMessage(role: .user, content: "Explain this file"),
                AiChatMessage(role: .assistant, content: "Old answer"),
            ],
            catalogRows: [openAIRow, codexRow],
            modelListState: .loaded([openAIModel, codexModel]),
            selectedModelHandle: codexHandle,
            executionPhase: .completed(completedLock)
        )) {
            AiChatFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_001_900))
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

        let request = try XCTUnwrap(stream.requests.first)
        let regeneratedAttachment = try XCTUnwrap(request.context.requestContext.addedAttachments.first)
        XCTAssertEqual(regeneratedAttachment.sourceLocation.filePath, fileURL.path(percentEncoded: false))
        XCTAssertEqual(regeneratedAttachment.resolutionResult, .resolvedText(text: "provider-specific regenerate body", metadata: [
            "filePath": fileURL.path(percentEncoded: false),
            "relativePath": "RegenerateNotes.txt",
            "source": "file",
        ]))
        XCTAssertEqual(request.context.model, codexHandle)
        XCTAssertEqual(request.context.provider, .chatgptCodex)
        XCTAssertEqual(request.context.currentContext.summary, "Original regenerate context")
        XCTAssertEqual(request.context.requestContext.addedAttachments.map(\.displayTitle), ["RegenerateNotes.txt"])
        let part = try XCTUnwrap(request.context.requestContext.parts.first)
        guard case let .providerNativeFile(kind, _, metadata) = part.resolution else {
            XCTFail("Expected Codex path-scope part, got \(part.resolution)")
            return
        }
        XCTAssertEqual(kind, .codexPathScope)
        XCTAssertNil(metadata["base64Data"])
        XCTAssertNil(metadata["nativeBase64Data"])
        XCTAssertEqual(metadata["attachmentID"], attachmentID.rawValue)
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


@MainActor
private func submitRequest(
    currentContext: AiChatCurrentContextSnapshot = makeContextSnapshot(summary: "Current folder"),
    attachments: [AiChatAttachmentDraft],
    selectedHandle: AiModelHandle? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> AiChatRequest {
    let stream = AiChatExecutionStreamDriver()
    let catalogRows = makeCatalogRows()
    let resolvedHandle = selectedHandle ?? catalogRows[0].handle
    let store = TestStore(initialState: AiChatFeature.State(
        sessionID: AiChatSessionID(rawValue: makeUUID("11111111-1111-1111-1111-111111111154")),
        sessionStatus: .active,
        currentContext: currentContext,
        addedAttachments: attachments,
        draftText: "Summarize these",
        catalogRows: catalogRows,
        selectedModelHandle: resolvedHandle,
        executionPhase: .idle
    )) {
        AiChatFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date = .constant(makeFixedDate(milliseconds: 1_700_000_002_000))
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
        XCTFail("Expected execution request", file: file, line: line)
        return AiChatRequest(
            context: AiChatRequestContextSnapshot(
                sessionID: nil,
                requestID: AiChatRequestID(rawValue: UUID()),
                runID: AiChatRunID(rawValue: UUID()),
                provider: .openai,
                model: resolvedHandle,
                selectedModelRow: catalogRows[0],
                sessionStatus: .active,
                promptSummary: nil,
                submittedAtMs: 0
            ),
            messages: []
        )
    }
    return request
}

private func writeCollectionFile(
    to url: URL,
    name: String,
    snapshotPaths: [String],
    stale: Bool = false
) throws {
    let conditions: [CollectionCondition] = []
    let query = ""
    let scopes = [url.deletingLastPathComponent().path]
    let fingerprint = stale
        ? "stale-fingerprint"
        : CollectionSnapshotHydration.definitionFingerprint(query: query, scopes: scopes, conditions: conditions)
    let file = VoyagerCollectionFile(
        id: UUID().uuidString,
        name: name,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        query: query,
        scopes: scopes,
        conditions: conditions,
        snapshot: CollectionPersistedSnapshot(items: snapshotPaths.map(VoyagerShared.JSONValue.string)),
        snapshotMeta: CollectionSnapshotMeta(
            definitionFingerprint: fingerprint,
            capturedAt: Date(timeIntervalSince1970: 0),
            itemCount: snapshotPaths.count,
            relevanceRoots: scopes
        ),
        appVersion: nil
    )
    let data = try VoyagerCollectionFileCompatibilityOwner.encodeCurrent(file)
    try data.write(to: url, options: [.atomic])
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


private func XCTAssertResolvedPartial(
    _ result: AiChatAttachmentResolutionResult,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .resolvedPartial = result else {
        XCTFail("Expected resolvedPartial, got \(result)", file: file, line: line)
        return
    }
}

private func XCTAssertResolvedReference(
    _ result: AiChatAttachmentResolutionResult,
    collectionPaths expectedPaths: [String]? = nil,
    included expectedIncluded: Int? = nil,
    truncated expectedTruncated: Bool? = nil,
    collectionSnapshotStatus expectedStatus: String? = nil,
    utf8ByteBudget expectedUTF8ByteBudget: Int? = nil,
    utf8Bytes expectedUTF8Bytes: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch result {
    case let .resolvedReference(metadata):
        if let expectedPaths {
            XCTAssertEqual(
                metadata["collectionItemPaths"]?.split(separator: "\n").map(String.init),
                expectedPaths,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(metadata["collectionItemPaths"], file: file, line: line)
        }
        if let expectedIncluded {
            XCTAssertEqual(metadata["collectionItemsIncluded"], "\(expectedIncluded)", file: file, line: line)
        }
        if let expectedTruncated {
            XCTAssertEqual(metadata["collectionItemsTruncated"], expectedTruncated ? "true" : "false", file: file, line: line)
        }
        if let expectedStatus {
            XCTAssertEqual(metadata["collectionSnapshotStatus"], expectedStatus, file: file, line: line)
        }
        if let expectedUTF8ByteBudget {
            XCTAssertEqual(metadata["collectionItemPathUTF8ByteBudget"], "\(expectedUTF8ByteBudget)", file: file, line: line)
        }
        if let expectedUTF8Bytes {
            XCTAssertEqual(metadata["collectionItemPathsUTF8Bytes"], "\(expectedUTF8Bytes)", file: file, line: line)
        }
    default:
        XCTFail("Expected resolved reference, got \(result)", file: file, line: line)
    }
}

private func redactedDisplayPaths(_ paths: [String]) -> [String] {
    paths.map { URL(fileURLWithPath: $0).lastPathComponent }
}

private func collectionPathsWithinUTF8Budget(_ paths: [String], budget: Int) -> [String] {
    var includedPaths: [String] = []
    var usedBytes = 0

    for path in paths {
        let separatorBytes = includedPaths.isEmpty ? 0 : 1
        let nextBytes = path.utf8.count
        guard usedBytes + separatorBytes + nextBytes <= budget else { return includedPaths }
        includedPaths.append(path)
        usedBytes += separatorBytes + nextBytes
    }

    return includedPaths
}
