@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
extension ACC002CheckEntitlementStatusTests {
    /// ACC-002-trusted-snapshot-fallback: 정책은 모든 필수 신뢰 경계 위반을 거부한다.
    /// - 검증 내용: envelope, session, snapshot, device, 시간 경계의 단일 위반마다 nil을 반환한다.
    /// - 사전 조건: 한 개의 유효 fixture에서 각 행이 하나의 정책 입력만 변경한다.
    /// - 기대 결과: 각 행은 fallback unlock 후보를 만들지 않는다.
    func testTrustedFallbackSnapshotPolicyRejectsMandatoryInvariantViolations() {
        let cases: [(String, (inout TrustedFallbackSnapshotFixture) -> Void)] = [
            ("non-finite now", { $0.now = Date(timeIntervalSinceReferenceDate: .nan) }),
            ("missing expected binding", { $0.expectedBinding = nil }),
            ("missing envelope", { $0.envelope = nil }),
            ("legacy envelope", { fixture in fixture.replaceEnvelope(isLegacy: true) }),
            ("stale envelope schema", { fixture in fixture.replaceEnvelope(schemaVersion: 0) }),
            ("missing envelope snapshot", { fixture in fixture.replaceEnvelope(snapshot: .some(nil)) }),
            ("envelope binding mismatch", { fixture in fixture.replaceEnvelope(binding: UUID()) }),
            ("envelope gateway mismatch", { fixture in fixture.replaceEnvelope(gateway: "other") }),
            ("missing persisted session", { $0.persistedSession = nil }),
            ("persisted binding mismatch", { fixture in fixture.persistedSession?.sessionBindingID = UUID() }),
            ("empty refresh token", { fixture in fixture.persistedSession?.refreshToken = "" }),
            ("missing persisted expiry", { fixture in fixture.persistedSession?.expiresAt = nil }),
            ("expired persisted session", { fixture in
                let now = fixture.now
                fixture.persistedSession?.expiresAt = now
            }),
            ("non-finite persisted expiry", { fixture in
                fixture.persistedSession?.expiresAt = Date(timeIntervalSinceReferenceDate: .nan)
            }),
            ("expired state session", { fixture in fixture.currentStateSessionExpiry = fixture.now }),
            ("non-finite state session", { fixture in
                fixture.currentStateSessionExpiry = Date(timeIntervalSinceReferenceDate: .nan)
            }),
            ("stale snapshot schema", { fixture in fixture.mutateSnapshot { $0.schemaVersion = 0 } }),
            ("snapshot binding mismatch", { fixture in fixture.mutateSnapshot { $0.sessionBindingID = UUID() } }),
            ("snapshot gateway mismatch", { fixture in fixture.mutateSnapshot { $0.gatewayBinding = "other" } }),
            ("inactive snapshot", { fixture in fixture.mutateSnapshot { $0.status = .revoked } }),
            ("empty snapshot device", { fixture in fixture.mutateSnapshot { $0.deviceID = "" } }),
            ("missing current device", { $0.currentDeviceID = nil }),
            ("device mismatch", { $0.currentDeviceID = "other-device" }),
            ("empty current device", { $0.currentDeviceID = "" }),
            ("non-finite fetched time", { fixture in
                fixture.mutateSnapshot { $0.fetchedAt = Date(timeIntervalSinceReferenceDate: .nan) }
            }),
            (
                "future fetched time",
                { fixture in fixture.mutateSnapshotUsingNow { $0.fetchedAt = $1.addingTimeInterval(1) } },
            ),
            (
                "exact seven-day snapshot age",
                { fixture in fixture.mutateSnapshotUsingNow { $0.fetchedAt = $1.addingTimeInterval(-604_800) } },
            ),
            ("missing proof", { fixture in fixture.mutateSnapshot { $0.deviceBindingVerifiedAt = nil } }),
            ("non-finite proof", { fixture in
                fixture.mutateSnapshot { $0.deviceBindingVerifiedAt = Date(timeIntervalSinceReferenceDate: .nan) }
            }),
            (
                "proof after fetch",
                { fixture in
                    fixture.mutateSnapshotUsingNow { $0.deviceBindingVerifiedAt = $1.addingTimeInterval(1) }
                },
            ),
            (
                "exact seven-day proof age",
                { fixture in
                    fixture.mutateSnapshotUsingNow { $0.deviceBindingVerifiedAt = $1.addingTimeInterval(-604_800) }
                },
            ),
            ("missing snapshot session expiry", { fixture in fixture.mutateSnapshot { $0.sessionExpiresAt = nil } }),
            ("non-finite snapshot session", { fixture in
                fixture.mutateSnapshot { $0.sessionExpiresAt = Date(timeIntervalSinceReferenceDate: .nan) }
            }),
            ("expired snapshot session", { fixture in fixture.mutateSnapshotUsingNow { $0.sessionExpiresAt = $1 } }),
            ("non-finite period", { fixture in
                fixture.mutateSnapshot { $0.currentPeriodEnd = Date(timeIntervalSinceReferenceDate: .nan) }
            }),
            ("expired period", { fixture in fixture.mutateSnapshotUsingNow { $0.currentPeriodEnd = $1 } }),
        ]

        for (name, mutate) in cases {
            var fixture = TrustedFallbackSnapshotFixture()
            mutate(&fixture)
            XCTAssertNil(fixture.validatedAdmission(), name)
        }
    }

