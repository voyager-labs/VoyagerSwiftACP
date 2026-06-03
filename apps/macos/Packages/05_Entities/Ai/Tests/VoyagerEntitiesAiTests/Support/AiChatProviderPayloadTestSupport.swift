import Foundation
@testable import VoyagerEntitiesAi
import XCTest

func makeLockedAttachmentResolutionFixtures() -> [AiChatAttachmentSnapshot] {
    [
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "text"),
            source: .file,
            displayTitle: "Notes.txt",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Notes.txt"),
            resolutionResult: .resolvedText(
                text: "Resolved note body",
                metadata: ["encoding": "utf-8"],
            ),
        ),
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "reference"),
            source: .folder,
            displayTitle: "Workspace",
            kind: .folder,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Workspace"),
            resolutionResult: .resolvedReference(
                metadata: ["resolution": "reference_only"],
            ),
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
                ],
            ),
        ),
        AiChatAttachmentSnapshot(
            id: AiChatAttachmentID(rawValue: "failure"),
            source: .file,
            displayTitle: "Broken.txt",
            kind: .file,
            sourceLocation: AiChatAttachmentSourceLocation(filePath: "/tmp/Broken.txt"),
            resolutionResult: .failure(
                reason: .readFailed,
                metadata: ["path": "/tmp/Broken.txt"],
            ),
        ),
    ]
}

func makePayload(
    provider: AiProvider,
    rawModelID: String,
    thinking: AiChatProviderThinkingPayload? = nil,
    messages: [AiChatProviderMessage] = [
        AiChatProviderMessage(role: .user, content: "Hello"),
    ],
    requestContext: AiChatLockedRequestContextSnapshot = AiChatLockedRequestContextSnapshot(
        currentContext: AiChatCurrentContextSnapshot(summary: "Request context"),
    ),
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
            submittedAtMs: 1_700_000_000_000,
        ),
        thinking: thinking,
    )
}

func decodeOpenAIRequestBody(_ request: URLRequest) throws -> PayloadCapturedOpenAIRequestBody {
    let body = try XCTUnwrap(request.httpBody)
    return try JSONDecoder().decode(PayloadCapturedOpenAIRequestBody.self, from: body)
}

func decodeAnthropicRequestBody(_ request: URLRequest) throws -> PayloadCapturedAnthropicRequestBody {
    let body = try XCTUnwrap(request.httpBody)
    return try JSONDecoder().decode(PayloadCapturedAnthropicRequestBody.self, from: body)
}

struct PayloadCapturedOpenAIRequestBody: Decodable {
    let input: [PayloadCapturedOpenAIInputItem]
    let reasoning: PayloadCapturedOpenAIReasoning?
}

struct PayloadCapturedOpenAIInputItem: Decodable {
    let type: String?
    let role: String
    let content: PayloadCapturedOpenAIContent
}

enum PayloadCapturedOpenAIContent: Decodable, Equatable {
    case text(String)
    case parts([PayloadCapturedOpenAIContentItem])

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    var parts: [PayloadCapturedOpenAIContentItem]? {
        guard case let .parts(value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = try .parts(container.decode([PayloadCapturedOpenAIContentItem].self))
    }
}

struct PayloadCapturedOpenAIContentItem: Decodable, Equatable {
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
        filename: String? = nil,
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

struct PayloadCapturedOpenAIReasoning: Decodable {
    let effort: String?
    let budgetTokens: Int?

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

struct PayloadCapturedAnthropicRequestBody: Decodable {
    let messages: [PayloadCapturedAnthropicMessage]
    let system: String?
}

struct PayloadCapturedAnthropicMessage: Decodable {
    let role: String
    let content: [PayloadCapturedAnthropicContentItem]
}

struct PayloadCapturedAnthropicContentItem: Decodable, Equatable {
    let type: String
    let text: String?
    let source: PayloadCapturedAnthropicSource?
    let title: String?

    static func text(_ value: String) -> Self {
        .init(type: "text", text: value, source: nil, title: nil)
    }

    static func image(mediaType: String, data: String) -> Self {
        .init(
            type: "image",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: nil,
        )
    }

