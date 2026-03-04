import Foundation

struct EntryActionRecord: Equatable, Identifiable, Sendable {
    struct Target: Equatable, Sendable {
        let beforePath: String?
        let afterPath: String?
        let beforeTags: [String]?
        let afterTags: [String]?

        nonisolated init(
            beforePath: String?,
            afterPath: String?,
            beforeTags: [String]? = nil,
            afterTags: [String]? = nil,
        ) {
            self.beforePath = beforePath
            self.afterPath = afterPath
            self.beforeTags = beforeTags
            self.afterTags = afterTags
        }
    }

    let id: UUID
    let operationKind: OperationKind
    let timestamp: Date
    let targets: [Target]

    nonisolated init(
        operationKind: OperationKind,
        targets: [Target],
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
    }
}
