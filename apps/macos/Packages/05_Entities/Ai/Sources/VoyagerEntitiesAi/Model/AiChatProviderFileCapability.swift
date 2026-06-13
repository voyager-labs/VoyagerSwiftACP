import Foundation
import UniformTypeIdentifiers

public enum AiChatProviderFileMIMEDetectionSource: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case urlResourceValuesContentType
    case filenameExtensionUTType
    case unknown
}

public enum AiChatProviderRequestFamily: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case openAIResponses
    case openAIChatCompletions
    case anthropicMessages
    case codexCLI
}

public struct AiChatProviderFileTypeDetectionPolicy: Equatable, Sendable {
    public let orderedSources: [AiChatProviderFileMIMEDetectionSource]

    public init(orderedSources: [AiChatProviderFileMIMEDetectionSource]) {
        self.orderedSources = orderedSources
    }

    public static let `default` = AiChatProviderFileTypeDetectionPolicy(
        orderedSources: [
            .urlResourceValuesContentType,
            .filenameExtensionUTType,
            .unknown,
        ],
    )
}

public enum AiChatProviderFileFallbackReason: String, Codable, Equatable, Sendable, Hashable {
    case providerDoesNotSupportNativeUpload
    case routeNotAllowlisted
    case modelNotAllowlisted
    case unknownExtension
    case unknownMIMEType
    case mimeTypeMismatch
    case tooLargeForNative
}

public enum AiChatProviderFileCapabilityDisposition: Equatable, Sendable {
    case providerNativeUpload(kind: AiChatProviderNativeFileKind, mimeType: String)
    case codexPathScope
    case fallback(AiChatProviderFileFallbackReason)
}

public struct AiChatProviderFileCapabilityLookup: Equatable, Sendable {
    public let provider: AiProvider
    public let rawModelID: String
    public let requestFamily: AiChatProviderRequestFamily
    public let fileExtension: String?
    public let detectedMIMEType: String
    public let detectedContentTypeIdentifier: String?
    public let sizeBytes: Int64

    public init(
        provider: AiProvider,
        rawModelID: String,
        requestFamily: AiChatProviderRequestFamily,
        fileExtension: String?,
        detectedMIMEType: String,
        sizeBytes: Int64,
        detectedContentTypeIdentifier: String? = nil,
    ) {
        self.provider = provider
        self.rawModelID = rawModelID
        self.requestFamily = requestFamily
        self.fileExtension = fileExtension
        self.detectedMIMEType = detectedMIMEType
        self.detectedContentTypeIdentifier = detectedContentTypeIdentifier
        self.sizeBytes = sizeBytes
    }
}

public struct AiChatProviderFileCapabilityDecision: Equatable, Sendable {
    public let disposition: AiChatProviderFileCapabilityDisposition
    public let normalizedExtension: String?
    public let normalizedMIMEType: String
    public let normalizedContentTypeIdentifier: String?

    public init(
        disposition: AiChatProviderFileCapabilityDisposition,
        normalizedExtension: String?,
        normalizedMIMEType: String,
        normalizedContentTypeIdentifier: String?,
    ) {
        self.disposition = disposition
        self.normalizedExtension = normalizedExtension
        self.normalizedMIMEType = normalizedMIMEType
        self.normalizedContentTypeIdentifier = normalizedContentTypeIdentifier
    }

    public var producesProviderNativeUpload: Bool {
        if case .providerNativeUpload = disposition {
            return true
        }
        return false
    }

    public var tooLargeForNative: Bool {
        if case .fallback(.tooLargeForNative) = disposition {
            return true
        }
        return false
    }
}

public enum AiChatProviderFileCapability {
    public static let mimeDetectionPolicy = AiChatProviderFileTypeDetectionPolicy.default

    public static let nativeUploadSafeLimitBytes: Int64 = 10 * 1024 * 1024

    public static let localInlineTextUTF8ByteLimit = Int64(AiChatRequestContextBudget.perAttachmentUTF8ByteBudget)
    public static let localInlineTextTotalUTF8ByteLimit = Int64(AiChatRequestContextBudget
        .totalAttachmentTextUTF8ByteBudget)

    public static let openAIKnownMaxUploadBytes: Int64 = 32 * 1024 * 1024
    public static let anthropicKnownMaxUploadBytes: Int64 = 32 * 1024 * 1024

