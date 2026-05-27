import Foundation

public struct AiChatSessionID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatRequestID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatRunID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct AiChatAttachmentID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AiModelHandle: Codable, Equatable, Hashable, Sendable {
    public let provider: AiProvider
    public let rawValue: String

    public init(provider: AiProvider, rawValue: String) {
        self.provider = provider
        self.rawValue = rawValue
    }
}

public struct AiModelCatalogRow: Codable, Equatable, Sendable {
    public let handle: AiModelHandle
    public let displayName: String
    public let authMethod: ProviderAuthMethod
    public let subtitle: String?
    public let sortOrder: Int
    public let isDefault: Bool
    public let isRecommended: Bool

    // swiftlint:disable function_default_parameter_at_end
    public init(
        handle: AiModelHandle,
        displayName: String,
        authMethod: ProviderAuthMethod,
        subtitle: String? = nil,
        sortOrder: Int,
        isDefault: Bool = false,
        isRecommended: Bool = false,
    ) {
        self.handle = handle
        self.displayName = displayName
        self.authMethod = authMethod
        self.subtitle = subtitle
        self.sortOrder = sortOrder
        self.isDefault = isDefault
        self.isRecommended = isRecommended
    }
    // swiftlint:enable function_default_parameter_at_end
}

public enum AiChatContextItemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case reference
    case attachment
    case file
    case folder
    case selection
    case note
    case prompt
    case other
}

public struct AiChatContextReference: Codable, Equatable, Sendable {
    public let kind: AiChatContextItemKind
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let metadata: [String: String]

    public init(
        kind: AiChatContextItemKind,
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: [String: String] = [:],
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
    }
}

public struct AiChatContextItem: Codable, Equatable, Sendable {
    public let kind: AiChatContextItemKind
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let metadata: [String: String]
    public let references: [AiChatContextReference]

    public init(
        kind: AiChatContextItemKind,
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: [String: String] = [:],
        references: [AiChatContextReference] = [],
    ) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.references = references
    }
}

public struct AiChatContextAttachment: Codable, Equatable, Sendable {
    public let identifier: String
    public let title: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let metadata: [String: String]

    public init(
        identifier: String,
        title: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        metadata: [String: String] = [:],
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.metadata = metadata
    }
}

public struct AiChatCurrentContextSnapshot: Codable, Equatable, Sendable {
    public let summary: String?
    public let references: [AiChatContextReference]
    public let items: [AiChatContextItem]
    public let attachments: [AiChatContextAttachment]

    public init(
        summary: String? = nil,
        references: [AiChatContextReference] = [],
        items: [AiChatContextItem] = [],
        attachments: [AiChatContextAttachment] = [],
    ) {
        self.summary = summary
        self.references = references
        self.items = items
        self.attachments = attachments
    }
}

public enum AiChatRequestContextStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case draftContext = "draft_context"
    case emptyContext = "empty_context"
    case brokenReference = "broken_reference"
    case requestContextLocked = "request_context_locked"
}

public struct AiChatRequestContextBudget: Codable, Equatable, Sendable {
    public static let historyCharacterBudget = 24000
    public static let perAttachmentUTF8ByteBudget = 64 * 1024
    public static let totalAttachmentTextUTF8ByteBudget = 128 * 1024
    public static let `default` = AiChatRequestContextBudget(
        historyCharacters: historyCharacterBudget,
        perAttachmentUTF8Bytes: perAttachmentUTF8ByteBudget,
        totalAttachmentTextUTF8Bytes: totalAttachmentTextUTF8ByteBudget,
    )

    public let historyCharacters: Int
    public let perAttachmentUTF8Bytes: Int
    public let totalAttachmentTextUTF8Bytes: Int

    public init(
        historyCharacters: Int = AiChatRequestContextBudget.historyCharacterBudget,
        perAttachmentUTF8Bytes: Int = AiChatRequestContextBudget.perAttachmentUTF8ByteBudget,
        totalAttachmentTextUTF8Bytes: Int = AiChatRequestContextBudget.totalAttachmentTextUTF8ByteBudget,
    ) {
        self.historyCharacters = historyCharacters
        self.perAttachmentUTF8Bytes = perAttachmentUTF8Bytes
        self.totalAttachmentTextUTF8Bytes = totalAttachmentTextUTF8Bytes
    }
}

