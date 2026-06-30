import Foundation

public struct AccessStatusSnapshot: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var currentPeriodEnd: Date?
    public var fetchedAt: Date

    private enum CodingKeys: String, CodingKey {
        case status
        case currentPeriodEnd
        case expiresAt
        case fetchedAt
    }

    public init(
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        fetchedAt: Date = Date(),
    ) {
        self.status = status
        self.currentPeriodEnd = currentPeriodEnd
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(AccessStatus.self, forKey: .status)
        currentPeriodEnd = try container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
            ?? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(currentPeriodEnd, forKey: .currentPeriodEnd)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    public var isActive: Bool {
        status.isActive
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let currentPeriodEnd else { return false }
        return now >= currentPeriodEnd
    }
}
