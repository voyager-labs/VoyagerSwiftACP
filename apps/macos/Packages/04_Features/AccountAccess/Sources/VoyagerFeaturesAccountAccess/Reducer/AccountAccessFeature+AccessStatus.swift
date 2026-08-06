import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

extension AccountAccessFeature {
    static var gatewayEnvironment: GatewayEnvironment {
        GatewayEnvironment(rawValue: EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL") ?? "")
    }

    func sessionSyncEffect(
        intent: SessionSyncIntent,
        reason _: SyncReason,
        generation: UInt64,
        binding: UUID?,
        currentStateSessionExpiry _: Date?,
    ) -> Effect<Action> {
        .run { [authNetwork, deviceIdentityClient] send in
            let device: DeviceBindingRequest
            do {
                device = try DeviceBindingRequest(
                    deviceId: deviceIdentityClient.deviceId(),
                    deviceName: Host.current().localizedName,
                    appVersion: AppVersionInfo.shortVersion,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                )
            } catch {
                await send(._sessionSyncCompleted(
                    generation: generation,
                    binding: binding,
                    result: .failure(.upstream(0)),
                ))
                return
            }

            do {
                let result = try await authNetwork.syncSession(
                    intent: intent,
                    device: device,
                    requestID: UUID().uuidString,
                )
                await send(._sessionSyncCompleted(
                    generation: generation,
                    binding: binding,
                    result: .success(result),
                ))
            } catch is CancellationError {
                return
            } catch let error as SessionSyncError {
                await send(._sessionSyncCompleted(
                    generation: generation,
                    binding: binding,
                    result: .failure(error),
                ))
            } catch {
                await send(._sessionSyncCompleted(
                    generation: generation,
                    binding: binding,
                    result: .failure(.upstream(0)),
                ))
            }
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    func invalidateSessionSync(_ state: inout State) {
        state.syncGeneration += 1
        state.inFlightSyncReason = nil
    }

    func requestSessionSync(
        _ state: inout State,
        intent: SessionSyncIntent,
        reason: SyncReason,
    ) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSessionExpired else {
            return .none
        }
        if let inFlightReason = state.inFlightSyncReason,
           reason.priority <= inFlightReason.priority
        {
            return .none
        }

        state.syncGeneration += 1
        state.inFlightSyncReason = reason
        state.isSubmitting = true
        state.errorMessage = nil
        let requestGeneration = state.syncGeneration
        let binding = state.sessionBindingID
        return .run { send in
            guard !Task.isCancelled else { return }
            await send(._sessionSyncActivationCompleted(AccountAccessSessionSyncActivationCompletion(
                requestGeneration: requestGeneration,
                binding: binding,
                intent: intent,
                reason: reason,
            )))
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    func handleSessionSyncActivationCompleted(
        _ state: inout State,
        completion: AccountAccessSessionSyncActivationCompletion,
    ) -> Effect<Action> {
        guard completion.requestGeneration == state.syncGeneration,
              completion.binding == state.sessionBindingID,
              state.hasAccountSession,
              !state.isSessionExpired
        else {
            return .none
        }

        state.syncGeneration = max(state.syncGeneration, completion.requestGeneration)
        return sessionSyncEffect(
            intent: completion.intent,
            reason: completion.reason,
            generation: state.syncGeneration,
            binding: completion.binding,
            currentStateSessionExpiry: state.sessionExpiresAt,
        )
    }

    func handleSessionSyncCompleted(
        _ state: inout State,
        generation: UInt64,
        binding: UUID?,
        result: Result<SessionSyncResult, SessionSyncError>,
    ) -> Effect<Action> {
        guard generation == state.syncGeneration, binding == state.sessionBindingID else {
            return .none
        }

        state.inFlightSyncReason = nil
        state.isSubmitting = false

        switch result {
        case let .success(result):
            if let sessionExpiresAt = result.sessionExpiresAt {
                state.sessionExpiresAt = sessionExpiresAt
                state.ttlTimerActive = true
            }
            if result.syncStatus == .complete {
                state.lastCompleteSyncAt = date()
            }
            state.errorMessage = nil
            return .none

        case let .failure(error):
            guard case .invalidCredential = error else {
                state.errorMessage = errorMessage(for: accessError(for: error))
                return .none
            }
            return .send(._sessionExpiredDetected)
        }
    }

    private func accessError(for error: SessionSyncError) -> AccessError {
        switch error {
        case .invalidCredential:
            .unauthorized
        case .storageFailure, .capabilityMiss, .invalidResponse:
            .notConfigured
        case .upstream:
            .networkFailure
        }
    }

    func errorMessage(for error: AccessError) -> String {
        switch error {
        case .networkFailure: "Network error. Please check your connection and try again."
        case .notConfigured: "Access service is not configured."
        case .decodingFailure: "Failed to process the response."
        case .unauthorized: "Session expired. Please sign in again."
        case .unknownGatewayCode: "An unexpected error occurred."
        }
    }
}
