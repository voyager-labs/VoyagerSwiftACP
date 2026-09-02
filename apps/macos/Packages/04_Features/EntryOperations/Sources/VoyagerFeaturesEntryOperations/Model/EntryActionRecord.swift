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
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
    }

    /// Replay가 실제 적용한 방향의 identity record를 반환한다.
    /// undo는 원본 target을 반대 방향으로 적용하지만 history record 자체는 유지하므로,
    /// downstream projection owner가 사용할 때만 before/after를 뒤집는다.
    public func applying(direction: EntryActionDirection) -> Self {
        guard direction == .undo else { return self }
        return Self(
            operationKind: operationKind,
            targets: targets.map { target in
                Target(
                    beforePath: target.afterPath,
                    afterPath: target.beforePath,
                    beforeTags: target.afterTags,
                    afterTags: target.beforeTags,
                )
            },
            id: id,
            timestamp: timestamp,
        )
    }
}
