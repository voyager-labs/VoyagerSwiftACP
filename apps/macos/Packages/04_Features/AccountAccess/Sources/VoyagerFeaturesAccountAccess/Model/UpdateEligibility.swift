import Foundation
import VoyagerShared

public enum UpdateEligibilityFailure: Equatable, Sendable {
    case missingReleaseIdentity
    case invalidReleaseIdentity
    case missingUpdatesThrough
    case invalidUpdatesThrough
    case invalidAccessTuple
    case buildReleasedAfterUpdatesThrough(releasedAt: Date, updatesThrough: Date)
}

public enum UpdateEligibilityEvaluator {
    /// Canonical ownership/update tuple과 release identity를 함께 검증한다.
    /// Lifetime 및 active trial은 update boundary 없이 최신 release를 허용하고,
    /// expired Core만 `releasedAt <= updatesThrough`를 요구한다.
    public static func evaluate(
        releaseIdentity: ReleaseIdentity?,
        hasAccess: Bool,
        ownershipStatus: String?,
        updateStatus: String?,
        updatesThrough: Date?,
    ) -> UpdateEligibilityFailure? {
        guard let releaseIdentity else { return .missingReleaseIdentity }

        switch (hasAccess, ownershipStatus, updateStatus) {
        case (true, "owned", "perpetual"),
             (true, "trial", "active"),
             (true, "owned", "active"):
            guard updatesThrough == nil || updatesThrough?.timeIntervalSinceReferenceDate.isFinite == true else {
                return .invalidUpdatesThrough
            }
            return nil

        case (true, "owned", "expired"):
            guard let updatesThrough else { return .missingUpdatesThrough }
            guard updatesThrough.timeIntervalSinceReferenceDate.isFinite else {
                return .invalidUpdatesThrough
            }
            guard releaseIdentity.releasedAt <= updatesThrough else {
                return .buildReleasedAfterUpdatesThrough(
                    releasedAt: releaseIdentity.releasedAt,
                    updatesThrough: updatesThrough,
                )
            }
            return nil

        default:
            return .invalidAccessTuple
        }
    }
}
