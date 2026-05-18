import Foundation
import VoyagerEntitiesAi

public enum AiChatRequestContextDisplaySource: Equatable, Sendable {
    case draft
    case locked
}

public struct AiChatCurrentContextChipDisplayModel: Equatable, Sendable {
    public var title: String
    public var detail: String?
    public var iconSystemName: String?
    public var iconAssetName: String?
    public var iconFilePath: String?

    public init(
        title: String,
        detail: String?,
        iconSystemName: String? = nil,
        iconAssetName: String? = nil,
        iconFilePath: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.iconSystemName = iconSystemName
        self.iconAssetName = iconAssetName
        self.iconFilePath = iconFilePath
    }
}

public struct AiChatAddedAttachmentChipDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiChatAttachmentID { attachmentID }

    public var attachmentID: AiChatAttachmentID
    public var title: String
    public var statusLabel: String
    public var isRemovable: Bool
    public var iconSystemName: String?
    public var iconAssetName: String?
    public var iconFilePath: String?

    public init(
        attachmentID: AiChatAttachmentID,
        title: String,
        statusLabel: String,
        isRemovable: Bool,
        iconSystemName: String? = nil,
        iconAssetName: String? = nil,
        iconFilePath: String? = nil
    ) {
        self.attachmentID = attachmentID
        self.title = title
        self.statusLabel = statusLabel
        self.isRemovable = isRemovable
        self.iconSystemName = iconSystemName
        self.iconAssetName = iconAssetName
        self.iconFilePath = iconFilePath
    }
}

public struct AiChatRequestContextDisplayModel: Equatable, Sendable {
    public var source: AiChatRequestContextDisplaySource
    public var currentContext: AiChatCurrentContextChipDisplayModel?
    public var addedAttachments: [AiChatAddedAttachmentChipDisplayModel]

    public init(
        source: AiChatRequestContextDisplaySource,
        currentContext: AiChatCurrentContextChipDisplayModel?,
        addedAttachments: [AiChatAddedAttachmentChipDisplayModel],
    ) {
        self.source = source
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
    }

    public var isEmpty: Bool {
        currentContext == nil && addedAttachments.isEmpty
    }
}
