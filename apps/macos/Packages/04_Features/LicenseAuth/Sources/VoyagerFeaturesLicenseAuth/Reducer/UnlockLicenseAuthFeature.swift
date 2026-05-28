import ComposableArchitecture
import Foundation

@Reducer
public struct UnlockLicenseAuthFeature {
    public typealias State = UnlockLicenseAuthState
    public typealias Action = UnlockLicenseAuthAction

    @Dependency(\.licenseAuthClient)
    var licenseAuthClient

    @Dependency(\.licenseAuthStatusSnapshotClient)
    var snapshotClient

    @Dependency(\.date)
    var date

    private enum CancelID {
        static let claim = "unlockLicenseAuthClaim"
        static let fetchStatus = "unlockLicenseAuthFetchStatus"
    }

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return handleOnAppear(&state)

            case let .claimModeChanged(mode):
                state.claimMode = mode
                state.errorMessage = nil
                return .none

            case let .licenseKeyChanged(key):
                state.licenseKey = key
                state.errorMessage = nil
                return .none

            case let .betaCodeChanged(code):
                state.betaCode = code
                state.errorMessage = nil
                return .none

            case .submitTapped, .retryTapped:
                return handleSubmit(&state)

            case let .claimResponse(result):
                return handleClaimResponse(&state, result: result)

            case let .licenseAuthStatusResponse(result):
                return handleLicenseAuthStatusResponse(&state, result: result)

            case .delegate:
                return .none
            }
        }
    }

    private func handleOnAppear(_ state: inout State) -> Effect<Action> {
        guard state.snapshot != nil || state.isComplete else { return .none }

        return .run { [licenseAuthClient] send in
            let result: Result<LicenseAuthStatusResponse, LicenseAuthError>
            do {
                let response = try await licenseAuthClient.fetchAccessStatus()
                result = .success(response)
            } catch let error as LicenseAuthError {
                result = .failure(error)
            } catch {
                result = .failure(.networkFailure)
            }
            await send(.licenseAuthStatusResponse(result))
        }
        .cancellable(id: CancelID.fetchStatus, cancelInFlight: true)
    }

    private func handleSubmit(_ state: inout State) -> Effect<Action> {
        guard state.canSubmit else {
            state.errorMessage = "Please enter a license key or beta code."
            return .none
        }

        state.isSubmitting = true
        state.errorMessage = nil
        state.isComplete = false

        let mode = state.claimMode
        let licenseKey = state.licenseKey
        let betaCode = state.betaCode

        return .run { [licenseAuthClient] send in
            let result: Result<LicenseAuthStatusResponse, LicenseAuthError>
            do {
                let response: LicenseAuthStatusResponse = switch mode {
                case .licenseKey:
                    try await licenseAuthClient.claimLicense(licenseKey)
                case .betaCode:
                    try await licenseAuthClient.redeemBetaCode(betaCode)
                }
                result = .success(response)
            } catch let error as LicenseAuthError {
                result = .failure(error)
            } catch {
                result = .failure(.networkFailure)
            }
            await send(.claimResponse(result))
        }
        .cancellable(id: CancelID.claim, cancelInFlight: true)
    }

    private func handleClaimResponse(
        _ state: inout State,
        result: Result<LicenseAuthStatusResponse, LicenseAuthError>,
    ) -> Effect<Action> {
        state.isSubmitting = false

        switch result {
        case let .success(response):
            state.status = response.status
            state.trialExpiresAt = response.expiresAt

            let snapshot = LicenseAuthStatusSnapshot(
                status: response.status,
                expiresAt: response.expiresAt,
                entitlements: response.entitlements,
                fetchedAt: date(),
            )
            state.snapshot = snapshot

            if response.status.isActive {
                state.isComplete = true
                state.errorMessage = nil
                return .run { [snapshotClient] send in
                    await snapshotClient.save(snapshot)
                    await send(.delegate(.unlocked(snapshot)))
                }
            } else {
                state.isComplete = false
                state.errorMessage = errorMessageForStatus(response.status)
                return .run { [snapshotClient] _ in
                    await snapshotClient.save(snapshot)
                }
            }

        case let .failure(error):
            state.isComplete = false
            state.errorMessage = errorMessage(for: error)
            if error == .networkFailure {
                state.status = .networkFailure
            }
            return .none
        }
    }

    private func handleLicenseAuthStatusResponse(
        _ state: inout State,
        result: Result<LicenseAuthStatusResponse, LicenseAuthError>,
    ) -> Effect<Action> {
        switch result {
        case let .success(response):
            state.status = response.status
            state.trialExpiresAt = response.expiresAt

            let snapshot = LicenseAuthStatusSnapshot(
                status: response.status,
                expiresAt: response.expiresAt,
                entitlements: response.entitlements,
                fetchedAt: date(),
            )
            state.snapshot = snapshot

            if response.status.isActive {
                state.isComplete = true
                state.errorMessage = nil
                return .run { [snapshotClient] send in
                    await snapshotClient.save(snapshot)
                    await send(.delegate(.unlocked(snapshot)))
                }
            } else {
                state.isComplete = false
                state.errorMessage = errorMessageForStatus(response.status)
                return .run { [snapshotClient] _ in
                    await snapshotClient.save(snapshot)
                }
            }

        case let .failure(error):
            state.isComplete = false
            state.errorMessage = errorMessage(for: error)
            if error == .networkFailure {
                state.status = .networkFailure
            }
            return .none
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func errorMessage(for error: LicenseAuthError) -> String {
        switch error {
        case .missingInput: "Please enter a license key or beta code."
        case .invalidLicenseKey: "The license key is invalid."
        case .licenseAlreadyUsed: "This license key has already been used."
        case .licenseRevoked: "This license has been revoked."
        case .licenseRefunded: "This license has been refunded."
        case .betaCodeAlreadyRedeemed: "This beta code has already been redeemed."
        case .betaCodeExpired: "This beta code has expired."
        case .networkFailure: "Network error. Please check your connection and try again."
        case .notConfigured: "Access service is not configured."
        case .decodingFailure: "Failed to process the response."
        case .unknownGatewayCode: "An unexpected error occurred."
        }
    }

    private func errorMessageForStatus(_ status: LicenseAuthStatus) -> String {
        switch status {
        case .trialExpired: "This trial has expired."
        case .revoked: "This license has been revoked."
        case .refunded: "This license has been refunded."
        case .networkFailure: "Network error. Please check your connection and try again."
        case .none: "Access denied."
        default: "An unexpected status was returned."
        }
    }
}