    static func document(mediaType: String, data: String, title: String) -> Self {
        .init(
            type: "document",
            text: nil,
            source: .init(type: "base64", mediaType: mediaType, data: data),
            title: title,
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case title
    }
}

struct PayloadCapturedAnthropicSource: Decodable, Equatable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

func assertAnthropicNativeDocumentAndImageBlocksWhenAllowed() throws {
    let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
        payload: makeAnthropicNativeDocumentAndImagePayload(),
        credential: .apiKey("anthropic-key"),
    )
    let body = try XCTUnwrap(request.httpBody)
    let decoded = try JSONDecoder().decode(PayloadCapturedAnthropicRequestBody.self, from: body)

    XCTAssertEqual(decoded.messages.map(\.role), ["user", "assistant", "user"])
    XCTAssertEqual(decoded.messages[0].content, [.text("First question")])
    XCTAssertEqual(decoded.messages[1].content, [.text("First answer")])
    XCTAssertEqual(decoded.messages[2].content, anthropicNativeDocumentAndImageBlocks())
    XCTAssertNotEqual(decoded.system?.contains("attachment_id:"), true)
    XCTAssertNotEqual(decoded.system?.contains("native-image"), true)
    XCTAssertNotEqual(decoded.system?.contains("native-pdf"), true)
    try assertBodyDoesNotContain(body, "/Users/")
}

func assertAnthropicCurrentContextResolvedPartsOutsideAttachmentTransmission() throws {
    let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
        payload: makeAnthropicCurrentContextResolvedPartsPayload(),
        credential: .apiKey("anthropic-key"),
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

func assertOpenAIResolvedFolderMetadataForCurrentContextAndAttachments() throws {
    let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
        payload: makeOpenAIFolderMetadataPayload(),
        credential: .apiKey("openai-key"),
    )
    let decoded = try decodeOpenAIRequestBody(request)
    let prompt = try XCTUnwrap(decoded.input.first?.content.text)

    assertOpenAIFolderMetadataPrompt(prompt)
}

func assertAnthropicOmitsBase64PayloadMetadataFromSystemPrompt() throws {
    let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
        payload: makeAnthropicBase64RedactionPayload(),
        credential: .apiKey("anthropic-key"),
    )
    let decoded = try decodeAnthropicRequestBody(request)
    let system = try XCTUnwrap(decoded.system)

    XCTAssertTrue(system.contains("nativeUploadMode: requestBase64"), system)
    XCTAssertTrue(system.contains("resolution: provider_native"), system)
    assertPromptOmitsBase64PayloadMetadata(system)
}

func assertAnthropicFallbackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
    let request = try AiChatProviderExecutionClient.makeAnthropicRequest(
        payload: makeAnthropicNativeUploadFallbackPayload(),
        credential: .apiKey("anthropic-key"),
    )
    let decoded = try decodeAnthropicRequestBody(request)
    let body = try XCTUnwrap(request.httpBody)

    XCTAssertEqual(decoded.messages.map(\.role), ["user"])
    XCTAssertEqual(decoded.messages[0].content, [.text("Hello")])
    XCTAssertEqual(decoded.system?.contains("Report.docx [unsupportedType]"), true)
    XCTAssertEqual(decoded.system?.contains("not included: unsupportedType"), true)
    XCTAssertEqual(decoded.system?.contains("Huge.png [tooLarge]"), true)
    XCTAssertEqual(decoded.system?.contains("not included: tooLarge"), true)
    try assertBodyDoesNotContain(body, "/Users/")
}

func assertOpenAINativeImageAndFileBlocksWhenAllowed() throws {
    let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
        payload: makeOpenAINativeImageAndFilePayload(),
        credential: .apiKey("openai-key"),
    )
    let body = try XCTUnwrap(request.httpBody)
    let decoded = try JSONDecoder().decode(PayloadCapturedOpenAIRequestBody.self, from: body)
    let prompt = try XCTUnwrap(decoded.input.first?.content.text)

