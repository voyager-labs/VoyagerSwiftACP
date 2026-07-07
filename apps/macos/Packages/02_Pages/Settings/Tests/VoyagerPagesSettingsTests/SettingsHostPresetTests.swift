@testable import VoyagerPagesSettings
import XCTest

final class SettingsHostPresetTests: XCTestCase {
    func testDefaultSandboxExposesAllAxes() {
        let scenario = SettingsHostPreset.defaultSandbox.scenario

        XCTAssertEqual(scenario.accountAuth, .signedIn)
        XCTAssertEqual(scenario.aiConnection, .connected)
        XCTAssertEqual(scenario.permissions, .allGranted)
        XCTAssertEqual(scenario.persistence, .clean)
        XCTAssertEqual(scenario.failureLatency, .none)
    }

    func testAccountAuthPresetsMapToDistinctAxes() {
        XCTAssertEqual(SettingsHostPreset.signedOut.scenario.accountAuth, .signedOut)
        XCTAssertEqual(SettingsHostPreset.signedIn.scenario.accountAuth, .signedIn)
        XCTAssertEqual(SettingsHostPreset.authExpired.scenario.accountAuth, .authExpired)
        XCTAssertEqual(SettingsHostPreset.aiNotConfigured.scenario.aiConnection, .notConfigured)
    }

    func testAccountLoadedIsTrueOnlyForSignedIn() {
        for preset in SettingsHostPreset.allCases {
            XCTAssertEqual(
                preset.scenario.accountLoaded,
                preset.scenario.accountAuth == .signedIn,
                "Unexpected accountLoaded for \(preset)",
            )
        }
    }

    func testSessionLapseIsTrueOnlyForAuthExpired() {
        for preset in SettingsHostPreset.allCases {
            XCTAssertEqual(
                preset.scenario.sessionLapse,
                preset.scenario.accountAuth == .authExpired,
                "Unexpected sessionLapse for \(preset)",
            )
        }
    }

    func testSignedOutAndAuthExpiredRemainSemanticallyDistinct() {
        let signedOut = SettingsHostPreset.allCases.first { $0.scenario.accountAuth == .signedOut }
        let authExpired = SettingsHostPreset.allCases.first { $0.scenario.accountAuth == .authExpired }

        XCTAssertNotNil(signedOut)
        XCTAssertNotNil(authExpired)

        if let signedOut, let authExpired {
            XCTAssertFalse(signedOut.scenario.accountLoaded)
            XCTAssertFalse(signedOut.scenario.sessionLapse)
            XCTAssertFalse(authExpired.scenario.accountLoaded)
            XCTAssertTrue(authExpired.scenario.sessionLapse)
        }
    }

    func testParseFallsBackToDefaultSandboxForInvalidValue() {
        XCTAssertEqual(SettingsHostPreset.parse("notARealPreset"), .defaultSandbox)
    }

    func testParseFallsBackToDefaultSandboxForNil() {
        XCTAssertEqual(SettingsHostPreset.parse(nil), .defaultSandbox)
    }

    func testPresetsAreEquatableAndModelIsSendable() {
        func assertSendable(_: (some Sendable).Type) {}

        assertSendable(SettingsHostScenario.self)
        assertSendable(SettingsHostPreset.self)

        XCTAssertEqual(SettingsHostPreset.defaultSandbox, SettingsHostPreset.defaultSandbox)
        XCTAssertNotEqual(SettingsHostPreset.defaultSandbox, SettingsHostPreset.signedIn)
    }

    // MARK: - Full-Access Gate Scenario Realignment

    func testDefaultSandboxRepresentsFullAccessState() {
        let scenario = SettingsHostPreset.defaultSandbox.scenario

        XCTAssertEqual(
            scenario.accountAuth,
            .signedIn,
            "defaultSandbox must be signed_in under full-access gate policy",
        )
        XCTAssertTrue(
            scenario.entitlementActive,
            "defaultSandbox must mark entitlement_active under full-access gate policy",
        )
        XCTAssertFalse(
            scenario.requiresFloatingDebugPanel,
            "scenario must not require a floating debug panel",
        )
    }

    func testPresetListIncludesExplicitNamedFullAccessScenario() {
        XCTAssertTrue(
            SettingsHostPreset.allCases.contains(.fullAccess),
            "Preset list must include an explicit .fullAccess scenario",
        )
    }

    func testBlockedAndExpiredPresetsAreClassifiedAsNegativeGateScenarios() {
        let negativePresets: [SettingsHostPreset] = [
            .authExpired,
            .accountError,
            .permissionsDenied,
            .errorStates,
        ]

        for preset in negativePresets {
            XCTAssertEqual(
                preset.scenario.gateClassification,
                .negative,
                "\(preset) must be classified as a negative gate scenario",
            )
        }
    }

