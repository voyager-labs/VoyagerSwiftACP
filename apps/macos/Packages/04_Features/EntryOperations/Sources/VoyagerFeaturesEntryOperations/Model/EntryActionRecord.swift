import Foundation

public struct EntryActionRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operationKind: OperationKind
    public let timestamp: Date
    public let targets: [Target]
    public let failedCount: Int

    public var attemptedCount: Int {
        targets.count + failedCount
    }

    public struct Target: Equatable, Sendable {
        public let beforePath: String?
        public let afterPath: String?
        public let beforeTags: [String]?
        public let afterTags: [String]?

        nonisolated public init(
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

    nonisolated public init(
        operationKind: OperationKind,
        targets: [Target],
        failedCount: Int = 0,
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
        self.failedCount = max(0, failedCount)
    }
}