    XCTAssertEqual(decoded.input.map(\.role), ["developer", "user", "assistant", "user"])
    XCTAssertEqual(decoded.input[1].content.text, "First question")
    XCTAssertEqual(decoded.input[2].content.text, "First answer")
    XCTAssertEqual(decoded.input[3].content.parts, openAINativeImageAndFileBlocks())
    assertOpenAINativeImageAndFilePrompt(prompt)
    try assertBodyDoesNotContain(body, "/Users/me/secret")
}

func assertOpenAIFallbackToPromptOnlyWhenNativeUploadIsDisallowedOrTooLarge() throws {
    let request = try AiChatProviderExecutionClient.makeOpenAIRequest(
        payload: makeOpenAINativeUploadFallbackPayload(),
        credential: .apiKey("openai-key"),
    )
    let body = try XCTUnwrap(request.httpBody)
    let decoded = try JSONDecoder().decode(PayloadCapturedOpenAIRequestBody.self, from: body)
    let prompt = try XCTUnwrap(decoded.input.first?.content.text)

    XCTAssertEqual(decoded.input.map(\.role), ["developer", "user"])
    XCTAssertEqual(decoded.input[1].content.text, "Hello")
    XCTAssertTrue(prompt.contains("Budget.xlsx [resolvedReference]"))
    try assertBodyDoesNotContain(body, "/Users/")
}

func makeAnthropicNativeDocumentAndImagePayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .anthropic,
        rawModelID: "claude-sonnet-4-20250514",
        messages: nativeUploadConversationMessages(),
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(),
            addedAttachments: [nativeSummaryAttachment(filePath: "/Users/me/secret/docs/Design.pdf")],
            parts: anthropicNativeDocumentAndImageParts(),
        ),
    )
}

func makeAnthropicCurrentContextResolvedPartsPayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .anthropic,
        rawModelID: "claude-sonnet-4-20250514",
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(summary: "Current context summary"),
            addedAttachments: [],
            parts: currentContextResolvedParts(),
        ),
    )
}

func makeOpenAIFolderMetadataPayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .openai,
        rawModelID: "gpt-4.1-mini",
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: folderMetadataCurrentContext(),
            addedAttachments: [folderMetadataAttachment()],
            parts: folderMetadataContextParts(),
        ),
    )
}

func makeAnthropicBase64RedactionPayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .anthropic,
        rawModelID: "claude-sonnet-4-20250514",
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(),
            addedAttachments: [base64RedactionAttachment()],
            parts: [base64RedactionContextPart()],
        ),
    )
}

func makeAnthropicNativeUploadFallbackPayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .anthropic,
        rawModelID: "claude-sonnet-4-20250514",
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(),
            addedAttachments: anthropicFallbackAttachments(),
            parts: anthropicFallbackContextParts(),
        ),
    )
}

func makeOpenAINativeImageAndFilePayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .openai,
        rawModelID: "gpt-4.1-mini",
        messages: nativeUploadConversationMessages(),
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(),
            addedAttachments: [nativeSummaryAttachment(filePath: "Design.pdf", title: "Native summary")],
            parts: openAINativeImageAndFileParts(),
        ),
    )
}

func makeOpenAINativeUploadFallbackPayload() throws -> AiChatProviderRequestPayload {
    try makePayload(
        provider: .openai,
        rawModelID: "gpt-3.5-turbo",
        requestContext: AiChatLockedRequestContextSnapshot(
            currentContext: .init(),
            addedAttachments: [openAIFallbackAttachment()],
            parts: openAIFallbackContextParts(),
        ),
    )
}

func nativeUploadConversationMessages() -> [AiChatProviderMessage] {
    [
        AiChatProviderMessage(role: .user, content: "First question"),
        AiChatProviderMessage(role: .assistant, content: "First answer"),
        AiChatProviderMessage(role: .user, content: "Follow-up with the attached files"),
    ]
}

func nativeSummaryAttachment(filePath: String, title: String = "Design.pdf") -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: "native-summary"),
        source: .file,
        displayTitle: title,
        kind: .file,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: filePath),
        resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"]),
    )
}

