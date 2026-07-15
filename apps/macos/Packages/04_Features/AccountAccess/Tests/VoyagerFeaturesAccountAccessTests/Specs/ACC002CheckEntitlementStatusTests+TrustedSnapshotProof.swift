import ComposableArchitecture
@testable import VoyagerFeaturesAccountAccess
import XCTest

@MainActor
extension ACC002CheckEntitlementStatusTests {
    /// ACC-002-check_entitlement_status: binding 완료 시각을 신뢰 복원 증명과 fetch 시각에 함께 기록한다.
    func testDeviceBindingSuccessUsesCompletionTimeForTrustedSnapshotProof() async {
        let bindingCompletionDate = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionExpiry = bindingCompletionDate.addingTimeInterval(3600)
        let periodEnd = bindingCompletionDate.addingTimeInterval(7200)
        var state = AccountAccessFeature.State()
        state.fetchGeneration = 1
        state.syncGeneration = 1
        state.hasAccountSession = true
        state.sessionExpiresAt = sessionExpiry

        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.authNetworkClient = AuthNetworkClient(
                exchangeHandoff: { _, _, _ in throw AccessError.notConfigured },
                fetchAccessStatus: { throw AccessError.notConfigured },
                bindDevice: { _ in DeviceBindingResponse(ok: true) },
                refreshToken: { throw AccessError.notConfigured },
            )
            $0.date = .constant(bindingCompletionDate)
        }

