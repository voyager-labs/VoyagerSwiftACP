import Foundation
@testable import VoyagerEntitiesAi
import XCTest

final class AiChatProviderExecutionRequestTests: XCTestCase {
    func testMakeOpenAIRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: makePayload(provider: .openai, rawModelID: "gpt-4.1-mini"),
            credential: .apiKey("openai-key")
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

    func testMakeAnthropicRequest_usesStreamingExecutionTimeout() throws {
        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: makePayload(provider: .anthropic, rawModelID: "claude-sonnet-4-20250514"),
            credential: .apiKey("anthropic-key")
        )

        XCTAssertEqual(request.timeoutInterval, AiChatProviderExecutionClient.streamingExecutionRequestTimeout)
        XCTAssertGreaterThan(request.timeoutInterval, 30)
    }

    func testMakeAnthropicRequest_usesNativeDocumentAndImageBlocksWhenAllowed() throws {
        let payload = try makePayload(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            messages: [
                AiChatProviderMessage(role: .user, content: "First question"),
                AiChatProviderMessage(role: .assistant, content: "First answer"),
                AiChatProviderMessage(role: .user, content: "Follow-up with the attached files"),
            ],
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "native-summary"),
                        source: .file,
                        displayTitle: "Design.pdf",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "/Users/me/secret/docs/Design.pdf"),
                        resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"])
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .currentContext,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "Y3VycmVudC1jb250ZXh0LWltYWdl",
                                "fileExtension": "png",
                                "path": "/Users/me/secret/mockups/ignore-me.png",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/mockups/ignore-me.png",
                        displayPath: "/Users/me/secret/mockups/ignore-me.png",
                        fileKind: .file,
                        displayTitle: "ignore-me.png",
                        byteCount: 64,
                        mimeType: "image/png"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .pdf,
                            mimeType: "application/pdf",
                            metadata: [
                                "base64Data": "cGRmLWJ5dGVz",
                                "fileExtension": "pdf",
                                "filePath": "/Users/me/secret/docs/Design.pdf",
                                "attachmentID": "native-pdf",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/docs/Design.pdf",
                        displayPath: "/Users/me/secret/docs/Design.pdf",
                        fileKind: .file,
                        displayTitle: "Design.pdf",
                        byteCount: 1024,
                        mimeType: "application/pdf"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "aW1hZ2UtYnl0ZXM=",
                                "fileExtension": "png",
                                "path": "/Users/me/secret/mockups/diagram.png",
                                "attachmentID": "native-image",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/mockups/diagram.png",
                        displayPath: "/Users/me/secret/mockups/diagram.png",
                        fileKind: .file,
                        displayTitle: "diagram.png",
                        byteCount: 128,
                        mimeType: "image/png"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: payload,
            credential: .apiKey("anthropic-key")
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(CapturedAnthropicRequestBody.self, from: body)

        XCTAssertEqual(decoded.messages.map(\.role), ["user", "assistant", "user"])
        XCTAssertEqual(decoded.messages[0].content, [.text("First question")])
        XCTAssertEqual(decoded.messages[1].content, [.text("First answer")])
        XCTAssertEqual(decoded.messages[2].content, [
            .text("Follow-up with the attached files"),
            .image(mediaType: "image/png", data: "Y3VycmVudC1jb250ZXh0LWltYWdl"),
            .document(mediaType: "application/pdf", data: "cGRmLWJ5dGVz", title: "Design.pdf"),
            .image(mediaType: "image/png", data: "aW1hZ2UtYnl0ZXM="),
        ])
        XCTAssertFalse(decoded.system?.contains("attachment_id:") == true)
        XCTAssertFalse(decoded.system?.contains("native-image") == true)
        XCTAssertFalse(decoded.system?.contains("native-pdf") == true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("/Users/"))
    }

    func testMakeAnthropicRequest_includesCurrentContextResolvedPartsOutsideAttachmentTransmission() throws {
        let payload = try makePayload(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(summary: "Current context summary"),
                addedAttachments: [],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .currentContext,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "Y3VycmVudC1jb250ZXh0LWJ5dGVz",
                                "fileExtension": "png",
                                "path": "/Users/me/secret/current-context.png",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/current-context.png",
                        displayPath: "/Users/me/secret/current-context.png",
                        fileKind: .file,
                        displayTitle: "current-context.png",
                        byteCount: 64,
                        mimeType: "image/png"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .pdf,
                            mimeType: "application/pdf",
                            metadata: [
                                "base64Data": "YXR0YWNobWVudC1ieXRlcw==",
                                "fileExtension": "pdf",
                                "filePath": "/Users/me/secret/Attachment.pdf",
                                "attachmentID": "attachment-pdf",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/Attachment.pdf",
                        displayPath: "/Users/me/secret/Attachment.pdf",
                        fileKind: .file,
                        displayTitle: "Attachment.pdf",
                        byteCount: 1_024,
                        mimeType: "application/pdf"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: payload,
            credential: .apiKey("anthropic-key")
        )
        let decoded = try decodeAnthropicRequestBody(request)
        let system = try XCTUnwrap(decoded.system)

        XCTAssertTrue(system.contains("current_context:"), system)
        XCTAssertTrue(system.contains("resolved_parts:"), system)
        XCTAssertTrue(system.contains("current-context.png"), system)
        XCTAssertTrue(system.contains("uploaded natively as image/png"), system)
        XCTAssertTrue(system.contains("attachment_transmission:"), system)
        XCTAssertTrue(system.contains("Attachment.pdf"), system)
        XCTAssertTrue(system.contains("uploaded natively as application/pdf"), system)
    }

    func testMakeOpenAIRequest_includesResolvedFolderMetadataForCurrentContextAndAttachments() throws {
        let currentFolderMetadata = [
            "displayPath": "Desktop",
            "folderStructureMode": "includeSubfolders",
            "collectionItemCount": "1",
            "collectionItemsIncluded": "1",
            "collectionItemsTruncated": "false",
            "collectionItemPaths": "Inside.md",
            "folderStructureEntries": "directory\t0\tDesktop\nfile\t1\tDesktop/Inside.md",
            "folderStructureDirectoryFilePaths": "Desktop\tDesktop/Inside.md",
        ]
        let attachmentFolderMetadata = [
            "displayPath": "Workspace",
            "folderStructureMode": "includeSubfolders",
            "collectionItemCount": "1",
            "collectionItemsIncluded": "1",
            "collectionItemsTruncated": "false",
            "collectionItemPaths": "AttachmentInside.md",
            "folderStructureEntries": "directory\t0\tWorkspace\nfile\t1\tWorkspace/AttachmentInside.md",
            "folderStructureDirectoryFilePaths": "Workspace\tWorkspace/AttachmentInside.md",
            "attachmentID": "folder-attachment",
        ]
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "Desktop",
                    items: [
                        AiChatContextItem(
                            kind: .folder,
                            identifier: "Desktop",
                            title: "Desktop",
                            metadata: ["folderStructureMode": "includeSubfolders"]
                        ),
                    ]
                ),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "folder-attachment"),
                        source: .folder,
                        displayTitle: "Workspace",
                        kind: .folder,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Workspace"),
                        resolutionResult: .resolvedReference(metadata: attachmentFolderMetadata)
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .currentContext,
                        resolution: .referenceOnly(metadata: currentFolderMetadata),
                        canonicalPath: "/tmp/Desktop",
                        displayPath: "Desktop",
                        fileKind: .folder,
                        displayTitle: "Desktop"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .referenceOnly(metadata: attachmentFolderMetadata),
                        canonicalPath: "/tmp/Workspace",
                        displayPath: "Workspace",
                        fileKind: .folder,
                        displayTitle: "Workspace"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("current_context:"), prompt)
        XCTAssertTrue(prompt.contains("resolved_parts:"), prompt)
        XCTAssertTrue(prompt.contains("Desktop/Inside.md"), prompt)
        XCTAssertTrue(prompt.contains("- Inside.md"), prompt)
        XCTAssertTrue(prompt.contains("folder_structure:"), prompt)
        XCTAssertTrue(prompt.contains("directory_file_paths:"), prompt)
        XCTAssertTrue(prompt.contains("- Desktop\tDesktop/Inside.md"), prompt)
        XCTAssertFalse(prompt.contains("folderStructureDirectoryFilePaths:"), prompt)
        XCTAssertTrue(prompt.contains("added_attachments:"), prompt)
        XCTAssertTrue(prompt.contains("attachment_transmission:"), prompt)
        XCTAssertTrue(prompt.contains("Workspace/AttachmentInside.md"), prompt)
        XCTAssertTrue(prompt.contains("- AttachmentInside.md"), prompt)
        XCTAssertTrue(prompt.contains("- Workspace\tWorkspace/AttachmentInside.md"), prompt)
        XCTAssertFalse(prompt.contains("attachmentID:"), prompt)
    }

    func testMakeAnthropicRequest_omitsBase64PayloadMetadataFromSystemPrompt() throws {
        let payload = try makePayload(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "native-image"),
                        source: .file,
                        displayTitle: "Diagram.png",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Diagram.png"),
                        metadata: ["nativeBase64Data": "ATTACHMENT_NATIVE_BYTES"],
                        resolutionResult: .resolvedReference(metadata: [
                            "base64Data": "ATTACHMENT_BASE64_BYTES",
                            "fileDataBase64": "ATTACHMENT_FILE_DATA_BYTES",
                            "nativeUploadMode": "requestBase64",
                            "resolution": "provider_native",
                        ])
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "NATIVE_BLOCK_BYTES",
                                "nativeBase64Data": "NATIVE_BLOCK_DUPLICATE_BYTES",
                                "fileDataBase64": "NATIVE_BLOCK_FILE_DATA_BYTES",
                                "nativeUploadMode": "requestBase64",
                            ]
                        ),
                        fileKind: .file,
                        displayTitle: "Diagram.png",
                        byteCount: 128,
                        mimeType: "image/png"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: payload,
            credential: .apiKey("anthropic-key")
        )
        let decoded = try decodeAnthropicRequestBody(request)
        let system = try XCTUnwrap(decoded.system)

        XCTAssertTrue(system.contains("nativeUploadMode: requestBase64"), system)
        XCTAssertTrue(system.contains("resolution: provider_native"), system)
        XCTAssertFalse(system.contains("base64Data:"), system)
        XCTAssertFalse(system.contains("nativeBase64Data:"), system)
        XCTAssertFalse(system.contains("fileDataBase64:"), system)
        XCTAssertFalse(system.contains("ATTACHMENT_BASE64_BYTES"), system)
        XCTAssertFalse(system.contains("ATTACHMENT_NATIVE_BYTES"), system)
        XCTAssertFalse(system.contains("ATTACHMENT_FILE_DATA_BYTES"), system)
        XCTAssertFalse(system.contains("NATIVE_BLOCK_BYTES"), system)
        XCTAssertFalse(system.contains("NATIVE_BLOCK_DUPLICATE_BYTES"), system)
        XCTAssertFalse(system.contains("NATIVE_BLOCK_FILE_DATA_BYTES"), system)
    }

    func testMakeAnthropicRequest_fallsBackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
        let payload = try makePayload(
            provider: .anthropic,
            rawModelID: "claude-sonnet-4-20250514",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "docx-fallback"),
                        source: .file,
                        displayTitle: "Report.docx",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Report.docx"),
                        resolutionResult: .failure(reason: .unsupportedType, metadata: ["path": "Report.docx"])
                    ),
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "oversized-fallback"),
                        source: .file,
                        displayTitle: "Huge.png",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Huge.png"),
                        resolutionResult: .failure(reason: .tooLarge, metadata: ["path": "Huge.png"])
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .openAIDocument,
                            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                            metadata: [
                                "base64Data": "ZG9jeC1ieXRlcw==",
                                "fileExtension": "docx",
                                "filePath": "/Users/me/secret/docs/Report.docx",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/docs/Report.docx",
                        displayPath: "/Users/me/secret/docs/Report.docx",
                        fileKind: .file,
                        displayTitle: "Report.docx",
                        byteCount: 4096,
                        mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "dG9vLWJpZw==",
                                "fileExtension": "png",
                                "path": "/Users/me/secret/mockups/Huge.png",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/mockups/Huge.png",
                        displayPath: "/Users/me/secret/mockups/Huge.png",
                        fileKind: .file,
                        displayTitle: "Huge.png",
                        byteCount: AiChatProviderFileCapability.nativeUploadSafeLimitBytes + 1,
                        mimeType: "image/png"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
            payload: payload,
            credential: .apiKey("anthropic-key")
        )
        let decoded = try decodeAnthropicRequestBody(request)
        let body = try XCTUnwrap(request.httpBody)

        XCTAssertEqual(decoded.messages.map(\.role), ["user"])
        XCTAssertEqual(decoded.messages[0].content, [.text("Hello")])
        XCTAssertTrue(decoded.system?.contains("Report.docx [unsupportedType]") == true)
        XCTAssertTrue(decoded.system?.contains("not included: unsupportedType") == true)
        XCTAssertTrue(decoded.system?.contains("Huge.png [tooLarge]") == true)
        XCTAssertTrue(decoded.system?.contains("not included: tooLarge") == true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("/Users/"))
    }

    func testMakeOpenAIRequest_encodesReasoningWhenThinkingNoneIsSupported() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-5",
            thinking: AiChatProviderThinkingPayload.none
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)

        XCTAssertEqual(decoded.reasoning?.effort, "none")
        XCTAssertNil(decoded.reasoning?.budgetTokens)
    }

    func testMakeOpenAIRequest_usesLockedCurrentContextWhenNoAttachmentsExist() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(
                    summary: "Locked editor selection",
                    items: [
                        AiChatContextItem(
                            kind: .selection,
                            identifier: "selection-1",
                            title: "Lines 10-20",
                            metadata: ["path": "/tmp/Selection.swift"]
                        ),
                    ]
                ),
                addedAttachments: []
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user"])
        XCTAssertEqual(decoded.input.first?.type, "message")
        XCTAssertTrue(prompt.contains("current_context:"))
        XCTAssertTrue(prompt.contains("summary: Locked editor selection"))
        XCTAssertTrue(prompt.contains("[selection] Lines 10-20"))
        XCTAssertTrue(prompt.contains("added_attachments:\n  - none"))
        XCTAssertFalse(prompt.contains("live draft should not leak"))
    }

    func testMakeOpenAIRequest_usesOutputTextForAssistantHistory() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            messages: [
                AiChatProviderMessage(role: .user, content: "First question"),
                AiChatProviderMessage(role: .assistant, content: "First answer"),
                AiChatProviderMessage(role: .user, content: "Follow-up question"),
            ]
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user", "assistant", "user"])
        XCTAssertEqual(decoded.input[1].content.text, "First question")
        XCTAssertEqual(decoded.input[2].content.text, "First answer")
        XCTAssertEqual(decoded.input[3].content.text, "Follow-up question")
    }

    func testMakeOpenAIRequest_includesLockedAttachmentResolutionVariantsOnly() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: AiChatCurrentContextSnapshot(summary: "Locked request context"),
                addedAttachments: makeLockedAttachmentResolutionFixtures()
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("Notes.txt [resolvedText]"))
        XCTAssertTrue(prompt.contains("Resolved note body"))
        XCTAssertTrue(prompt.contains("Workspace [resolvedReference]"))
        XCTAssertTrue(prompt.contains("reference included; content not expanded."))
        XCTAssertTrue(prompt.contains("Workspace.voycoll [resolvedReference]"))
        XCTAssertTrue(prompt.contains("collection_items:"))
        XCTAssertTrue(prompt.contains("- /tmp/project/README.md"))
        XCTAssertTrue(prompt.contains("- /tmp/project/design.pdf"))
        XCTAssertTrue(prompt.contains("collection_items_included: 2"))
        XCTAssertTrue(prompt.contains("collection_item_count: 2"))
        XCTAssertTrue(prompt.contains("collection references included; content not expanded."))
        XCTAssertTrue(prompt.contains("Broken.txt [readFailed]"))
        XCTAssertTrue(prompt.contains("not included: readFailed"))
        XCTAssertFalse(prompt.contains("live attachment should not leak"))
    }

    func testMakeOpenAIRequest_redactsAddedAttachmentAbsoluteFilePathInPrompt() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "secret-notes"),
                        source: .file,
                        displayTitle: "SecretNotes.txt",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "/Users/me/secret/docs/SecretNotes.txt"),
                        resolutionResult: .resolvedText(text: "safe body", metadata: ["encoding": "utf-8"])
                    ),
                ],
                parts: []
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertTrue(prompt.contains("file_path: SecretNotes.txt"), prompt)
        XCTAssertFalse(prompt.contains("/Users/me/secret"), prompt)
    }

    func testMakeOpenAIRequest_usesNativeImageAndFileBlocksWhenAllowed() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            messages: [
                AiChatProviderMessage(role: .user, content: "First question"),
                AiChatProviderMessage(role: .assistant, content: "First answer"),
                AiChatProviderMessage(role: .user, content: "Follow-up with the attached files"),
            ],
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "native-summary"),
                        source: .file,
                        displayTitle: "Native summary",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Design.pdf"),
                        resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"])
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "aW1hZ2UtYnl0ZXM=",
                                "fileExtension": "png",
                                "path": "/Users/me/secret/mockups/diagram.png",
                                "attachmentID": "native-image",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/mockups/diagram.png",
                        displayPath: "/Users/me/secret/mockups/diagram.png",
                        fileKind: .file,
                        displayTitle: "diagram.png",
                        byteCount: 128,
                        mimeType: "image/png"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .pdf,
                            mimeType: "application/pdf",
                            metadata: [
                                "base64Data": "cGRmLWJ5dGVz",
                                "fileExtension": "pdf",
                                "filePath": "/Users/me/secret/docs/Design.pdf",
                                "attachmentID": "native-pdf",
                            ]
                        ),
                        canonicalPath: "/Users/me/secret/docs/Design.pdf",
                        displayPath: "/Users/me/secret/docs/Design.pdf",
                        fileKind: .file,
                        displayTitle: "Design.pdf",
                        byteCount: 1024,
                        mimeType: "application/pdf"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user", "assistant", "user"])
        XCTAssertEqual(decoded.input[1].content.text, "First question")
        XCTAssertEqual(decoded.input[2].content.text, "First answer")
        XCTAssertEqual(decoded.input[3].content.parts, [
            .init(type: "input_text", text: "Follow-up with the attached files"),
            .init(type: "input_image", detail: "auto", imageURL: "data:image/png;base64,aW1hZ2UtYnl0ZXM="),
            .init(type: "input_file", fileData: "data:application/pdf;base64,cGRmLWJ5dGVz", filename: "Design.pdf"),
        ])
        XCTAssertTrue(prompt.contains("attachment_transmission:"))
        XCTAssertTrue(prompt.contains("state: provider-native"))
        XCTAssertTrue(prompt.contains("status: Uploaded/native"))
        XCTAssertTrue(prompt.contains("provider-native attachment included; uploaded natively as application/pdf"))
        XCTAssertFalse(prompt.contains("attachment_id:"))
        XCTAssertFalse(prompt.contains("native-image"))
        XCTAssertFalse(prompt.contains("native-pdf"))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("/Users/me/secret"))
    }

    func testMakeOpenAIRequest_fallsBackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-3.5-turbo",
            requestContext: AiChatLockedRequestContextSnapshot(
                currentContext: .init(),
                addedAttachments: [
                    AiChatAttachmentSnapshot(
                        id: AiChatAttachmentID(rawValue: "native-fallback"),
                        source: .file,
                        displayTitle: "Budget.xlsx",
                        kind: .file,
                        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Budget.xlsx"),
                        resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"])
                    ),
                ],
                parts: [
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .spreadsheet,
                            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                            metadata: [
                                "base64Data": "eGxzeC1ieXRlcw==",
                                "fileExtension": "xlsx",
                            ]
                        ),
                        fileKind: .file,
                        displayTitle: "Budget.xlsx",
                        byteCount: 4096,
                        mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    ),
                    AiChatLockedContextPartSnapshot(
                        source: .attachment,
                        resolution: .providerNativeFile(
                            kind: .image,
                            mimeType: "image/png",
                            metadata: [
                                "base64Data": "dG9vLWJpZw==",
                                "fileExtension": "png",
                            ]
                        ),
                        fileKind: .file,
                        displayTitle: "Huge.png",
                        byteCount: AiChatProviderFileCapability.nativeUploadSafeLimitBytes + 1,
                        mimeType: "image/png"
                    ),
                ]
            )
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)
        let prompt = try XCTUnwrap(decoded.input.first?.content.text)

        XCTAssertEqual(decoded.input.map(\.role), ["developer", "user"])
        XCTAssertEqual(decoded.input[1].content.text, "Hello")
        XCTAssertTrue(prompt.contains("Budget.xlsx [resolvedReference]"))
        XCTAssertFalse(prompt.contains("/Users/"))
    }

    func testMakeOpenAIRequest_allowsEmptyLockedContextWithoutContextPrompt() throws {
        let payload = try makePayload(
            provider: .openai,
            rawModelID: "gpt-4.1-mini",
            requestContext: AiChatLockedRequestContextSnapshot(currentContext: .init(), addedAttachments: [])
        )

        let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
            payload: payload,
            credential: .apiKey("openai-key")
        )
        let decoded = try decodeOpenAIRequestBody(request)

        XCTAssertEqual(decoded.input.map(\.role), ["user"])
        XCTAssertEqual(decoded.input.first?.content.text, "Hello")
    }

    func testCodexArguments_includeReasoningEffortWhenSelected() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        let arguments = AiChatProviderExecutionClient.codexArguments(
            model: "gpt-5-codex",
            outputURL: outputURL,
            prompt: "Explain the change",
            thinking: .effort(.high)
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--model",
            "gpt-5-codex",
            "--output-last-message",
            outputURL.path,
            "-c",
            "model_reasoning_effort=\"high\"",
            "Explain the change",
        ])
    }

    func testCodexArguments_includeReasoningNoneWhenSupported() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        let arguments = AiChatProviderExecutionClient.codexArguments(
            model: "gpt-5-codex",
            outputURL: outputURL,
            prompt: "Explain the change",
            thinking: AiChatProviderThinkingPayload.none
        )

        XCTAssertEqual(arguments, [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--model",
            "gpt-5-codex",
            "--output-last-message",
            outputURL.path,
            "-c",
            "model_reasoning_effort=\"none\"",
            "Explain the change",
        ])
    }

    func testCodexArguments_omitReasoningEffortWhenUnsupported() {
        let outputURL = URL(fileURLWithPath: "/tmp/codex-output.txt")

        for thinking in [nil, .disabled, .tokenBudget(1024)] as [AiChatProviderThinkingPayload?] {
            let arguments = AiChatProviderExecutionClient.codexArguments(
                model: "gpt-5-codex",
                outputURL: outputURL,
                prompt: "Explain the change",
                thinking: thinking
            )

            XCTAssertFalse(arguments.contains { $0.contains("model_reasoning_effort") })
        }
    }

    func testCodexPipeDataAccumulator_collectsConcurrentStderrChunks() {
        let accumulator = CodexPipeDataAccumulator()

        accumulator.append(Data("first stderr chunk\n".utf8))
        accumulator.append(Data("second stderr chunk".utf8))

        XCTAssertEqual(accumulator.stringValue(), "first stderr chunk\nsecond stderr chunk")
    }

    private func makeLockedAttachmentResolutionFixtures() -> [AiChatAttachmentSnapshot] {
        [
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "text"),
                source: .file,
                displayTitle: "Notes.txt",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Notes.txt"),
                resolutionResult: .resolvedText(
                    text: "Resolved note body",
                    metadata: ["encoding": "utf-8"]
                )
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "reference"),
                source: .folder,
                displayTitle: "Workspace",
                kind: .folder,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Workspace"),
                resolutionResult: .resolvedReference(
                    metadata: ["resolution": "reference_only"]
                )
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "collection"),
                source: .collectionDocument,
                displayTitle: "Workspace.voycoll",
                kind: .attachment,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Workspace.voycoll"),
                resolutionResult: .resolvedReference(
                    metadata: [
                        "collectionItemCount": "2",
                        "collectionItemPaths": "/tmp/project/README.md\n/tmp/project/design.pdf",
                        "collectionItemsIncluded": "2",
                        "collectionItemsTruncated": "false",
                        "collectionSnapshotStatus": "usable",
                    ]
                )
            ),
            AiChatAttachmentSnapshot(
                id: AiChatAttachmentID(rawValue: "failure"),
                source: .file,
                displayTitle: "Broken.txt",
                kind: .file,
                sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Broken.txt"),
                resolutionResult: .failure(
                    reason: .readFailed,
                    metadata: ["path": "/tmp/Broken.txt"]
                )
            ),
        ]
    }

    private func makePayload(
        provider: AiProvider,
        rawModelID: String,
        thinking: AiChatProviderThinkingPayload? = nil,
        messages: [AiChatProviderMessage] = [
            AiChatProviderMessage(role: .user, content: "Hello"),
        ],
        requestContext: AiChatLockedRequestContextSnapshot = AiChatLockedRequestContextSnapshot(
            currentContext: AiChatCurrentContextSnapshot(summary: "Request context")
        )
    ) throws -> AiChatProviderRequestPayload {
        let requestUUID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runUUID = try XCTUnwrap(UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA"))
        let requestID = AiChatRequestID(rawValue: requestUUID)
        let runID = AiChatRunID(rawValue: runUUID)
        return AiChatProviderRequestPayload(
            provider: provider,
            rawModelID: rawModelID,
            messages: messages,
            context: AiChatProviderContextBundle(
                sessionID: nil,
                requestID: requestID,
                runID: runID,
                requestContext: requestContext,
                promptSummary: messages.last?.content,
                submittedAtMs: 1_700_000_000_000
            ),
            thinking: thinking
        )
    }

    private func decodeOpenAIRequestBody(_ request: URLRequest) throws -> CapturedOpenAIRequestBody {
        let body = try XCTUnwrap(request.httpBody)
        return try JSONDecoder().decode(CapturedOpenAIRequestBody.self, from: body)
    }

    private func decodeAnthropicRequestBody(_ request: URLRequest) throws -> CapturedAnthropicRequestBody {
        let body = try XCTUnwrap(request.httpBody)
        return try JSONDecoder().decode(CapturedAnthropicRequestBody.self, from: body)
    }
}

