import Foundation

/// GET /access/status backend 응답 DTO. Backend raw status(Polar) + productKey 조합으로 구성되며,
/// `toAccessStatus()`로 canonical `AccessStatus`로 변환한다.
public struct AccessStatusResponse: Equatable, Sendable, Codable {
    public var hasAccess: Bool
    public var status: String
    public var reason: String?
    public var productKey: String?
    public var currentPeriodEnd: Date?
    public var source: String?
    public var ownershipStatus: String?
    public var updateStatus: String?
    public var updatesThrough: Date?

    public init(
        hasAccess: Bool,
        status: String,
        ownershipStatus: String? = nil,
        updateStatus: String? = nil,
        reason: String? = nil,
        productKey: String? = nil,
        currentPeriodEnd: Date? = nil,
        source: String? = nil,
        updatesThrough: Date? = nil,
    ) {
        self.hasAccess = hasAccess
        self.status = status
        self.reason = reason
        self.productKey = productKey
        self.currentPeriodEnd = currentPeriodEnd
        self.source = source
        self.ownershipStatus = ownershipStatus
        self.updateStatus = updateStatus
        self.updatesThrough = updatesThrough
    }

    private enum CodingKeys: String, CodingKey {
        case hasAccess = "has_access"
        case status
        case reason
        case productKey = "product_key"
        case currentPeriodEnd = "current_period_end"
        case source
        case ownershipStatus = "ownership_status"
        case updateStatus = "update_status"
        case updatesThrough = "updates_through"
    }

    private enum GatewayAliasCodingKeys: String, CodingKey {
        case hasAccess
        case productKey
        case currentPeriodEnd
    }

    public init(from decoder: Decoder) throws {
        let canonical = try decoder.container(keyedBy: CodingKeys.self)
        let aliases = try decoder.container(keyedBy: GatewayAliasCodingKeys.self)

        if canonical.contains(.hasAccess) {
            hasAccess = try canonical.decode(Bool.self, forKey: .hasAccess)
        } else {
            hasAccess = try aliases.decode(Bool.self, forKey: .hasAccess)
        }
        status = try canonical.decode(String.self, forKey: .status)
        reason = try canonical.decodeIfPresent(String.self, forKey: .reason)
        if canonical.contains(.productKey) {
            productKey = try canonical.decodeIfPresent(String.self, forKey: .productKey)
        } else {
            productKey = try aliases.decodeIfPresent(String.self, forKey: .productKey)
        }
        if canonical.contains(.currentPeriodEnd) {
            currentPeriodEnd = try canonical.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
        } else {
            currentPeriodEnd = try aliases.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
        }
        source = try canonical.decodeIfPresent(String.self, forKey: .source)
        ownershipStatus = try canonical.decodeIfPresent(String.self, forKey: .ownershipStatus)
        updateStatus = try canonical.decodeIfPresent(String.self, forKey: .updateStatus)
        updatesThrough = try canonical.decodeIfPresent(Date.self, forKey: .updatesThrough)
    }

    /// Backend raw status + productKey → canonical AccessStatus 변환.
    /// - hasAccess=true + productKey="trial" → .trialActive
    /// - hasAccess=true + 그 외 productKey → .coreLicenseActive (core/lifetime/renewal/extra_mac/null 모두 license로 취급)
    /// - hasAccess=false + status="revoked" → .revoked
    /// - hasAccess=false + status="refunded" → .refunded
    /// - hasAccess=false + status="expired" + productKey="trial" → .trialExpired
    /// - hasAccess=false + status="expired" + 그 외 → .none
    /// - 그 외 (inactive, past_due, none) → .none
    public func toAccessStatus() -> AccessStatus {
        if let canonicalStatus = AccessStatus(rawValue: status) {
            return canonicalStatus
        }

        if hasAccess {
            switch productKey {
            case "trial": return .trialActive
            default: return .coreLicenseActive
            }
        }
        switch status {
        case "revoked": return .revoked
        case "refunded": return .refunded
        case "expired":
            return productKey == "trial" ? .trialExpired : .none
        default: return .none
        }
    }
}
