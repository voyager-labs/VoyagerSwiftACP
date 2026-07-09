import Foundation

public struct AccessStatusSnapshot: Equatable, Sendable, Codable {
    public var status: AccessStatus
    public var currentPeriodEnd: Date?
    public var fetchedAt: Date
    /// 세션 축: 세션 존재 여부 및 만료 시점. `nil`이면 세션 없음(미로그인).
    public var sessionExpiresAt: Date?
    /// 현재 기기 binding 검증 시각. `nil`이면 active entitlement만으로 unlock을 확정하지 않는다.
    public var deviceBindingVerifiedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case status
        case currentPeriodEnd
        case expiresAt
        case fetchedAt
        case sessionExpiresAt
        case deviceBindingVerifiedAt
    }

    public init(
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        fetchedAt: Date = Date(),
        sessionExpiresAt: Date? = nil,
        deviceBindingVerifiedAt: Date? = nil,
    ) {
        self.status = status
        self.currentPeriodEnd = currentPeriodEnd
        self.fetchedAt = fetchedAt
        self.sessionExpiresAt = sessionExpiresAt
        self.deviceBindingVerifiedAt = deviceBindingVerifiedAt
    }

    /// access_status 조회 결과와 현재 세션 축을 하나의 복구 스냅샷으로 고정한다.
    public static func fetchResult(
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        sessionExpiresAt: Date? = nil,
        fetchedAt: Date = Date(),
        deviceBindingVerifiedAt: Date? = nil,
    ) -> Self {
        Self(
            status: status,
            currentPeriodEnd: currentPeriodEnd,
            fetchedAt: fetchedAt,
            sessionExpiresAt: sessionExpiresAt,
            deviceBindingVerifiedAt: deviceBindingVerifiedAt,
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(AccessStatus.self, forKey: .status)
        currentPeriodEnd = try container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
            ?? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        // 세션 축 backward compat: 키 없으면 nil
        sessionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .sessionExpiresAt)
        // device binding proof backward compat: 키 없으면 nil
        deviceBindingVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .deviceBindingVerifiedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(currentPeriodEnd, forKey: .currentPeriodEnd)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(sessionExpiresAt, forKey: .sessionExpiresAt)
        try container.encodeIfPresent(deviceBindingVerifiedAt, forKey: .deviceBindingVerifiedAt)
    }

    public var isActive: Bool {
        status.isActive
    }

    /// 세션 존재 여부. `sessionExpiresAt != nil`이면 signed-in.
    public var hasSession: Bool {
        sessionExpiresAt != nil
    }

    public var isDeviceBindingVerified: Bool {
        deviceBindingVerifiedAt != nil
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let currentPeriodEnd else { return false }
        return now >= currentPeriodEnd
    }
}