public enum AiChatAttachmentSource: String, Codable, Equatable, Sendable, CaseIterable {
    case file
    case folder
    case collectionDocument
    case collectionFile
    case inlineAttachment
    case otherReference
}

public struct AiChatAttachmentSourceLocation: Codable, Equatable, Sendable {
    public let fileURL: URL?
    public let filePath: String?

    public init(fileURL: URL? = nil, filePath: String? = nil) {
        self.fileURL = fileURL
        self.filePath = filePath
    }
}

public enum AiChatAttachmentResolutionFailure: String, Codable, Equatable, Sendable, CaseIterable {
    case tooLarge
    case unsupportedType
    case readFailed
    case permissionDenied
    case brokenReference
    case emptyContent
}

public enum AiChatProviderNativeFileKind: String, Codable, Equatable, Sendable {
    case pdf
    case image
    case plainTextDocument
    case openAIDocument
    case spreadsheet
    case codexPathScope
}

public enum AiChatContextPartResolution: Codable, Equatable, Sendable {
    case inlineText(text: String, metadata: [String: String])
    case partialText(text: String, truncated: Bool, metadata: [String: String])
    case referenceOnly(metadata: [String: String])
    case collectionPathList(paths: [String], metadata: [String: String])
    case providerNativeFile(kind: AiChatProviderNativeFileKind, mimeType: String, metadata: [String: String])
    case failure(reason: AiChatAttachmentResolutionFailure, metadata: [String: String])
}

public enum AiChatAttachmentResolutionResult: Codable, Equatable, Sendable {
    case resolvedText(text: String, metadata: [String: String])
    case resolvedReference(metadata: [String: String])
    case resolvedPartial(text: String, truncated: Bool, metadata: [String: String])
    case failure(reason: AiChatAttachmentResolutionFailure, metadata: [String: String])

    public var contextPartResolution: AiChatContextPartResolution {
        switch self {
        case let .resolvedText(text, metadata):
            return AiChatContextPartResolution.inlineText(text: text, metadata: metadata)
        case let .resolvedReference(metadata):
            let paths = Self.collectionItemPaths(from: metadata)
            if paths.isEmpty {
                return AiChatContextPartResolution.referenceOnly(metadata: metadata)
            }
            return AiChatContextPartResolution.collectionPathList(
                paths: paths,
                metadata: Self.collectionPathMetadata(from: metadata),
            )
        case let .resolvedPartial(text, truncated, metadata):
            return AiChatContextPartResolution.partialText(text: text, truncated: truncated, metadata: metadata)
        case let .failure(reason, metadata):
            return AiChatContextPartResolution.failure(reason: reason, metadata: metadata)
        }
    }

    private static func collectionPathMetadata(from metadata: [String: String]) -> [String: String] {
        metadata.filter { $0.key != "collectionItemPaths" }
    }

