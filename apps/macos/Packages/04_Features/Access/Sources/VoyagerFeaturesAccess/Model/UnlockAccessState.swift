import ComposableArchitecture
import Foundation

@ObservableState
public struct UnlockAccessState: Equatable {
    public var claimMode: AccessClaimMode = .licenseKey
    public var licenseKey: String = ""
    public var betaCode: String = ""
    public var status: AccessStatus?
    public var snapshot: AccessStatusSnapshot?
    public var isSubmitting: Bool = false
    public var errorMessage: String?
    public var isComplete: Bool = false
    public var trialExpiresAt: Date?

    public init() {}

    public var showsRetry: Bool {
        guard let status else { return false }
        return !status.isActive
    }

    public var canSubmit: Bool {
        switch claimMode {
        case .licenseKey: !licenseKey.isEmpty
        case .betaCode: !betaCode.isEmpty
        }
    }
}
