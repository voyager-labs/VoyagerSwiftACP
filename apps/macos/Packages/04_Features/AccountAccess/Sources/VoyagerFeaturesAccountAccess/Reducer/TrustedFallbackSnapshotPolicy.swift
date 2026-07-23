import Foundation

enum TrustedFallbackSnapshotPolicy {
    struct Context {
        let envelope: AccessStatusSnapshotEnvelope?
        let persistedSession: AccountSession?
        let expectedBinding: UUID?
        let currentStateSessionExpiry: Date?
        let gatewayBinding: String
        let currentDeviceID: String?
        let now: Date
    }

    struct Admission: Equatable {
        let snapshot: AccessStatusSnapshot
        let validUntil: Date
    }

    private static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    static func validatedAdmission(_ context: Context) -> Admission? {
        guard
            context.now.isFinite,
            let expectedBinding = context.expectedBinding,
            let envelope = context.envelope,
            !envelope.isLegacy,
            envelope.schemaVersion == AccessStatusSnapshotEnvelope.currentSchemaVersion,
            let snapshot = envelope.snapshot,
            envelope.sessionBindingID == expectedBinding,
            envelope.gatewayBinding == context.gatewayBinding,
            let persistedSession = context.persistedSession,
            persistedSession.sessionBindingID == expectedBinding,
            persistedSession.refreshToken?.isEmpty == false,
            let persistedSessionExpiry = persistedSession.expiresAt,
            persistedSessionExpiry.isFinite,
            persistedSessionExpiry > context.now,
            let currentStateSessionExpiry = context.currentStateSessionExpiry,
            currentStateSessionExpiry.isFinite,
            currentStateSessionExpiry > context.now,
            snapshot.schemaVersion == AccessStatusSnapshot.currentSchemaVersion,
            snapshot.sessionBindingID == expectedBinding,
            snapshot.gatewayBinding == context.gatewayBinding,
            snapshot.status.isActive,
            let snapshotDeviceID = snapshot.deviceID,
            !snapshotDeviceID.isEmpty,
            let currentDeviceID = context.currentDeviceID,
            !currentDeviceID.isEmpty,
            snapshotDeviceID == currentDeviceID,
            snapshot.fetchedAt.isFinite,
            snapshot.fetchedAt <= context.now,
            let deviceBindingVerifiedAt = snapshot.deviceBindingVerifiedAt,
            deviceBindingVerifiedAt.isFinite,
            deviceBindingVerifiedAt <= snapshot.fetchedAt,
            let snapshotSessionExpiry = snapshot.sessionExpiresAt,
            snapshotSessionExpiry.isFinite,
            snapshotSessionExpiry > context.now
        else {
            return nil
        }

        guard isWithinMaximumAge(snapshot.fetchedAt, now: context.now),
              isWithinMaximumAge(deviceBindingVerifiedAt, now: context.now)
        else {
            return nil
        }

        if let currentPeriodEnd = snapshot.currentPeriodEnd {
            guard currentPeriodEnd.isFinite, currentPeriodEnd > context.now else {
                return nil
            }
        }

        var validityBoundaries = [
            persistedSessionExpiry,
            currentStateSessionExpiry,
            snapshotSessionExpiry,
            snapshot.fetchedAt.addingTimeInterval(maximumAge),
            deviceBindingVerifiedAt.addingTimeInterval(maximumAge),
        ]
        if let currentPeriodEnd = snapshot.currentPeriodEnd {
            validityBoundaries.append(currentPeriodEnd)
        }

        guard let validUntil = validityBoundaries.min(), validUntil.isFinite else {
            return nil
        }
        return Admission(snapshot: snapshot, validUntil: validUntil)
    }

    private static func isWithinMaximumAge(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= 0 && age < maximumAge
    }
}

private extension Date {
    var isFinite: Bool {
        timeIntervalSinceReferenceDate.isFinite
    }
}
