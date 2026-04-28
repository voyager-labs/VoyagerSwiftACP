import Foundation

public struct EntryActionRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operationKind: OperationKind
    public let timestamp: Date
    public let targets: [Target]

    public struct Target: Equatable, Sendable {
        public let beforePath: String?
        public let afterPath: String?
        public let beforeTags: [String]?
        public let afterTags: [String]?

        public nonisolated init(
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

    public nonisolated init(
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