        await store.send(._sessionSyncCompleted(generation: 1, result: .success(SessionSyncResult(
            sessionStatus: .unchanged,
            syncStatus: .complete,
            accessStatus: AccessStatusResponse(
                hasAccess: true,
                status: "active",
                reason: "active_entitlement",
                productKey: "core",
                currentPeriodEnd: periodEnd,
                source: "polar",
            ),
            deviceBindingOutcome: .bound,
            connectedDeviceAvailability: .available,
        )))) { state in
            state.status = .coreLicenseActive
            state.trialExpiresAt = periodEnd
            state.snapshot = AccessStatusSnapshot(
                status: .coreLicenseActive,
                currentPeriodEnd: periodEnd,
                fetchedAt: bindingCompletionDate,
                deviceID: "test-device-id",
                sessionExpiresAt: sessionExpiry,
                deviceBindingVerifiedAt: bindingCompletionDate,
            )
            state.isComplete = true
            state.lastCompleteSyncAt = bindingCompletionDate
        }
        await store.receive(\.delegate.unlocked)
    }

    // MARK: - ACC-002-trusted-snapshot-fallback

    /// ACC-002-trusted-snapshot-fallback: 정확히 7일 지난 검증 결과는 fallback unlock에 사용할 수 없다.
    /// - 검증 내용: age == 604800인 active snapshot은 recoveryRequired만 전송한다.
    /// - 사전 조건: 현재 세션과 device binding proof는 있으나 fetchedAt이 정확히 7일 전이다.
    /// - 기대 결과: isComplete=false이며 snapshot을 entitlement 사실로 투영하지 않는다.
    func testTrustedSnapshotAtExactSevenDaysIsRejected() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now.addingTimeInterval(-604_800),
            sessionExpiresAt: now.addingTimeInterval(3600),
            deviceBindingVerifiedAt: now.addingTimeInterval(-604_800),
        )
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = now.addingTimeInterval(3600)
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(._cachedSnapshotRestored(generation: 1, snapshot: snapshot)) { state in
            state.status = .networkFailure
            state.errorMessage = "Network error. Please check your connection and try again."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNil(store.state.snapshot)
    }

    /// ACC-002-trusted-snapshot-fallback: 미래 검증 시각은 fallback unlock에 사용할 수 없다.
    /// - 검증 내용: fetchedAt이 현재보다 미래인 active snapshot은 recoveryRequired만 전송한다.
    /// - 사전 조건: 현재 세션과 device binding proof는 있으나 verification timestamp가 미래다.
    /// - 기대 결과: isComplete=false이며 unlock delegate가 발생하지 않는다.
    func testTrustedSnapshotWithFutureVerificationTimeIsRejected() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now.addingTimeInterval(1),
            sessionExpiresAt: now.addingTimeInterval(3600),
            deviceBindingVerifiedAt: now,
        )
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = now.addingTimeInterval(3600)
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(._cachedSnapshotRestored(generation: 1, snapshot: snapshot)) { state in
            state.status = .networkFailure
            state.errorMessage = "Network error. Please check your connection and try again."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertFalse(store.state.isComplete)
        XCTAssertEqual(store.state.status, .networkFailure)
        XCTAssertNil(store.state.snapshot)
    }

    /// ACC-002-trusted-snapshot-fallback: snapshot은 account session을 생성하거나 복원할 수 없다.
    /// - 검증 내용: signed-out state에서 active snapshot은 recoveryRequired만 전송한다.
    /// - 사전 조건: snapshot에는 옛 sessionExpiresAt이 있으나 reducer에는 현재 persisted session이 없다.
    /// - 기대 결과: hasAccountSession=false와 isComplete=false를 유지한다.
    func testTrustedSnapshotCannotRestoreAccountSession() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now,
            sessionExpiresAt: now.addingTimeInterval(3600),
            deviceBindingVerifiedAt: now,
        )
        var state = AccountAccessFeature.State()
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(._cachedSnapshotRestored(generation: 1, snapshot: snapshot)) { state in
            state.status = .networkFailure
            state.errorMessage = "Network error. Please check your connection and try again."
        }
        await store.receive(\.delegate.recoveryRequired)

        XCTAssertFalse(store.state.hasAccountSession)
        XCTAssertNil(store.state.sessionExpiresAt)
        XCTAssertFalse(store.state.isComplete)
    }

    /// ACC-002-trusted-snapshot-fallback: 신뢰 경계 위반은 각각 독립적으로 fallback unlock을 거부한다.
    /// - 검증 내용: legacy schema, binding/gateway/device proof, inactive status, period expiry를 각 행마다 거부한다.
    /// - 사전 조건: 나머지 predicate 입력은 모두 현재 session/device/environment와 일치한다.
    /// - 기대 결과: 모든 행이 network recovery만 남기고 entitlement unlock을 만들지 않는다.
    func testTrustedSnapshotRejectsEveryBoundaryViolation() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let binding = UUID()
        let gatewayBinding = GatewayEnvironment(rawValue: "").binding
        let validSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            currentPeriodEnd: now.addingTimeInterval(3600),
            fetchedAt: now,
            sessionBindingID: binding,
            gatewayBinding: gatewayBinding,
            deviceID: "test-device-id",
            deviceBindingVerifiedAt: now,
        )
        let violations: [(String, AccessStatusSnapshot)] = [
            ("legacy schema", AccessStatusSnapshot(
                schemaVersion: 0,
                status: validSnapshot.status,
                currentPeriodEnd: validSnapshot.currentPeriodEnd,
                fetchedAt: validSnapshot.fetchedAt,
                sessionBindingID: validSnapshot.sessionBindingID,
                gatewayBinding: validSnapshot.gatewayBinding,
                deviceID: validSnapshot.deviceID,
                deviceBindingVerifiedAt: validSnapshot.deviceBindingVerifiedAt,
            )),
            ("missing binding", AccessStatusSnapshot(
                status: validSnapshot.status,
                currentPeriodEnd: validSnapshot.currentPeriodEnd,
                fetchedAt: validSnapshot.fetchedAt,
                gatewayBinding: validSnapshot.gatewayBinding,
                deviceID: validSnapshot.deviceID,
                deviceBindingVerifiedAt: validSnapshot.deviceBindingVerifiedAt,
            )),
            ("gateway mismatch", AccessStatusSnapshot(
                status: validSnapshot.status,
                currentPeriodEnd: validSnapshot.currentPeriodEnd,
                fetchedAt: validSnapshot.fetchedAt,
                sessionBindingID: binding,
                gatewayBinding: "https://wrong.gateway",
                deviceID: validSnapshot.deviceID,
                deviceBindingVerifiedAt: validSnapshot.deviceBindingVerifiedAt,
            )),
            ("missing device proof", AccessStatusSnapshot(
                status: validSnapshot.status,
                currentPeriodEnd: validSnapshot.currentPeriodEnd,
                fetchedAt: validSnapshot.fetchedAt,
                sessionBindingID: binding,
                gatewayBinding: gatewayBinding,
            )),
            ("inactive entitlement", AccessStatusSnapshot(
                status: .revoked,
                currentPeriodEnd: validSnapshot.currentPeriodEnd,
                fetchedAt: validSnapshot.fetchedAt,
                sessionBindingID: binding,
                gatewayBinding: gatewayBinding,
                deviceID: validSnapshot.deviceID,
                deviceBindingVerifiedAt: validSnapshot.deviceBindingVerifiedAt,
            )),
            ("expired period", AccessStatusSnapshot(
                status: validSnapshot.status,
                currentPeriodEnd: now,
                fetchedAt: validSnapshot.fetchedAt,
                sessionBindingID: binding,
                gatewayBinding: gatewayBinding,
                deviceID: validSnapshot.deviceID,
                deviceBindingVerifiedAt: validSnapshot.deviceBindingVerifiedAt,
            )),
        ]

        for (name, snapshot) in violations {
            var state = AccountAccessFeature.State()
            state.hasAccountSession = true
            state.sessionExpiresAt = now.addingTimeInterval(7200)
            state.sessionBindingID = binding
            state.syncGeneration = 1
            let store = TestStore(initialState: state) {
                AccountAccessFeature()
            } withDependencies: {
                $0.date = .constant(now)
            }

            await store.send(._cachedSnapshotRestored(generation: 1, snapshot: snapshot)) { state in
                state.status = .networkFailure
                state.errorMessage = "Network error. Please check your connection and try again."
            }
            await store.receive(\.delegate.recoveryRequired)

            XCTAssertFalse(store.state.isComplete, name)
            XCTAssertNil(store.state.snapshot, name)
        }
    }

    /// ACC-002-trusted-snapshot-fallback: 완전한 현재 trusted snapshot은 entitlement만 투영한다.
    /// - 검증 내용: valid active proof가 unlock을 보내도 session expiry와 bootstrap은 현재 reducer 값을 유지한다.
    /// - 사전 조건: current binding/device/gateway와 일치하는 fresh active snapshot 및 이미 검증된 session state.
    /// - 기대 결과: isComplete=true지만 snapshot-derived auth/session/bootstrap 복원은 발생하지 않는다.
    func testTrustedSnapshotUnlockProjectsOnlyEntitlement() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let binding = UUID()
        let currentSessionExpiry = now.addingTimeInterval(7200)
        let snapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now,
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            sessionExpiresAt: now.addingTimeInterval(3600),
            deviceBindingVerifiedAt: now,
        )
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionExpiresAt = currentSessionExpiry
        state.sessionBindingID = binding
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(._cachedSnapshotRestored(generation: 1, snapshot: snapshot)) { state in
            state.status = .coreLicenseActive
            state.snapshot = snapshot
            state.isComplete = true
            state.errorMessage = "일시적인 네트워크 오류"
        }
        await store.receive(\.delegate.unlocked)

        XCTAssertTrue(store.state.hasAccountSession)
        XCTAssertEqual(store.state.sessionExpiresAt, currentSessionExpiry)
        XCTAssertFalse(store.state.didBootstrap)
    }

    /// ACC-002-trusted-snapshot-fallback: complete active sync와 성공한 device binding만 trusted snapshot을 저장한다.
    /// - 검증 내용: 저장된 snapshot에 current schema, session/gateway/device binding과 같은 verification timestamp가 기록된다.
    /// - 사전 조건: complete active sync와 `.bound` device outcome, 현재 session binding이 있다.
    /// - 기대 결과: active trusted snapshot 한 개가 저장되고 unlocked delegate가 전달된다.
    func testCompleteActiveSyncSavesDeviceBoundTrustedSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let binding = UUID()
        nonisolated(unsafe) var savedSnapshots: [AccessStatusSnapshot] = []
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionBindingID = binding
        state.sessionExpiresAt = now.addingTimeInterval(3600)
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { _, _ in nil },
                save: { snapshot, _, _, _ in savedSnapshots.append(snapshot) },
                remove: { _, _, _ in },
            )
        }
        let expectedSnapshot = AccessStatusSnapshot(
            status: .coreLicenseActive,
            fetchedAt: now,
            sessionBindingID: binding,
            gatewayBinding: GatewayEnvironment(rawValue: "").binding,
            deviceID: "test-device-id",
            sessionExpiresAt: now.addingTimeInterval(3600),
            deviceBindingVerifiedAt: now,
        )

        await store.send(._sessionSyncCompleted(
            generation: 1,
            binding: binding,
            result: .success(SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .complete,
                accessStatus: AccessStatusResponse(hasAccess: true, status: "active"),
                deviceBindingOutcome: .bound,
                connectedDeviceAvailability: .available,
            )),
        )) { state in
            state.status = .coreLicenseActive
            state.snapshot = expectedSnapshot
            state.isComplete = true
            state.lastCompleteSyncAt = now
        }
        await store.receive(\.delegate.unlocked)

        XCTAssertEqual(savedSnapshots, [expectedSnapshot])
    }

    /// ACC-002-trusted-snapshot-fallback: authoritative inactive sync는 이전 trusted snapshot을 제거한다.
    /// - 검증 내용: revoked response가 current state를 blocked로 갱신하고 generation-aware remove를 호출한다.
    /// - 사전 조건: session binding에 기존 trusted snapshot이 존재하며 complete sync가 revoked를 반환한다.
    /// - 기대 결과: snapshot 저장 없이 remove 한 번과 recoveryRequired delegate가 발생한다.
    func testAuthoritativeRevocationRemovesTrustedSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let binding = UUID()
        nonisolated(unsafe) var removeCalls: [(UUID?, GatewayEnvironment, Int)] = []
        var state = AccountAccessFeature.State()
        state.hasAccountSession = true
        state.sessionBindingID = binding
        state.syncGeneration = 1
        let store = TestStore(initialState: state) {
            AccountAccessFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.accessStatusSnapshotClient = AccessStatusSnapshotClient(
                load: { _, _ in nil },
                save: { _, _, _, _ in XCTFail("inactive sync must not save a trusted snapshot") },
                remove: { binding, environment, generation in removeCalls.append((binding, environment, generation)) },
            )
        }

        await store.send(._sessionSyncCompleted(
            generation: 1,
            binding: binding,
            result: .success(SessionSyncResult(
                sessionStatus: .unchanged,
                syncStatus: .complete,
                accessStatus: AccessStatusResponse(hasAccess: false, status: "revoked"),
                deviceBindingOutcome: .notAttempted,
                connectedDeviceAvailability: .available,
            )),
        )) { state in
            state.status = .revoked
            state.lastCompleteSyncAt = now
            state.errorMessage = "This license has been revoked."
        }
        await store.receive(\.delegate.recoveryRequired)
        await store.finish()

        XCTAssertEqual(removeCalls.count, 1)
        XCTAssertEqual(removeCalls.first?.0, binding)
        XCTAssertEqual(removeCalls.first?.1, GatewayEnvironment(rawValue: ""))
        XCTAssertEqual(removeCalls.first?.2, 1)
    }
}
