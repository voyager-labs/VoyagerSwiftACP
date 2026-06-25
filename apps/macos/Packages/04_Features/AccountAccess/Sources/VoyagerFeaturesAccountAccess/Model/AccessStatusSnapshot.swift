import Foundation

public struct AccessStatusSnapshot: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var currentPeriodEnd: Date?
    public var fetchedAt: Date
    public init(
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        fetchedAt: Date = Date(),
    ) {
        self.status = status
        self.currentPeriodEnd = currentPeriodEnd
        self.fetchedAt = fetchedAt
    }

    public var isActive: Bool {
        status.isActive
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let currentPeriodEnd else { return false }
        return now >= currentPeriodEnd
    }
}
