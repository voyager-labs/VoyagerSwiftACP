import Foundation
import VoyagerEntitiesAi

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

struct AiChatFolderStructureMenuItemDisplayModel: Identifiable, Equatable {
    var id: AiChatFolderStructureMode {
        mode
    }

    var mode: AiChatFolderStructureMode
    var title: String
    var isSelected: Bool
    var isEnabled: Bool
    var accessibilityLabel: String
    var accessibilityValue: String

    static func items(
        selectedMode: AiChatFolderStructureMode,
    ) -> [AiChatFolderStructureMenuItemDisplayModel] {
        [
            item(title: "Current folder only", mode: .currentFolderOnly, selectedMode: selectedMode),
            item(title: "Include subfolders", mode: .includeSubfolders, selectedMode: selectedMode),
        ]
    }

    private static func item(
        title: String,
        mode: AiChatFolderStructureMode,
        selectedMode: AiChatFolderStructureMode,
    ) -> AiChatFolderStructureMenuItemDisplayModel {
        let isSelected = mode == selectedMode
        return AiChatFolderStructureMenuItemDisplayModel(
            mode: mode,
            title: title,
            isSelected: isSelected,
            isEnabled: true,
            accessibilityLabel: title,
            accessibilityValue: isSelected ? "Selected" : "Not selected",
        )
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
    public var currentContext: AiChatCurrentContextChipDisplayModel?
    public var addedAttachments: [AiChatAddedAttachmentChipDisplayModel]

    public init(
        currentContext: AiChatCurrentContextChipDisplayModel?,
        addedAttachments: [AiChatAddedAttachmentChipDisplayModel],
    ) {
        self.currentContext = currentContext
        self.addedAttachments = addedAttachments
    }

    public var isEmpty: Bool {
        currentContext == nil && addedAttachments.isEmpty
    }
}
