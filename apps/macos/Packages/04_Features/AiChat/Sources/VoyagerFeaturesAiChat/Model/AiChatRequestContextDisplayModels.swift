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
    public var folderStructureMode: AiChatFolderStructureMode?
    public var supportsFolderStructureMode: Bool

    public init(
        title: String,
        detail: String?,
        iconSystemName: String? = nil,
        iconAssetName: String? = nil,
        iconFilePath: String? = nil,
        folderStructureMode: AiChatFolderStructureMode? = nil,
        supportsFolderStructureMode: Bool = false,
    ) {
        self.title = title
        self.detail = detail
        self.iconSystemName = iconSystemName
        self.iconAssetName = iconAssetName
        self.iconFilePath = iconFilePath
        self.folderStructureMode = folderStructureMode
        self.supportsFolderStructureMode = supportsFolderStructureMode
    }
}

public struct AiChatAddedAttachmentChipDisplayModel: Identifiable, Equatable, Sendable {
    public var id: AiChatAttachmentID {
        attachmentID
    }

    public var attachmentID: AiChatAttachmentID
    public var title: String
    public var statusLabel: String
    public var statusDetail: String
    public var isRemovable: Bool
    public var source: AiChatAttachmentSource
    public var iconSystemName: String?
    public var iconAssetName: String?
    public var iconFilePath: String?
    public var folderStructureMode: AiChatFolderStructureMode?
    public var supportsFolderStructureMode: Bool

    public init(
        attachmentID: AiChatAttachmentID,
        title: String,
        statusLabel: String,
        statusDetail: String,
        isRemovable: Bool,
        source: AiChatAttachmentSource = .file,
        iconSystemName: String? = nil,
        iconAssetName: String? = nil,
        iconFilePath: String? = nil,
        folderStructureMode: AiChatFolderStructureMode? = nil,
        supportsFolderStructureMode: Bool = false,
    ) {
        self.attachmentID = attachmentID
        self.title = title
        self.statusLabel = statusLabel
        self.statusDetail = statusDetail
        self.isRemovable = isRemovable
        self.source = source
        self.iconSystemName = iconSystemName
        self.iconAssetName = iconAssetName
        self.iconFilePath = iconFilePath
        self.folderStructureMode = folderStructureMode
        self.supportsFolderStructureMode = supportsFolderStructureMode
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