    public static func lookup(_ input: AiChatProviderFileCapabilityLookup) -> AiChatProviderFileCapabilityDecision {
        let normalizedExtension = normalizeExtension(input.fileExtension)
        let normalizedMIMEType = normalizeMIMEType(input.detectedMIMEType)
        let normalizedContentTypeIdentifier = normalizeContentTypeIdentifier(input.detectedContentTypeIdentifier)

        let fileInfo = NormalizedFileInfo(
            extension: normalizedExtension,
            mimeType: normalizedMIMEType,
            contentTypeIdentifier: normalizedContentTypeIdentifier,
        )

        switch input.provider {
        case .chatgptCodex:
            return codexDecision(
                input: input,
                normalizedExtension: normalizedExtension,
                normalizedMIMEType: normalizedMIMEType,
                normalizedContentTypeIdentifier: normalizedContentTypeIdentifier,
            )

        case .openai:
            return providerDecision(
                input: input,
                fileInfo: fileInfo,
                routeMatches: input.requestFamily == .openAIResponses,
                modelMatches: openAINativeUploadModels.contains(normalizeModelID(input.rawModelID)),
                allowlist: openAIAllowlist,
            )

        case .anthropic:
            return providerDecision(
                input: input,
                fileInfo: fileInfo,
                routeMatches: input.requestFamily == .anthropicMessages,
                modelMatches: anthropicSupportsMessagesNativeUpload(normalizeModelID(input.rawModelID)),
                allowlist: anthropicAllowlist,
            )
        }
    }
}

private extension AiChatProviderFileCapability {
    struct AllowlistEntry: Equatable {
        let kind: AiChatProviderNativeFileKind
        let mimeTypes: Set<String>
        let contentTypeIdentifiers: Set<String>
    }

    static let openAINativeUploadModels: Set<String> = [
        "gpt-4.1",
        "gpt-4.1-mini",
        "gpt-4.1-nano",
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-5",
        "gpt-5-mini",
        "gpt-5-nano",
        "o1",
        "o1-mini",
        "o3",
        "o3-mini",
        "o4-mini",
    ]