    private static func collectionItemPaths(from metadata: [String: String]) -> [String] {
        guard let rawPaths = metadata["collectionItemPaths"] else { return [] }
        return rawPaths
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public enum AiChatAttachmentDraftStatus: Codable, Equatable, Sendable {
    case pending
    case resolved(AiChatAttachmentResolutionResult)
}

public struct AiChatAttachmentDraft: Codable, Equatable, Sendable {
    public let id: AiChatAttachmentID
    public let source: AiChatAttachmentSource
    public let displayTitle: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let sourceLocation: AiChatAttachmentSourceLocation
    public let metadata: [String: String]
    public let currentStatus: AiChatAttachmentDraftStatus

    public init(
        id: AiChatAttachmentID,
        source: AiChatAttachmentSource,
        displayTitle: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        sourceLocation: AiChatAttachmentSourceLocation = .init(),
        metadata: [String: String] = [:],
        currentStatus: AiChatAttachmentDraftStatus = .pending,
    ) {
        self.id = id
        self.source = source
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.metadata = metadata
        self.currentStatus = currentStatus
    }
}

public struct AiChatAttachmentSnapshot: Codable, Equatable, Sendable {
    public let id: AiChatAttachmentID
    public let source: AiChatAttachmentSource
    public let displayTitle: String?
    public let subtitle: String?
    public let kind: AiChatContextItemKind
    public let sourceLocation: AiChatAttachmentSourceLocation
    public let metadata: [String: String]
    public let resolutionResult: AiChatAttachmentResolutionResult

    // swiftlint:disable function_default_parameter_at_end
    public init(
        id: AiChatAttachmentID,
        source: AiChatAttachmentSource,
        displayTitle: String? = nil,
        subtitle: String? = nil,
        kind: AiChatContextItemKind = .attachment,
        sourceLocation: AiChatAttachmentSourceLocation = .init(),
        metadata: [String: String] = [:],
        resolutionResult: AiChatAttachmentResolutionResult,
    ) {
        self.id = id
        self.source = source
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.metadata = metadata
        self.resolutionResult = resolutionResult
    }
    // swiftlint:enable function_default_parameter_at_end
}

public struct AiChatRequestContextDraft: Codable, Equatable, Sendable {
    public let currentContext: AiChatCurrentContextSnapshot
    public let addedAttachments: [AiChatAttachmentDraft]
    public let status: AiChatRequestContextStatus

    public init(
        currentContext: AiChatCurrentContextSnapshot = .init(),
        addedAttachments: [AiChatAttachmentDraft] = [],
        status: AiChatRequestContextStatus? = nil,
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.status = status ?? Self.deriveStatus(
            currentContext: currentContext,
            addedAttachments: addedAttachments,
        )
    }

    private static func deriveStatus(
        currentContext: AiChatCurrentContextSnapshot,
        addedAttachments: [AiChatAttachmentDraft],
    ) -> AiChatRequestContextStatus {
        if addedAttachments.contains(where: \.containsBrokenReference) {
            return .brokenReference
        }
        if currentContext.isEmpty, addedAttachments.isEmpty {
            return .emptyContext
        }
        return .draftContext
    }
}

public enum AiChatLockedContextPartSource: String, Codable, Equatable, Sendable {
    case currentContext
    case attachment
}

public struct AiChatLockedContextPartSnapshot: Codable, Equatable, Sendable {
    public let source: AiChatLockedContextPartSource
    public let resolution: AiChatContextPartResolution
    public let canonicalPath: String?
    public let displayPath: String?
    public let fileKind: AiChatContextItemKind
    public let displayTitle: String?
    public let byteCount: Int64?
    public let mimeType: String?

    public init(
        source: AiChatLockedContextPartSource,
        resolution: AiChatContextPartResolution,
        canonicalPath: String? = nil,
        displayPath: String? = nil,
        fileKind: AiChatContextItemKind,
        displayTitle: String? = nil,
        byteCount: Int64? = nil,
        mimeType: String? = nil,
    ) {
        self.source = source
        self.resolution = resolution
        self.canonicalPath = canonicalPath
        self.displayPath = displayPath
        self.fileKind = fileKind
        self.displayTitle = displayTitle
        self.byteCount = byteCount
        self.mimeType = mimeType
    }
}

public struct AiChatLockedRequestContextSnapshot: Codable, Equatable, Sendable {
    public let currentContext: AiChatCurrentContextSnapshot
    public let addedAttachments: [AiChatAttachmentSnapshot]
    public let parts: [AiChatLockedContextPartSnapshot]
    public let status: AiChatRequestContextStatus

    public init(
        currentContext: AiChatCurrentContextSnapshot = .init(),
        addedAttachments: [AiChatAttachmentSnapshot] = [],
        parts: [AiChatLockedContextPartSnapshot] = [],
        status: AiChatRequestContextStatus = .requestContextLocked,
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
        self.parts = parts
        self.status = status
    }
}

public enum AiChatSessionStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case restoring
    case active
    case completed
    case failed
    case rebindRequired
}

public enum AiChatSessionRestoreFailure: String, Codable, Sendable, Equatable, CaseIterable {
    case missingRecord
    case contextMismatch
    case corruptedRecord
    case unsupportedVersion
    case unknown
}

public struct AiChatRequestContextSnapshot: Codable, Equatable, Sendable {
    public let sessionID: AiChatSessionID?
    public let requestID: AiChatRequestID
    public let runID: AiChatRunID
    public let provider: AiProvider
    public let model: AiModelHandle
    public let selectedModel: AiProviderModel?
    public let selectedModelRow: AiModelCatalogRow?
    public let selectedThinking: AiThinkingSelection?
    public let sessionStatus: AiChatSessionStatus
    public let currentContext: AiChatCurrentContextSnapshot
    public let requestContext: AiChatLockedRequestContextSnapshot
    public let promptSummary: String?
    public let submittedAtMs: Int64?

