import Foundation

public struct FileTag: Equatable, Sendable, Hashable {
    public let name: String
    public let colorCode: Int

    public nonisolated init(name: String, colorCode: Int) {
        self.name = name
        self.colorCode = colorCode
    }
}

public struct FSItem: Identifiable, Sendable {
    public let id: String // fullPath를 ID로 사용
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
    public let tags: [FileTag]?
    public let additionalInfo: String?

    public nonisolated init(
        name: String,
        fullPath: String,
        isDirectory: Bool,
        isHidden: Bool,
        size: Int64 = 0,
        modifiedDate: Date = Date(),
        createdDate: Date = Date(),
        addedDate: Date = Date(),
        lastOpenedDate: Date? = nil,
        fileExtension: String = "",
        kind: String = "",
        creatorApplication: String? = nil,
        tags: [FileTag]? = nil,
        additionalInfo: String? = nil,
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
    }
}

extension FSItem: Equatable {
    public static func == (lhs: FSItem, rhs: FSItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.modifiedDate == rhs.modifiedDate &&
            lhs.size == rhs.size &&
            lhs.tags == rhs.tags
    }

    public static func temporaryFolder(id: String, name: String) -> FSItem {
        FSItem(
            name: name,
            fullPath: id,
            isDirectory: true,
            isHidden: false,
            kind: "Folder",
        )
    }
}