private struct CapturedOpenAIRequestBody: Decodable {
    let input: [CapturedOpenAIInputItem]
    let reasoning: CapturedOpenAIReasoning?
}

private struct CapturedOpenAIInputItem: Decodable {
    let type: String?
    let role: String
    let content: CapturedOpenAIContent
}

private enum CapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([CapturedOpenAIContentItem])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts(try container.decode([CapturedOpenAIContentItem].self))
    }

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [CapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }
}

private struct CapturedOpenAIContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let detail: String?
    let imageURL: String?
    let fileData: String?
    let filename: String?

    init(
        type: String,
        text: String? = nil,
        detail: String? = nil,
        imageURL: String? = nil,
        fileData: String? = nil,
        filename: String? = nil
    ) {
        self.type = type
        self.text = text
        self.detail = detail
        self.imageURL = imageURL
        self.fileData = fileData
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case detail
        case imageURL = "image_url"
        case fileData = "file_data"
        case filename
    }
}

private struct CapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

private struct CapturedAnthropicRequestBody: Decodable {
    let messages: [CapturedAnthropicMessage]
    let system: String?
}

private struct CapturedAnthropicMessage: Decodable {
    let role: String
    let content: [CapturedAnthropicContentItem]
}

private struct CapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: CapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    static func image(mediaType: String, data: String) -> Self {
        .init(
            type: "image",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: nil
        )
    }

    static func document(mediaType: String, data: String, title: String) -> Self {
        .init(
            type: "document",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: title
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

private struct CapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}
