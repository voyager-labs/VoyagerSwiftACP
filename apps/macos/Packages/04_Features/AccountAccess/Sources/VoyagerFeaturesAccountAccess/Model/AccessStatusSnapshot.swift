import Foundation

public struct AccessStatusSnapshot: Equatable, Sendable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var status: AccessStatus
    public var currentPeriodEnd: Date?
    public var fetchedAt: Date
    public var sessionBindingID: UUID?
    public var gatewayBinding: String
    public var deviceID: String?
    /// 세션 축: 세션 존재 여부 및 만료 시점. `nil`이면 세션 없음(미로그인).
    public var sessionExpiresAt: Date?
    /// 현재 기기 binding 검증 시각. `nil`이면 active entitlement만으로 unlock을 확정하지 않는다.
    public var deviceBindingVerifiedAt: Date?
    /// 서버가 인증한 구매 소유권 유형. 구형 snapshot과의 호환성을 위해 optional이다.
    public var ownershipStatus: String?
    /// 서버가 인증한 업데이트 권한 유형. 구형 snapshot과의 호환성을 위해 optional이다.
    public var updateStatus: String?
    /// 이 build를 실행할 수 있는 마지막 출시 시각.
    public var updatesThrough: Date?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case currentPeriodEnd
        case expiresAt
        case fetchedAt
        case sessionBindingID
        case gatewayBinding
        case deviceID
        case sessionExpiresAt
        case deviceBindingVerifiedAt
        case ownershipStatus
        case updateStatus
        case updatesThrough
    }

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        fetchedAt: Date = Date(),
        sessionBindingID: UUID? = nil,
        gatewayBinding: String = "",
        deviceID: String? = nil,
        sessionExpiresAt: Date? = nil,
        deviceBindingVerifiedAt: Date? = nil,
        ownershipStatus: String? = nil,
        updateStatus: String? = nil,
        updatesThrough: Date? = nil,
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.currentPeriodEnd = currentPeriodEnd
        self.fetchedAt = fetchedAt
        self.sessionBindingID = sessionBindingID
        self.gatewayBinding = gatewayBinding
        self.deviceID = deviceID
        self.sessionExpiresAt = sessionExpiresAt
        self.deviceBindingVerifiedAt = deviceBindingVerifiedAt
        self.ownershipStatus = ownershipStatus
        self.updateStatus = updateStatus
        self.updatesThrough = updatesThrough
    }

    /// access_status 조회 결과와 현재 세션 축을 하나의 복구 스냅샷으로 고정한다.
    public static func fetchResult(
        status: AccessStatus,
        currentPeriodEnd: Date? = nil,
        sessionExpiresAt: Date? = nil,
        fetchedAt: Date = Date(),
        sessionBindingID: UUID? = nil,
        gatewayBinding: String = "",
        deviceID: String? = nil,
        deviceBindingVerifiedAt: Date? = nil,
        ownershipStatus: String? = nil,
        updateStatus: String? = nil,
        updatesThrough: Date? = nil,
    ) -> Self {
        Self(
            status: status,
            currentPeriodEnd: currentPeriodEnd,
            fetchedAt: fetchedAt,
            sessionBindingID: sessionBindingID,
            gatewayBinding: gatewayBinding,
            deviceID: deviceID,
            sessionExpiresAt: sessionExpiresAt,
            deviceBindingVerifiedAt: deviceBindingVerifiedAt,
            ownershipStatus: ownershipStatus,
            updateStatus: updateStatus,
            updatesThrough: updatesThrough,
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        status = try container.decode(AccessStatus.self, forKey: .status)
        currentPeriodEnd = try container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
            ?? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        sessionBindingID = try container.decodeIfPresent(UUID.self, forKey: .sessionBindingID)
        gatewayBinding = try container.decodeIfPresent(String.self, forKey: .gatewayBinding) ?? ""
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        // 세션 축 backward compat: 키 없으면 nil
        sessionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .sessionExpiresAt)
        // device binding proof backward compat: 키 없으면 nil
        deviceBindingVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .deviceBindingVerifiedAt)
        ownershipStatus = try container.decodeIfPresent(String.self, forKey: .ownershipStatus)
        updateStatus = try container.decodeIfPresent(String.self, forKey: .updateStatus)
        updatesThrough = try container.decodeIfPresent(Date.self, forKey: .updatesThrough)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(currentPeriodEnd, forKey: .currentPeriodEnd)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(sessionBindingID, forKey: .sessionBindingID)
        try container.encode(gatewayBinding, forKey: .gatewayBinding)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encodeIfPresent(sessionExpiresAt, forKey: .sessionExpiresAt)
        try container.encodeIfPresent(deviceBindingVerifiedAt, forKey: .deviceBindingVerifiedAt)
        try container.encodeIfPresent(ownershipStatus, forKey: .ownershipStatus)
        try container.encodeIfPresent(updateStatus, forKey: .updateStatus)
        try container.encodeIfPresent(updatesThrough, forKey: .updatesThrough)
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
