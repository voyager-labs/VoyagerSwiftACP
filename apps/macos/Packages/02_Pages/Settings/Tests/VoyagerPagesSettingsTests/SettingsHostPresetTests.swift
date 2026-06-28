@testable import VoyagerPagesSettings
import XCTest

final class SettingsHostPresetTests: XCTestCase {
    func testDefaultSandboxExposesAllAxes() {
        let scenario = SettingsHostPreset.defaultSandbox.scenario

        XCTAssertEqual(scenario.accountAuth, .signedOut)
        XCTAssertEqual(scenario.aiConnection, .notConfigured)
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
}
