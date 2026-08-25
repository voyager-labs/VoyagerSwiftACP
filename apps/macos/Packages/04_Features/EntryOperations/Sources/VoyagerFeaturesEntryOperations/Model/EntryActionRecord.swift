import Foundation

public struct EntryActionRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let operationKind: OperationKind
    public let timestamp: Date
    public let targets: [Target]
    public let failedCount: Int
    /// 실제 성공 시도 수. targets는 undo 가능한 의미론적 변환 경로만 담으므로
    /// 비-undo 연산의 성공 집계는 이 값으로 별도 전달한다.
    public let succeededCount: Int

    public var attemptedCount: Int {
        succeededCount + failedCount
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
        succeededCount: Int? = nil,
        id: UUID = UUID(),
        timestamp: Date = Date(),
    ) {
        self.id = id
        self.operationKind = operationKind
        self.timestamp = timestamp
        self.targets = targets
        self.failedCount = max(0, failedCount)
        // 의미론적 target 기반 연산은 성공 수가 targets 수와 일치한다.
        self.succeededCount = max(0, succeededCount ?? targets.count)
    }
}