    static let openAIAllowlist: [String: AllowlistEntry] = [
        "pdf": .init(kind: .pdf, mimeTypes: ["application/pdf"], contentTypeIdentifiers: ["com.adobe.pdf"]),
        "png": .init(kind: .image, mimeTypes: ["image/png"], contentTypeIdentifiers: ["public.png"]),
        "jpg": .init(kind: .image, mimeTypes: ["image/jpeg"], contentTypeIdentifiers: ["public.jpeg"]),
        "jpeg": .init(kind: .image, mimeTypes: ["image/jpeg"], contentTypeIdentifiers: ["public.jpeg"]),
        "webp": .init(kind: .image, mimeTypes: ["image/webp"], contentTypeIdentifiers: ["org.webmproject.webp"]),
        "gif": .init(kind: .image, mimeTypes: ["image/gif"], contentTypeIdentifiers: ["com.compuserve.gif"]),
        "txt": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/plain"],
            contentTypeIdentifiers: ["public.plain-text"],
        ),
        "md": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/markdown"],
            contentTypeIdentifiers: ["net.daringfireball.markdown"],
        ),
        "json": .init(
            kind: .plainTextDocument,
            mimeTypes: ["application/json", "text/json"],
            contentTypeIdentifiers: ["public.json"],
        ),
        "xml": .init(
            kind: .plainTextDocument,
            mimeTypes: ["application/xml", "text/xml"],
            contentTypeIdentifiers: ["public.xml"],
        ),
        "html": .init(kind: .plainTextDocument, mimeTypes: ["text/html"], contentTypeIdentifiers: ["public.html"]),
        "css": .init(kind: .plainTextDocument, mimeTypes: ["text/css"], contentTypeIdentifiers: ["public.css"]),
        "js": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/javascript", "application/javascript"],
            contentTypeIdentifiers: ["com.netscape.javascript-source"],
        ),
        "ts": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/typescript", "application/typescript"],
            contentTypeIdentifiers: ["public.typescript-source"],
        ),
        "tsx": .init(kind: .plainTextDocument, mimeTypes: ["text/tsx"], contentTypeIdentifiers: ["public.tsx-source"]),
        "swift": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-swift"],
            contentTypeIdentifiers: ["public.swift-source"],
        ),
        "py": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-python"],
            contentTypeIdentifiers: ["public.python-script"],
        ),
        "rb": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-ruby"],
            contentTypeIdentifiers: ["public.ruby-script"],
        ),
        "go": .init(kind: .plainTextDocument, mimeTypes: ["text/x-go"], contentTypeIdentifiers: ["public.go-source"]),
        "rs": .init(kind: .plainTextDocument, mimeTypes: ["text/rust"], contentTypeIdentifiers: ["public.rust-source"]),
        "java": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-java-source"],
            contentTypeIdentifiers: ["com.sun.java-source"],
        ),
        "kt": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-kotlin"],
            contentTypeIdentifiers: ["public.kotlin-source"],
        ),
        "c": .init(kind: .plainTextDocument, mimeTypes: ["text/x-c"], contentTypeIdentifiers: ["public.c-source"]),
        "cpp": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-c++"],
            contentTypeIdentifiers: ["public.c-plus-plus-source"],
        ),
        "h": .init(kind: .plainTextDocument, mimeTypes: ["text/x-chdr"], contentTypeIdentifiers: ["public.c-header"]),
        "hpp": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/x-c++hdr"],
            contentTypeIdentifiers: ["public.c-plus-plus-header"],
        ),
        "yaml": .init(
            kind: .plainTextDocument,
            mimeTypes: ["application/x-yaml", "text/yaml"],
            contentTypeIdentifiers: ["public.yaml"],
        ),
        "yml": .init(
            kind: .plainTextDocument,
            mimeTypes: ["application/x-yaml", "text/yaml"],
            contentTypeIdentifiers: ["public.yaml"],
        ),
        "toml": .init(
            kind: .plainTextDocument,
            mimeTypes: ["application/toml"],
            contentTypeIdentifiers: ["public.toml"],
        ),
        "csv": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/csv"],
            contentTypeIdentifiers: ["public.comma-separated-values-text"],
        ),
        "doc": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/msword"],
            contentTypeIdentifiers: ["com.microsoft.word.doc"],
        ),
        "docx": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
            contentTypeIdentifiers: ["org.openxmlformats.wordprocessingml.document"],
        ),
        "rtf": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/rtf", "text/rtf"],
            contentTypeIdentifiers: ["public.rtf"],
        ),
        "odt": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/vnd.oasis.opendocument.text"],
            contentTypeIdentifiers: ["org.oasis-open.opendocument.text"],
        ),
        "ppt": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/vnd.ms-powerpoint"],
            contentTypeIdentifiers: ["com.microsoft.powerpoint.ppt"],
        ),
        "pptx": .init(
            kind: .openAIDocument,
            mimeTypes: ["application/vnd.openxmlformats-officedocument.presentationml.presentation"],
            contentTypeIdentifiers: ["org.openxmlformats.presentationml.presentation"],
        ),
        "xls": .init(
            kind: .spreadsheet,
            mimeTypes: ["application/vnd.ms-excel"],
            contentTypeIdentifiers: ["com.microsoft.excel.xls"],
        ),
        "xlsx": .init(
            kind: .spreadsheet,
            mimeTypes: ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
            contentTypeIdentifiers: ["org.openxmlformats.spreadsheetml.sheet"],
        ),
        "tsv": .init(
            kind: .spreadsheet,
            mimeTypes: ["text/tab-separated-values"],
            contentTypeIdentifiers: ["public.tab-separated-values-text"],
        ),
    ]

    static let anthropicAllowlist: [String: AllowlistEntry] = [
        "pdf": .init(kind: .pdf, mimeTypes: ["application/pdf"], contentTypeIdentifiers: ["com.adobe.pdf"]),
        "txt": .init(
            kind: .plainTextDocument,
            mimeTypes: ["text/plain"],
            contentTypeIdentifiers: ["public.plain-text"],
        ),
        "png": .init(kind: .image, mimeTypes: ["image/png"], contentTypeIdentifiers: ["public.png"]),
        "jpg": .init(kind: .image, mimeTypes: ["image/jpeg"], contentTypeIdentifiers: ["public.jpeg"]),
        "jpeg": .init(kind: .image, mimeTypes: ["image/jpeg"], contentTypeIdentifiers: ["public.jpeg"]),
        "webp": .init(kind: .image, mimeTypes: ["image/webp"], contentTypeIdentifiers: ["org.webmproject.webp"]),
        "gif": .init(kind: .image, mimeTypes: ["image/gif"], contentTypeIdentifiers: ["com.compuserve.gif"]),
    ]

    struct NormalizedFileInfo {
        var `extension`: String?
        var mimeType: String
        var contentTypeIdentifier: String?
    }

    static func providerDecision(
        input: AiChatProviderFileCapabilityLookup,
        fileInfo: NormalizedFileInfo,
        routeMatches: Bool,
        modelMatches: Bool,
        allowlist: [String: AllowlistEntry],
    ) -> AiChatProviderFileCapabilityDecision {
        guard routeMatches else {
            return makeDecision(
                disposition: .fallback(.routeNotAllowlisted),
                extension: fileInfo.extension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        guard modelMatches else {
            return makeDecision(
                disposition: .fallback(.modelNotAllowlisted),
                extension: fileInfo.extension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        if let rejection = allowlistRejection(fileInfo: fileInfo, allowlist: allowlist) {
            return rejection
        }

        guard input.sizeBytes <= nativeUploadSafeLimitBytes else {
            return makeDecision(
                disposition: .fallback(.tooLargeForNative),
                extension: fileInfo.extension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        guard let normalizedExtension = fileInfo.extension,
              let entry = allowlist[normalizedExtension]
        else {
            return makeDecision(
                disposition: .fallback(.unknownExtension),
                extension: fileInfo.extension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        return makeDecision(
            disposition: .providerNativeUpload(kind: entry.kind, mimeType: fileInfo.mimeType),
            extension: normalizedExtension,
            mimeType: fileInfo.mimeType,
            contentTypeIdentifier: fileInfo.contentTypeIdentifier,
        )
    }

    private static func allowlistRejection(
        fileInfo: NormalizedFileInfo,
        allowlist: [String: AllowlistEntry],
    ) -> AiChatProviderFileCapabilityDecision? {
        guard let normalizedExtension = fileInfo.extension else {
            return makeDecision(
                disposition: .fallback(.unknownExtension),
                extension: nil,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        guard let entry = allowlist[normalizedExtension] else {
            return makeDecision(
                disposition: .fallback(.unknownExtension),
                extension: normalizedExtension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        guard fileInfo.mimeType != "application/octet-stream" else {
            return makeDecision(
                disposition: .fallback(.unknownMIMEType),
                extension: normalizedExtension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        guard entry.mimeTypes.contains(fileInfo.mimeType) else {
            return makeDecision(
                disposition: .fallback(.mimeTypeMismatch),
                extension: normalizedExtension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        if let normalizedContentTypeIdentifier = fileInfo.contentTypeIdentifier,
           !entry.contentTypeIdentifiers.isEmpty,
           !entry.contentTypeIdentifiers.contains(normalizedContentTypeIdentifier)
        {
            return makeDecision(
                disposition: .fallback(.mimeTypeMismatch),
                extension: normalizedExtension,
                mimeType: fileInfo.mimeType,
                contentTypeIdentifier: fileInfo.contentTypeIdentifier,
            )
        }

        return nil
    }

    static func codexDecision(
        input: AiChatProviderFileCapabilityLookup,
        normalizedExtension: String?,
        normalizedMIMEType: String,
        normalizedContentTypeIdentifier: String?,
    ) -> AiChatProviderFileCapabilityDecision {
        guard input.requestFamily == .codexCLI else {
            return makeDecision(
                disposition: .fallback(.routeNotAllowlisted),
                extension: normalizedExtension,
                mimeType: normalizedMIMEType,
                contentTypeIdentifier: normalizedContentTypeIdentifier,
            )
        }

        let normalizedModelID = normalizeModelID(input.rawModelID)
        guard normalizedModelID.contains("codex") else {
            return makeDecision(
                disposition: .fallback(.modelNotAllowlisted),
                extension: normalizedExtension,
                mimeType: normalizedMIMEType,
                contentTypeIdentifier: normalizedContentTypeIdentifier,
            )
        }

        return makeDecision(
            disposition: .codexPathScope,
            extension: normalizedExtension,
            mimeType: normalizedMIMEType,
            contentTypeIdentifier: normalizedContentTypeIdentifier,
        )
    }

    static func anthropicSupportsMessagesNativeUpload(_ normalizedModelID: String) -> Bool {
        normalizedModelID.hasPrefix("claude-")
    }

    static func normalizeExtension(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeMIMEType(_ value: String) -> String {
        let baseValue = value
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? value
        let normalized = baseValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "application/octet-stream" : normalized
    }

    static func normalizeContentTypeIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeModelID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func makeDecision(
        disposition: AiChatProviderFileCapabilityDisposition,
        extension: String?,
        mimeType: String,
        contentTypeIdentifier: String?,
    ) -> AiChatProviderFileCapabilityDecision {
        AiChatProviderFileCapabilityDecision(
            disposition: disposition,
            normalizedExtension: `extension`,
            normalizedMIMEType: mimeType,
            normalizedContentTypeIdentifier: contentTypeIdentifier,
        )
    }
}

private extension Set<String> {
    init(_ values: [String]) {
        self.init(values.map { $0.lowercased() })
    }
}
