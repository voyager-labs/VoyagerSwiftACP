@testable import SettingsHost
import VoyagerPagesSettings
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

    // MARK: - Account presentation projection

    func testHostPresetSignedInUsesPresentationFacts() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.signedIn.scenario)

        XCTAssertTrue(state.accountSettings.presentation.hasAccountSession)
        XCTAssertEqual(state.accountSettings.presentation.accessStatus, .coreLicenseActive)
        XCTAssertEqual(state.accessStatus, .coreLicenseActive)
        XCTAssertEqual(state.accountSettings.setAuthState, .signedIn)
        XCTAssertEqual(state.accountSettings.setEntitlementState, .entitlementActive)
    }

    func testHostPresetSignedOutUsesNoSessionFact() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.signedOut.scenario)

        XCTAssertFalse(state.accountSettings.presentation.hasAccountSession)
        XCTAssertNil(state.accountSettings.presentation.accessStatus)
        XCTAssertEqual(state.accessStatus, .none)
        XCTAssertEqual(state.accountSettings.setAuthState, .signedOut)
        XCTAssertEqual(state.accountSettings.setEntitlementState, .entitlementUnknown)
    }

    func testHostPresetAuthExpiredUsesInactivePresentationFacts() {
        let state = SettingsState.hostPreset(for: SettingsHostPreset.authExpired.scenario)

        XCTAssertTrue(state.accountSettings.presentation.hasAccountSession)
        XCTAssertEqual(state.accountSettings.presentation.accessStatus, .trialExpired)
        XCTAssertEqual(state.accessStatus, .trialExpired)
        XCTAssertEqual(state.accountSettings.setEntitlementState, .entitlementInactive)
    }

    func testHostPresetNonSessionPresetsUseEmptyPresentationFacts() {
        let nonSessionPresets: [SettingsHostPreset] = [.accountLoading, .accountError, .errorStates]

        for preset in nonSessionPresets {
            let state = SettingsState.hostPreset(for: preset.scenario)

            XCTAssertFalse(state.accountSettings.presentation.hasAccountSession)
            XCTAssertNil(state.accountSettings.presentation.accessStatus)
            XCTAssertEqual(state.accountSettings.setEntitlementState, .entitlementUnknown)
        }
    }
}
