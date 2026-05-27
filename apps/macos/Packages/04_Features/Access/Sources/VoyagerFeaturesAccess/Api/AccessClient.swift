import ComposableArchitecture
import Foundation

public struct AccessClient: Sendable {
    public var restoreSession: @Sendable () async throws -> AccessSession?
    public var claimLicense: @Sendable (_ key: String) async throws -> AccessStatusResponse
    public var redeemBetaCode: @Sendable (_ code: String) async throws -> AccessStatusResponse
    public var fetchAccessStatus: @Sendable () async throws -> AccessStatusResponse
    public var signOut: @Sendable () async throws -> Void

    public nonisolated init(
        restoreSession: @escaping @Sendable () async throws -> AccessSession?,
        claimLicense: @escaping @Sendable (_ key: String) async throws -> AccessStatusResponse,
        redeemBetaCode: @escaping @Sendable (_ code: String) async throws -> AccessStatusResponse,
        fetchAccessStatus: @escaping @Sendable () async throws -> AccessStatusResponse,
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

public extension AccessClient {
    nonisolated static var mock: AccessClient {
        AccessClient(
            restoreSession: { nil },
            claimLicense: { key in
                try mockClaimLicense(key: key)
            },
            redeemBetaCode: { code in
                try mockRedeemBetaCode(code: code)
            },
            fetchAccessStatus: {
                AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
            },
            signOut: {},
        )
    }

    private static func mockClaimLicense(key: String) throws -> AccessStatusResponse {
        guard !key.isEmpty else {
            throw AccessError.missingInput
        }
        switch key {
        case "VOYAGER-CORE-VALID":
            return AccessStatusResponse(status: .coreLicenseActive, entitlements: [.coreLicense])
        case "VOYAGER-INTERNAL":
            return AccessStatusResponse(status: .internalTestActive, entitlements: [.internalTest])
        case "VOYAGER-EXPIRED":
            return AccessStatusResponse(status: .trialExpired, entitlements: [])
        case "VOYAGER-REVOKED":
            return AccessStatusResponse(status: .revoked, entitlements: [])
        case "VOYAGER-REFUNDED":
            return AccessStatusResponse(status: .refunded, entitlements: [])
        default:
            throw AccessError.invalidLicenseKey
        }
    }

    private static func mockRedeemBetaCode(code: String) throws -> AccessStatusResponse {
        guard !code.isEmpty else {
            throw AccessError.missingInput
        }
        switch code {
        case "VOYAGER-BETA-TRIAL":
            return AccessStatusResponse(
                status: .betaTrialActive,
                expiresAt: Date().addingTimeInterval(14 * 24 * 3600),
                entitlements: [.betaTrial],
            )
        default:
            throw AccessError.invalidLicenseKey
        }
    }
}

// MARK: - DependencyKey

extension AccessClient: DependencyKey {
    public nonisolated static var liveValue: AccessClient {
        AccessClient(
            restoreSession: { throw AccessError.notConfigured },
            claimLicense: { _ in throw AccessError.notConfigured },
            redeemBetaCode: { _ in throw AccessError.notConfigured },
            fetchAccessStatus: { throw AccessError.notConfigured },
            signOut: { throw AccessError.notConfigured },
        )
    }

    public nonisolated static var testValue: AccessClient { .mock }
    public nonisolated static var previewValue: AccessClient { .mock }
}

public extension DependencyValues {
    nonisolated var accessClient: AccessClient {
        get { self[AccessClient.self] }
        set { self[AccessClient.self] = newValue }
    }
}