func anthropicNativeDocumentAndImageParts() -> [AiChatLockedContextPartSnapshot] {
    [
        nativeContextPart(
            source: .currentContext,
            kind: .image,
            title: "ignore-me.png",
            base64: "Y3VycmVudC1jb250ZXh0LWltYWdl",
        ),
        nativeContextPart(source: .attachment, kind: .pdf, title: "Design.pdf", base64: "cGRmLWJ5dGVz"),
        nativeContextPart(source: .attachment, kind: .image, title: "diagram.png", base64: "aW1hZ2UtYnl0ZXM="),
    ]
}

func currentContextResolvedParts() -> [AiChatLockedContextPartSnapshot] {
    [
        nativeContextPart(
            source: .currentContext,
            kind: .image,
            title: "current-context.png",
            base64: "Y3VycmVudC1jb250ZXh0LWJ5dGVz",
        ),
        nativeContextPart(source: .attachment, kind: .pdf, title: "Attachment.pdf", base64: "YXR0YWNobWVudC1ieXRlcw=="),
    ]
}

func openAINativeImageAndFileParts() -> [AiChatLockedContextPartSnapshot] {
    [
        nativeContextPart(source: .attachment, kind: .image, title: "diagram.png", base64: "aW1hZ2UtYnl0ZXM="),
        nativeContextPart(source: .attachment, kind: .pdf, title: "Design.pdf", base64: "cGRmLWJ5dGVz"),
    ]
}

func nativeContextPart(
    source: AiChatLockedContextPartSource,
    kind: AiChatProviderNativeFileKind,
    title: String,
    base64: String,
) -> AiChatLockedContextPartSnapshot {
    let mimeType = nativeMimeType(for: kind)
    let path = "/Users/me/secret/" + title
    return AiChatLockedContextPartSnapshot(
        source: source,
        resolution: .providerNativeFile(
            kind: kind,
            mimeType: mimeType,
            metadata: nativeMetadata(kind: kind, title: title, base64: base64),
        ),
        canonicalPath: path,
        displayPath: path,
        fileKind: .file,
        displayTitle: title,
        byteCount: kind == .pdf ? 1024 : 128,
        mimeType: mimeType,
    )
}

func nativeMetadata(kind: AiChatProviderNativeFileKind, title: String, base64: String) -> [String: String] {
    var metadata = ["base64Data": base64, "fileExtension": nativeFileExtension(for: kind)]
    metadata[kind == .pdf ? "filePath" : "path"] = "/Users/me/secret/" + title
    metadata["attachmentID"] = kind == .pdf ? "native-pdf" : "native-image"
    return metadata
}

func nativeMimeType(for kind: AiChatProviderNativeFileKind) -> String {
    switch kind {
    case .pdf: "application/pdf"
    case .openAIDocument: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case .spreadsheet: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case .image: "image/png"
    case .plainTextDocument: "text/plain"
    case .codexPathScope: "text/plain"
    }
}

func nativeFileExtension(for kind: AiChatProviderNativeFileKind) -> String {
    switch kind {
    case .pdf: "pdf"
    case .openAIDocument: "docx"
    case .spreadsheet: "xlsx"
    case .image: "png"
    case .plainTextDocument: "txt"
    case .codexPathScope: "txt"
    }
}

func anthropicNativeDocumentAndImageBlocks() -> [PayloadCapturedAnthropicContentItem] {
    [
        .text("Follow-up with the attached files"),
        .image(mediaType: "image/png", data: "Y3VycmVudC1jb250ZXh0LWltYWdl"),
        .document(mediaType: "application/pdf", data: "cGRmLWJ5dGVz", title: "Design.pdf"),
        .image(mediaType: "image/png", data: "aW1hZ2UtYnl0ZXM="),
    ]
}

func folderMetadataCurrentContext() -> AiChatCurrentContextSnapshot {
    AiChatCurrentContextSnapshot(
        summary: "Desktop",
        items: [
            AiChatContextItem(
                kind: .folder,
                identifier: "Desktop",
                title: "Desktop",
                metadata: ["folderStructureMode": "includeSubfolders"],
            ),
        ],
    )
}