    // MARK: - Session Expiry Axis

    func testSignedInPresetsExposeFutureSessionExpiry() {
        let signedInPresets: [SettingsHostPreset] = [
            .defaultSandbox,
            .fullAccess,
            .signedIn,
            .permissionsAllGranted,
            .aiNotConfigured,
            .aiConnected,
            .aiConnectionError,
            .permissionsDenied,
        ]

        for preset in signedInPresets {
            XCTAssertEqual(
                preset.scenario.accountAuth,
                .signedIn,
                "\(preset) must be signed-in to map to a future session expiry",
            )
            XCTAssertEqual(
                preset.scenario.sessionExpiresAt,
                .sessionExpiryFuture,
                "\(preset) must expose the deterministic future session expiry",
            )
        }
    }

    func testAuthExpiredPresetExposesPastSessionExpiry() {
        XCTAssertEqual(SettingsHostPreset.authExpired.scenario.accountAuth, .authExpired)
        XCTAssertEqual(
            SettingsHostPreset.authExpired.scenario.sessionExpiresAt,
            .sessionExpiryPast,
            "authExpired must expose the deterministic past session expiry",
        )
    }

    func testSignedOutPresetExposesNilSessionExpiry() {
        XCTAssertEqual(SettingsHostPreset.signedOut.scenario.accountAuth, .signedOut)
        XCTAssertNil(
            SettingsHostPreset.signedOut.scenario.sessionExpiresAt,
            "signedOut must expose nil session expiry",
        )
    }

    func testNonSessionAccountStatesExposeNilSessionExpiry() {
        let nonSessionPresets: [SettingsHostPreset] = [
            .signedOut,
            .accountLoading,
            .accountError,
            .errorStates,
        ]

        for preset in nonSessionPresets {
            XCTAssertNil(
                preset.scenario.sessionExpiresAt,
                "\(preset) must expose nil session expiry (no valid session)",
            )
        }
    }

    func testSessionAxisIsSemanticallyDistinctAcrossAuthStates() {
        let signedIn = SettingsHostPreset.signedIn.scenario
        let authExpired = SettingsHostPreset.authExpired.scenario
        let signedOut = SettingsHostPreset.signedOut.scenario

        XCTAssertNotNil(signedIn.sessionExpiresAt)
        XCTAssertNotNil(authExpired.sessionExpiresAt)
        XCTAssertNil(signedOut.sessionExpiresAt)

        if let signedInExpiry = signedIn.sessionExpiresAt,
           let authExpiredExpiry = authExpired.sessionExpiresAt
        {
            XCTAssertGreaterThan(signedInExpiry, authExpiredExpiry)
            XCTAssertEqual(signedInExpiry, .sessionExpiryFuture)
            XCTAssertEqual(authExpiredExpiry, .sessionExpiryPast)
        }
    }

    // MARK: - Task 16: hostPreset launch hydration (AccountAccess session axis)