    /// ACC-002-trusted-snapshot-fallback: 정책은 허용한 시간 및 세션 회전 변형을 수락한다.
    /// - 검증 내용: nil period, proof가 fetch보다 이전, 서로 다른 미래 expiry, 7일 직전 age를 허용한다.
    /// - 사전 조건: binding, gateway, device, refresh credential은 유효하다.
    /// - 기대 결과: 원본 snapshot을 fallback unlock 후보로 반환한다.
    func testTrustedFallbackSnapshotPolicyAcceptsValidTemporalVariants() {
        let cases: [(String, (inout TrustedFallbackSnapshotFixture) -> Void)] = [
            ("baseline", { _ in }),
            ("nil period", { fixture in fixture.mutateSnapshot { $0.currentPeriodEnd = nil } }),
            ("proof before fetch", { fixture in
                fixture.mutateSnapshotUsingNow {
                    $0.fetchedAt = $1.addingTimeInterval(-60)
                    $0.deviceBindingVerifiedAt = $1.addingTimeInterval(-120)
                }
            }),
            ("different future expiries", { fixture in
                let now = fixture.now
                fixture.persistedSession?.expiresAt = now.addingTimeInterval(3600)
                fixture.currentStateSessionExpiry = now.addingTimeInterval(7200)
                fixture.mutateSnapshot { $0.sessionExpiresAt = now.addingTimeInterval(10800) }
            }),
            ("maximum age just inside", { fixture in
                fixture.mutateSnapshotUsingNow {
                    $0.fetchedAt = $1.addingTimeInterval(-604_799)
                    $0.deviceBindingVerifiedAt = $1.addingTimeInterval(-604_799)
                }
            }),
        ]

        for (name, mutate) in cases {
            var fixture = TrustedFallbackSnapshotFixture()
            mutate(&fixture)
            let admission = fixture.validatedAdmission()
            XCTAssertEqual(admission?.snapshot, fixture.snapshot, name)
            XCTAssertGreaterThan(admission?.validUntil ?? .distantPast, fixture.now, name)
        }
    }
}

private struct TrustedFallbackSnapshotFixture {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    var expectedBinding: UUID?
    var gatewayBinding = GatewayEnvironment(rawValue: "").binding
    var currentDeviceID: String? = "test-device-id"
    var currentStateSessionExpiry: Date?
    var persistedSession: AccountSession?
    var snapshot: AccessStatusSnapshot
    var envelope: AccessStatusSnapshotEnvelope?

    init() {
        let binding = UUID()
        expectedBinding = binding
        let expiry = now.addingTimeInterval(3600)
        snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: now.addingTimeInterval(7200),
            fetchedAt: now,
            sessionBindingID: binding,
            gatewayBinding: gatewayBinding,
            deviceID: currentDeviceID,
            sessionExpiresAt: expiry,
            deviceBindingVerifiedAt: now,
        )
        envelope = AccessStatusSnapshotEnvelope(
            sessionBindingID: binding,
            gatewayBinding: gatewayBinding,
            mutationGeneration: 1,
            snapshot: snapshot,
        )
        persistedSession = AccountSession(
            accessToken: "access-token",
            status: .coreLicenseActive,
            refreshToken: "refresh-token",
            expiresAt: expiry,
            sessionBindingID: binding,
        )
        currentStateSessionExpiry = expiry
    }

    mutating func mutateSnapshot(_ mutate: (inout AccessStatusSnapshot) -> Void) {
        mutate(&snapshot)
        envelope = envelope(snapshot: snapshot)
    }

    mutating func mutateSnapshotUsingNow(_ mutate: (inout AccessStatusSnapshot, Date) -> Void) {
        let now = now
        mutate(&snapshot, now)
        envelope = envelope(snapshot: snapshot)
    }

    mutating func replaceEnvelope(
        binding: UUID? = nil,
        gateway: String? = nil,
        schemaVersion: Int? = nil,
        isLegacy: Bool = false,
        snapshot: AccessStatusSnapshot?? = nil,
    ) {
        let replacement = envelope(
            binding: binding,
            gateway: gateway,
            schemaVersion: schemaVersion,
            isLegacy: isLegacy,
            snapshot: snapshot,
        )
        envelope = replacement
    }

    func validatedAdmission() -> TrustedFallbackSnapshotPolicy.Admission? {
        TrustedFallbackSnapshotPolicy.validatedAdmission(.init(
            envelope: envelope,
            persistedSession: persistedSession,
            expectedBinding: expectedBinding,
            currentStateSessionExpiry: currentStateSessionExpiry,
            gatewayBinding: gatewayBinding,
            currentDeviceID: currentDeviceID,
            now: now,
        ))
    }

    func envelope(
        binding: UUID? = nil,
        gateway: String? = nil,
        schemaVersion: Int? = nil,
        isLegacy: Bool = false,
        snapshot: AccessStatusSnapshot?? = nil,
    ) -> AccessStatusSnapshotEnvelope {
        AccessStatusSnapshotEnvelope(
            sessionBindingID: binding ?? expectedBinding,
            gatewayBinding: gateway ?? gatewayBinding,
            mutationGeneration: 1,
            snapshot: snapshot ?? self.snapshot,
            isLegacy: isLegacy,
            schemaVersion: schemaVersion ?? AccessStatusSnapshotEnvelope.currentSchemaVersion,
        )
    }
}