func folderMetadataAttachment() -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: "folder-attachment"),
        source: .folder,
        displayTitle: "Workspace",
        kind: .folder,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Workspace"),
        resolutionResult: .resolvedReference(metadata: attachmentFolderMetadata()),
    )
}

func folderMetadataContextParts() -> [AiChatLockedContextPartSnapshot] {
    [
        folderMetadataPart(source: .currentContext, title: "Desktop", metadata: currentFolderMetadata()),
        folderMetadataPart(source: .attachment, title: "Workspace", metadata: attachmentFolderMetadata()),
    ]
}

func folderMetadataPart(
    source: AiChatLockedContextPartSource,
    title: String,
    metadata: [String: String],
) -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: source,
        resolution: .referenceOnly(metadata: metadata),
        canonicalPath: "/tmp/" + title,
        displayPath: title,
        fileKind: .folder,
        displayTitle: title,
    )
}

func currentFolderMetadata() -> [String: String] {
    folderMetadata(displayPath: "Desktop", itemPath: "Inside.md", directoryFilePaths: "Desktop\tDesktop/Inside.md")
}

func attachmentFolderMetadata() -> [String: String] {
    var metadata = folderMetadata(
        displayPath: "Workspace",
        itemPath: "AttachmentInside.md",
        directoryFilePaths: "Workspace\tWorkspace/AttachmentInside.md",
    )
    metadata["attachmentID"] = "folder-attachment"
    return metadata
}

func folderMetadata(displayPath: String, itemPath: String, directoryFilePaths: String) -> [String: String] {
    [
        "displayPath": displayPath,
        "folderStructureMode": "includeSubfolders",
        "collectionItemCount": "1",
        "collectionItemsIncluded": "1",
        "collectionItemsTruncated": "false",
        "collectionItemPaths": itemPath,
        "folderStructureEntries": "directory\t0\t\(displayPath)\nfile\t1\t\(displayPath)/\(itemPath)",
        "folderStructureDirectoryFilePaths": directoryFilePaths,
    ]
}

func assertOpenAIFolderMetadataPrompt(_ prompt: String) {
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

func base64RedactionAttachment() -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: "native-image"),
        source: .file,
        displayTitle: "Diagram.png",
        kind: .file,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Diagram.png"),
        metadata: ["nativeBase64Data": "ATTACHMENT_NATIVE_BYTES"],
        resolutionResult: .resolvedReference(metadata: base64RedactionMetadata()),
    )
}

func base64RedactionMetadata() -> [String: String] {
    [
        "base64Data": "ATTACHMENT_BASE64_BYTES",
        "fileDataBase64": "ATTACHMENT_FILE_DATA_BYTES",
        "nativeUploadMode": "requestBase64",
        "resolution": "provider_native",
    ]
}

func base64RedactionContextPart() -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .attachment,
        resolution: .providerNativeFile(kind: .image, mimeType: "image/png", metadata: nativeBlockRedactionMetadata()),
        fileKind: .file,
        displayTitle: "Diagram.png",
        byteCount: 128,
        mimeType: "image/png",
    )
}

func nativeBlockRedactionMetadata() -> [String: String] {
    [
        "base64Data": "NATIVE_BLOCK_BYTES",
        "nativeBase64Data": "NATIVE_BLOCK_DUPLICATE_BYTES",
        "fileDataBase64": "NATIVE_BLOCK_FILE_DATA_BYTES",
        "nativeUploadMode": "requestBase64",
    ]
}

func assertPromptOmitsBase64PayloadMetadata(_ system: String) {
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

func anthropicFallbackAttachments() -> [AiChatAttachmentSnapshot] {
    [
        fallbackAttachment(id: "docx-fallback", title: "Report.docx", reason: .unsupportedType),
        fallbackAttachment(id: "oversized-fallback", title: "Huge.png", reason: .tooLarge),
    ]
}

func fallbackAttachment(
    id: String,
    title: String,
    reason: AiChatAttachmentResolutionFailure,
) -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: id),
        source: .file,
        displayTitle: title,
        kind: .file,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: title),
        resolutionResult: .failure(reason: reason, metadata: ["path": title]),
    )
}