    /// Task 16: signedIn preset이 hostPreset factory를 거쳐 AccountAccess 상태로
    /// session/entitlement 사실을 전파하는지 검증. SettingsHost가 AppLifecycle 없이도
    /// launch 직후 signed-in UI를 렌더링하려면 factory에서 didBootstrap/hasAccountSession/
    /// sessionExpiresAt/status를 함께 prehydrate해야 한다.
    func testHostPresetSignedInHydratesAccountAccessSession() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.signedIn.scenario)

        XCTAssertTrue(state.accountSettings.access.didBootstrap, "signedIn preset은 launch hydration 완료 상태")
        XCTAssertTrue(state.accountSettings.access.hasAccountSession, "signedIn preset은 session 존재")
        XCTAssertEqual(
            state.accountSettings.access.sessionExpiresAt,
            .sessionExpiryFuture,
            "signedIn preset sessionExpiresAt은 미래 deterministic 시각",
        )
        XCTAssertEqual(
            state.accountSettings.access.status,
            .coreLicenseActive,
            "signedIn preset entitlement 축은 coreLicenseActive",
        )
        XCTAssertEqual(state.accessStatus, .coreLicenseActive)
        XCTAssertNotNil(state.accountSettings.access.snapshot)
        XCTAssertEqual(state.accountSettings.access.snapshot?.sessionExpiresAt, .sessionExpiryFuture)
        XCTAssertFalse(state.accountSettings.access.isSessionExpired)
    }

    /// Task 16: signedOut preset은 가짜 세션을 주입하지 않아야 한다.
    /// sessionExpiresAt == nil이면 hasAccountSession=false를 유지하며,
    /// didBootstrap=true로 onAppear 중복 read를 차단한다.
    func testHostPresetSignedOutHasNoFakeSession() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.signedOut.scenario)

        XCTAssertTrue(state.accountSettings.access.didBootstrap, "signedOut도 launch hydration 완료 상태")
        XCTAssertFalse(state.accountSettings.access.hasAccountSession, "signedOut은 session 없음")
        XCTAssertNil(state.accountSettings.access.sessionExpiresAt, "signedOut은 session fact 없음")
        XCTAssertNil(state.accountSettings.access.status, "signedOut은 status 부재 (entitlementUnknown derive)")
        XCTAssertEqual(state.accessStatus, .none)
        XCTAssertNil(state.accountSettings.access.snapshot, "session 없는 시나리오는 snapshot도 없음")
    }

    /// Task 16: authExpired preset은 session fact(과거 시각)를 전파하되
    /// entitlement 축은 trialExpired로 유지한다. session 축과 entitlement 축이
    /// 독립적임을 증명 — session 존재여부와 상관없이 entitlement는 만료 상태.
    func testHostPresetAuthExpiredPropagatesSessionFactWithExpiredEntitlement() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.authExpired.scenario)

        XCTAssertTrue(state.accountSettings.access.didBootstrap)
        XCTAssertTrue(
            state.accountSettings.access.hasAccountSession,
            "authExpired는 session fact 존재 (과거 시각이라도 session 축은 참)",
        )
        XCTAssertEqual(
            state.accountSettings.access.sessionExpiresAt,
            .sessionExpiryPast,
            "authExpired sessionExpiresAt은 과거 deterministic 시각",
        )
        XCTAssertEqual(
            state.accountSettings.access.status,
            .trialExpired,
            "authExpired entitlement 축은 trialExpired (session과 독립)",
        )
        XCTAssertEqual(state.accessStatus, .trialExpired)
        XCTAssertNotNil(state.accountSettings.access.snapshot)
        XCTAssertEqual(state.accountSettings.access.snapshot?.sessionExpiresAt, .sessionExpiryPast)
        XCTAssertEqual(state.accountSettings.access.snapshot?.status, .trialExpired)
    }

    /// Task 16: loading/error preset은 session 없이 status=nil(부재) 상태로 남는다.
    /// 이들 시나리오는 sessionExpiresAt == nil이므로 prehydrate 대상에서 제외된다.
    /// `accountSettings.access.status`를 nil로 두어 Settings가 entitlementUnknown을
    /// derive하도록 한다 (.some(.none)이면 entitlementInactive로 잘못 파생됨).
    func testHostPresetNonSessionPresetsLeaveAccountAccessWithoutSession() {
        let nonSessionPresets: [SettingsHostPreset] = [.accountLoading, .accountError, .errorStates]

        for preset in nonSessionPresets {
            let state = SettingsState.hostPreset(for: preset.scenario)

            XCTAssertTrue(
                state.accountSettings.access.didBootstrap,
                "\(preset)도 launch hydration 완료 상태 (onAppear 중복 차단)",
            )
            XCTAssertFalse(
                state.accountSettings.access.hasAccountSession,
                "\(preset)은 session 없음",
            )
            XCTAssertNil(state.accountSettings.access.sessionExpiresAt)
            XCTAssertNil(state.accountSettings.access.snapshot)
            XCTAssertNil(state.accountSettings.access.status, "\(preset)은 status 부재 (entitlementUnknown derive)")
        }
    }

    /// Task 16: hostPreset은 effect 기반 상태(ttlTimerActive/fetchGeneration)를
    /// 건드리지 않는다. 이들는 런타임 effect(TTL 타이머 시작, fetch 무효화) 소유이므로
    /// 초기 상태에서는 기본값을 유지해야 한다. mock launch가 실제 effect를 시작하지 않음을 보장.
    func testHostPresetDoesNotStartRuntimeEffects() {
        let signedIn = SettingsState.hostPreset(for: SettingsHostPreset.signedIn.scenario)
        let authExpired = SettingsState.hostPreset(for: SettingsHostPreset.authExpired.scenario)

        for state in [signedIn, authExpired] {
            XCTAssertFalse(
                state.accountSettings.access.ttlTimerActive,
                "hostPreset은 TTL 타이머를 시작하지 않음 (런타임 effect 소유)",
            )
            XCTAssertEqual(
                state.accountSettings.access.fetchGeneration,
                0,
                "hostPreset은 fetchGeneration 무효화하지 않음",
            )
        }
    }
}