    // swiftlint:disable function_default_parameter_at_end
    public init(
        sessionID: AiChatSessionID? = nil,
        requestID: AiChatRequestID,
        runID: AiChatRunID,
        provider: AiProvider,
        model: AiModelHandle,
        selectedModel: AiProviderModel? = nil,
        selectedModelRow: AiModelCatalogRow? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        sessionStatus: AiChatSessionStatus,
        currentContext: AiChatCurrentContextSnapshot = .init(),
        requestContext: AiChatLockedRequestContextSnapshot? = nil,
        promptSummary: String? = nil,
        submittedAtMs: Int64? = nil,
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.runID = runID
        self.provider = provider
        self.model = model
        self.selectedModel = selectedModel
        self.selectedModelRow = selectedModelRow
        self.selectedThinking = selectedThinking
        self.sessionStatus = sessionStatus
        let resolvedRequestContext = requestContext ??
            AiChatLockedRequestContextSnapshot(currentContext: currentContext)
        self.requestContext = resolvedRequestContext
        self.currentContext = resolvedRequestContext.currentContext
        self.promptSummary = promptSummary
        self.submittedAtMs = submittedAtMs
    }
    // swiftlint:enable function_default_parameter_at_end
}

public struct AiChatSessionSnapshot: Codable, Equatable, Sendable {
    public let sessionID: AiChatSessionID
    public let status: AiChatSessionStatus
    public let customTitle: String?
    public let provider: AiProvider?
    public let model: AiModelHandle?
    public let selectedModelRow: AiModelCatalogRow?
    public let selectedThinking: AiThinkingSelection?
    public let transcriptHistory: [AiChatMessage]
    public let lastRequestID: AiChatRequestID?
    public let lastRunID: AiChatRunID?
    public let lastRequestContext: AiChatLockedRequestContextSnapshot?
    public let updatedAtMs: Int64

    // swiftlint:disable function_default_parameter_at_end
    public init(
        sessionID: AiChatSessionID,
        status: AiChatSessionStatus,
        customTitle: String? = nil,
        provider: AiProvider?,
        model: AiModelHandle?,
        selectedModelRow: AiModelCatalogRow? = nil,
        selectedThinking: AiThinkingSelection? = nil,
        transcriptHistory: [AiChatMessage] = [],
        lastRequestID: AiChatRequestID? = nil,
        lastRunID: AiChatRunID? = nil,
        lastRequestContext: AiChatLockedRequestContextSnapshot? = nil,
        updatedAtMs: Int64,
    ) {
        self.sessionID = sessionID
        self.status = status
        self.customTitle = customTitle
        self.provider = provider
        self.model = model
        self.selectedModelRow = selectedModelRow
        self.selectedThinking = selectedThinking
        self.transcriptHistory = transcriptHistory
        self.lastRequestID = lastRequestID
        self.lastRunID = lastRunID
        self.lastRequestContext = lastRequestContext
        self.updatedAtMs = updatedAtMs
    }
    // swiftlint:enable function_default_parameter_at_end
}

public struct AiChatSessionSummary: Codable, Equatable, Sendable {
    public static func automaticTitle(from value: String, limit: Int = 32) -> String {
        let collapsed = normalizedSummaryText(value)
        let sentence = firstSentence(in: collapsed)
        return normalizedSummaryText(sentence, limit: limit)
    }

    public let sessionID: AiChatSessionID
    public let title: String
    public let preview: String?
    public let messageCount: Int
    public let contextTitle: String?
    public let searchText: String?
    public let provider: AiProvider?
    public let model: AiModelHandle?
    public let createdAtMs: Int64
    public let updatedAtMs: Int64
    public let status: AiChatSessionStatus