func anthropicFallbackContextParts() -> [AiChatLockedContextPartSnapshot] {
    [
        nativeContextPart(source: .attachment, kind: .openAIDocument, title: "Report.docx", base64: "ZG9jeC1ieXRlcw=="),
        nativeContextPart(
            source: .attachment,
            kind: .image,
            title: "Huge.png",
            base64: "dG9vLWJpZw==",
            byteCount: oversizedNativeUploadByteCount(),
        ),
    ]
}

func nativeContextPart(
    source: AiChatLockedContextPartSource,
    kind: AiChatProviderNativeFileKind,
    title: String,
    base64: String,
    byteCount: Int64,
) -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: source,
        resolution: .providerNativeFile(
            kind: kind,
            mimeType: nativeMimeType(for: kind),
            metadata: nativeMetadata(kind: kind, title: title, base64: base64),
        ),
        canonicalPath: "/Users/me/secret/" + title,
        displayPath: "/Users/me/secret/" + title,
        fileKind: .file,
        displayTitle: title,
        byteCount: byteCount,
        mimeType: nativeMimeType(for: kind),
    )
}

func oversizedNativeUploadByteCount() -> Int64 {
    AiChatProviderFileCapability.nativeUploadSafeLimitBytes + 1
}

func openAIFallbackAttachment() -> AiChatAttachmentSnapshot {
    AiChatAttachmentSnapshot(
        id: AiChatAttachmentID(rawValue: "native-fallback"),
        source: .file,
        displayTitle: "Budget.xlsx",
        kind: .file,
        sourceLocation: AiChatAttachmentSourceLocation(filePath: "Budget.xlsx"),
        resolutionResult: .resolvedReference(metadata: ["resolution": "reference_only"]),
    )
}

func openAIFallbackContextParts() -> [AiChatLockedContextPartSnapshot] {
    [
        openAIFallbackContextPart(kind: .spreadsheet, title: "Budget.xlsx", base64: "eGxzeC1ieXRlcw=="),
        openAIFallbackContextPart(
            kind: .image,
            title: "Huge.png",
            base64: "dG9vLWJpZw==",
            byteCount: oversizedNativeUploadByteCount(),
        ),
    ]
}

func openAIFallbackContextPart(
    kind: AiChatProviderNativeFileKind,
    title: String,
    base64: String,
    byteCount: Int64 = 128,
) -> AiChatLockedContextPartSnapshot {
    AiChatLockedContextPartSnapshot(
        source: .attachment,
        resolution: .providerNativeFile(
            kind: kind,
            mimeType: nativeMimeType(for: kind),
            metadata: nativeMetadata(kind: kind, title: title, base64: base64),
        ),
        canonicalPath: "/Users/me/secret/" + title,
        displayPath: title,
        fileKind: .file,
        displayTitle: title,
        byteCount: byteCount,
        mimeType: nativeMimeType(for: kind),
    )
}

func openAINativeImageAndFileBlocks() -> [PayloadCapturedOpenAIContentItem] {
    [
        .init(type: "input_text", text: "Follow-up with the attached files"),
        .init(type: "input_image", detail: "auto", imageURL: "data:image/png;base64,aW1hZ2UtYnl0ZXM="),
        .init(type: "input_file", fileData: "data:application/pdf;base64,cGRmLWJ5dGVz", filename: "Design.pdf"),
    ]
}

func assertOpenAINativeImageAndFilePrompt(_ prompt: String) {
    XCTAssertTrue(prompt.contains("attachment_transmission:"))
    XCTAssertTrue(prompt.contains("state: provider-native"))
    XCTAssertTrue(prompt.contains("status: Uploaded/native"))
    XCTAssertTrue(prompt.contains("provider-native attachment included; uploaded natively as application/pdf"))
    XCTAssertFalse(prompt.contains("attachment_id:"))
    XCTAssertFalse(prompt.contains("native-image"))
    XCTAssertFalse(prompt.contains("native-pdf"))
}

func assertBodyDoesNotContain(_ body: Data, _ needle: String) throws {
    let text = try XCTUnwrap(String(data: body, encoding: .utf8))
    XCTAssertFalse(text.contains(needle))
}
