import Foundation

struct FSItemModel: Identifiable, Equatable, Sendable {
    let id: String // fullPath를 ID로 사용
    let name: String
    let fullPath: String
    let isDirectory: Bool

    nonisolated init(name: String, fullPath: String, isDirectory: Bool) {
        id = fullPath
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
    }
}
