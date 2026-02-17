import Foundation

public struct EntryModel: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let fullPath: String
    public let isDirectory: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modifiedDate: Date
    public let createdDate: Date
    public let addedDate: Date
    public let lastOpenedDate: Date?
    public let fileExtension: String
    public let kind: String
    public let creatorApplication: String?
    public let tags: [Tag]?
    public let additionalInfo: String?

    public let formattedSize: String
    public let formattedModifiedDate: String
    public let formattedCreatedDate: String

    public nonisolated init(
        name: String = "",
        fullPath: String = "",
        isDirectory: Bool = false,
        isHidden: Bool = false,
        size: Int64 = 0,
        modifiedDate: Date = Date(),
        createdDate: Date = Date(),
        addedDate: Date = Date(),
        lastOpenedDate: Date? = nil,
        fileExtension: String = "",
        kind: String = "",
        creatorApplication: String? = nil,
        tags: [Tag]? = nil,
        additionalInfo: String? = nil,
        formattedSize: String = "--",
        formattedModifiedDate: String = "",
        formattedCreatedDate: String = "",
    ) {
        id = fullPath
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.size = size
        self.modifiedDate = modifiedDate
        self.createdDate = createdDate
        self.addedDate = addedDate
        self.lastOpenedDate = lastOpenedDate
        self.fileExtension = fileExtension
        self.kind = kind
        self.creatorApplication = creatorApplication
        self.tags = tags
        self.additionalInfo = additionalInfo
        self.formattedSize = formattedSize
        self.formattedModifiedDate = formattedModifiedDate
        self.formattedCreatedDate = formattedCreatedDate
    }
}

extension EntryModel: Equatable {
    public static func == (lhs: EntryModel, rhs: EntryModel) -> Bool {
        lhs.id == rhs.id &&
            lhs.modifiedDate == rhs.modifiedDate &&
            lhs.size == rhs.size &&
            lhs.tags == rhs.tags
    }

    public static func temporaryFolder(id: String, name: String) -> EntryModel {
        EntryModel(
            name: name,
            fullPath: id,
            isDirectory: true,
            isHidden: false,
            kind: "Folder",
        )
    }
}
