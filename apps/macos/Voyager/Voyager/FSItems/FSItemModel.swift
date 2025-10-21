import Foundation

struct FSItemModel: Identifiable, Equatable, Sendable {
    let id: String // fullPath를 ID로 사용
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let isHidden: Bool
    let size: Int64
    let modifiedDate: Date
    let fileExtension: String
    let kind: String

    nonisolated init(
        name: String,
        fullPath: String,
        isDirectory: Bool,
        isHidden: Bool,
        size: Int64 = 0,
        modifiedDate: Date = Date(),
        fileExtension: String = "",
        kind: String = ""
    ) {
        id = fullPath
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.size = size
        self.modifiedDate = modifiedDate
        self.fileExtension = fileExtension
        self.kind = kind
    }
}
