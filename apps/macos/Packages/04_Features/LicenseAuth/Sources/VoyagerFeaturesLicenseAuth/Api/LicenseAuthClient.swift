import ComposableArchitecture
import Foundation

public struct LicenseAuthClient: Sendable {
    public var restoreSession: @Sendable () async throws -> LicenseAuthSession?
    public var claimLicense: @Sendable (_ key: String) async throws -> LicenseAuthStatusResponse
    public var redeemBetaCode: @Sendable (_ code: String) async throws -> LicenseAuthStatusResponse
    public var fetchAccessStatus: @Sendable () async throws -> LicenseAuthStatusResponse
    public var signOut: @Sendable () async throws -> Void

    public nonisolated init(
        restoreSession: @escaping @Sendable () async throws -> LicenseAuthSession?,
        claimLicense: @escaping @Sendable (_ key: String) async throws -> LicenseAuthStatusResponse,
        redeemBetaCode: @escaping @Sendable (_ code: String) async throws -> LicenseAuthStatusResponse,
        fetchAccessStatus: @escaping @Sendable () async throws -> LicenseAuthStatusResponse,
        signOut: @escaping @Sendable () async throws -> Void,
    ) {
        self.restoreSession = restoreSession
        self.claimLicense = claimLicense
        self.redeemBetaCode = redeemBetaCode
        self.fetchAccessStatus = fetchAccessStatus
        self.signOut = signOut
    }
}

// MARK: - Mock

public extension LicenseAuthClient {
    nonisolated static var mock: LicenseAuthClient {
        LicenseAuthClient(
            restoreSession: { nil },
            claimLicense: { key in
                try mockClaimLicense(key: key)
            },
            redeemBetaCode: { code in
                try mockRedeemBetaCode(code: code)
            },
            fetchAccessStatus: {
                LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
            },
            signOut: {},
        )
    }

    private static func mockClaimLicense(key: String) throws -> LicenseAuthStatusResponse {
        guard !key.isEmpty else {
            throw LicenseAuthError.missingInput
        }
        switch key {
        case "VOYAGER-CORE-VALID":
            return LicenseAuthStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
        case "VOYAGER-INTERNAL":
            return LicenseAuthStatusResponse(status: .internalTestActive, entitlements: [.internalTest])
        case "VOYAGER-EXPIRED":
            return LicenseAuthStatusResponse(status: .trialExpired, entitlements: [])
        case "VOYAGER-REVOKED":
            return LicenseAuthStatusResponse(status: .revoked, entitlements: [])
        case "VOYAGER-REFUNDED":
            return LicenseAuthStatusResponse(status: .refunded, entitlements: [])
        default:
            throw LicenseAuthError.invalidLicenseKey
        }
    }

    private static func mockRedeemBetaCode(code: String) throws -> LicenseAuthStatusResponse {
        guard !code.isEmpty else {
            throw LicenseAuthError.missingInput
        }
        switch code {
        case "VOYAGER-BETA-TRIAL":
            return LicenseAuthStatusResponse(
                status: .betaTrialActive,
                expiresAt: Date().addingTimeInterval(14 * 24 * 3600),
                entitlements: [.betaTrial],
            )
        default:
            throw LicenseAuthError.invalidLicenseKey
        }
    }
}

// MARK: - DependencyKey

extension LicenseAuthClient: DependencyKey {
    public nonisolated static var liveValue: LicenseAuthClient {
        LicenseAuthClient(
            restoreSession: { throw LicenseAuthError.notConfigured },
            claimLicense: { _ in throw LicenseAuthError.notConfigured },
            redeemBetaCode: { _ in throw LicenseAuthError.notConfigured },
            fetchAccessStatus: { throw LicenseAuthError.notConfigured },
            signOut: { throw LicenseAuthError.notConfigured },
        )
    }

    public nonisolated static var testValue: LicenseAuthClient { .mock }
    public nonisolated static var previewValue: LicenseAuthClient { .mock }
}

public extension DependencyValues {
    nonisolated var licenseAuthClient: LicenseAuthClient {
        get { self[LicenseAuthClient.self] }
        set { self[LicenseAuthClient.self] = newValue }
    }
}
