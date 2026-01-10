import ComposableArchitecture
import Foundation

struct BetaAccessClient: Sendable {
    var verify: @Sendable (_ email: String, _ token: String, _ scenarioIndex: Int) async -> BetaAccessVerificationResult

    nonisolated init(
        verify: @escaping @Sendable (_ email: String, _ token: String, _ scenarioIndex: Int) async
            -> BetaAccessVerificationResult,
    ) {
        self.verify = verify
    }
}

extension BetaAccessClient {
    nonisolated static func mockResult(for scenarioIndex: Int) -> BetaAccessVerificationResult {
        switch scenarioIndex % 4 {
        case 0:
            BetaAccessVerificationResult(status: .notActive, reason: .mismatch)
        case 1:
            BetaAccessVerificationResult(status: .notActive, reason: .tokenAlreadyRegistered)
        case 2:
            BetaAccessVerificationResult(status: .checkFailed)
        default:
            BetaAccessVerificationResult(status: .active)
        }
    }

    nonisolated static var mock: BetaAccessClient {
        BetaAccessClient(verify: { _, _, scenarioIndex in
            BetaAccessClient.mockResult(for: scenarioIndex)
        })
    }
}

extension BetaAccessClient: DependencyKey {
    nonisolated static var liveValue: BetaAccessClient { .mock }
    nonisolated static var testValue: BetaAccessClient { .mock }
    nonisolated static var previewValue: BetaAccessClient { .mock }
}

extension DependencyValues {
    nonisolated var betaAccessClient: BetaAccessClient {
        get { self[BetaAccessClient.self] }
        set { self[BetaAccessClient.self] = newValue }
    }
}
