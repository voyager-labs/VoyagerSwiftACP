import Foundation

struct FSItem: Identifiable, Equatable, Sendable {
    let id: String // fullPath를 ID로 사용
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let isHidden: Bool
    let size: Int64
    let modifiedDate: Date
    let createdDate: Date
    let addedDate: Date
    let lastOpenedDate: Date?
    let fileExtension: String
    let kind: String
    let creatorApplication: String?
    let tags: [String]?

    nonisolated init(
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
        tags: [String]? = nil
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
    }
}