    // swiftlint:disable function_default_parameter_at_end
    public init(
        sessionID: AiChatSessionID,
        title: String,
        preview: String? = nil,
        messageCount: Int,
        contextTitle: String? = nil,
        searchText: String? = nil,
        provider: AiProvider?,
        model: AiModelHandle?,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        status: AiChatSessionStatus,
    ) {
        self.sessionID = sessionID
        self.title = title
        self.preview = preview
        self.messageCount = messageCount
        self.contextTitle = contextTitle
        self.searchText = searchText
        self.provider = provider
        self.model = model
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.status = status
    }
    // swiftlint:enable function_default_parameter_at_end

    fileprivate static func normalizedSummaryText(_ value: String, limit: Int = 120) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        let prefix = String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSpace = prefix.lastIndex(of: " ") else { return prefix }
        let wordBoundary = String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        return wordBoundary.count >= max(12, limit / 2) ? wordBoundary : prefix
    }

    private static func firstSentence(in value: String) -> String {
        let sentenceEndCharacters = CharacterSet(charactersIn: ".!?。！？")
        guard let range = value.rangeOfCharacter(from: sentenceEndCharacters) else { return value }
        return String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }


    public init(snapshot: AiChatSessionSnapshot) {
        self.init(
            sessionID: snapshot.sessionID,
            title: snapshot.sessionTitle,
            preview: snapshot.sessionPreview,
            messageCount: snapshot.transcriptHistory.count,
            contextTitle: snapshot.contextTitle,
            searchText: snapshot.transcriptSearchText,
            provider: snapshot.provider,
            model: snapshot.model,
            createdAtMs: snapshot.createdAtMs,
            updatedAtMs: snapshot.updatedAtMs,
            status: snapshot.status,
        )
    }
}

public enum AiChatSessionRestoreResult: Codable, Equatable, Sendable {
    case restored(snapshot: AiChatSessionSnapshot)
    case newSession(snapshot: AiChatSessionSnapshot)
    case rebindRequired(snapshot: AiChatSessionSnapshot)
    case failed(reason: AiChatSessionRestoreFailure)
}

private extension AiChatSessionSnapshot {
    var createdAtMs: Int64 {
        updatedAtMs
    }

    var sessionTitle: String {
        customTitle.map { AiChatSessionSummary.normalizedSummaryText($0) }?.nilIfBlank
            ?? sessionTitleCandidate
            ?? contextTitle
            ?? selectedModelRow?.displayName
            ?? model?.rawValue
            ?? "New Chat"
    }

    var sessionPreview: String? {
        transcriptHistory
            .reversed()
            .compactMap(\.content.nilIfBlank)
            .map { AiChatSessionSummary.normalizedSummaryText($0) }
            .first
    }

    var transcriptSearchText: String? {
        transcriptHistory
            .compactMap(\.content.nilIfBlank)
            .map { Self.normalizedSearchText($0) }
            .joined(separator: " ")
            .nilIfBlank
    }

    var contextTitle: String? {
        let currentContext = lastRequestContext?.currentContext
        return currentContext?.summary?.nilIfBlank
            ?? currentContext?.items.lazy.compactMap(\.title).first(where: { $0.nilIfBlank != nil })?.nilIfBlank
            ?? currentContext?.references.lazy.compactMap(\.title).first(where: { $0.nilIfBlank != nil })?.nilIfBlank
            ?? currentContext?.attachments.lazy.compactMap(\.title).first(where: { $0.nilIfBlank != nil })?.nilIfBlank
    }

    private var sessionTitleCandidate: String? {
        transcriptHistory
            .first(where: { $0.role == .user })?
            .content
            .nilIfBlank
            .map { AiChatSessionSummary.automaticTitle(from: $0) }
    }

    static func normalizedSearchText(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension AiChatCurrentContextSnapshot {
    var isEmpty: Bool {
        let summaryIsEmpty = summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return summaryIsEmpty && references.isEmpty && items.isEmpty && attachments.isEmpty
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension AiChatAttachmentDraft {
    var containsBrokenReference: Bool {
        guard case let .resolved(result) = currentStatus else {
            return false
        }
        guard case let .failure(reason, _) = result else {
            return false
        }
        return reason == .brokenReference
    }
}
