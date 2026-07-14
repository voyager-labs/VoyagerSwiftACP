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

    public init(
        hasAccess: Bool,
        status: String,
        reason: String? = nil,
        productKey: String? = nil,
        currentPeriodEnd: Date? = nil,
        source: String? = nil,
    ) {
        self.hasAccess = hasAccess
        self.status = status
        self.reason = reason
        self.productKey = productKey
        self.currentPeriodEnd = currentPeriodEnd
        self.source = source
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
