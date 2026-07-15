import AppKit
import ComposableArchitecture
import Foundation
import VoyagerShared

extension AccountAccessFeature {
    private struct CachedSnapshotRestoreContext {
        let generation: UInt64
        let binding: UUID?
        let currentStateSessionExpiry: Date?
        let currentDeviceID: String?
    }

    static var gatewayEnvironment: GatewayEnvironment {
        GatewayEnvironment(rawValue: EnvironmentLoader.stringValue(forKey: "PUBLIC_GATEWAY_URL") ?? "")
    }

    func sessionSyncEffect(
        intent: SessionSyncIntent,
        reason _: SyncReason,
        generation: UInt64,
        binding: UUID?,
        currentStateSessionExpiry: Date?,
    ) -> Effect<Action> {
        let retryDelays = intent == .refresh ? [Duration.seconds(5)] : Self.sessionSyncRetryDelays
        return .run { [
            authNetwork,
            continuousClock,
            date,
            deviceIdentityClient,
            retryDelays,
            sessionClient,
            snapshotClient,
        ] send in
            let device: DeviceBindingRequest
            do {
                device = try Self.sessionSyncDevice(deviceIdentityClient)
            } catch {
                await send(._sessionSyncCompleted(
                    generation: generation,
                    binding: binding,
                    result: .failure(.upstream(0)),
                ))
                return
            }

            let requestID = UUID().uuidString
            var retryIndex = 0
            while true {
                do {
                    let result = try await authNetwork.syncSession(
                        intent: intent,
                        device: device,
                        requestID: requestID,
                    )
                    await send(._sessionSyncCompleted(
                        generation: generation,
                        binding: binding,
                        result: .success(result),
                    ))
                    return
                } catch let error as SessionSyncError {
                    guard case .upstream = error else {
                        await send(._sessionSyncCompleted(
                            generation: generation,
                            binding: binding,
                            result: .failure(error),
                        ))
                        return
                    }
                    guard retryIndex < retryDelays.count else {
                        guard let action = await Self.cachedSnapshotRestoreAction(
                            snapshotClient,
                            sessionClient,
                            now: { date.now },
                            context: CachedSnapshotRestoreContext(
                                generation: generation,
                                binding: binding,
                                currentStateSessionExpiry: currentStateSessionExpiry,
                                currentDeviceID: device.deviceId,
                            ),
                        )
                        else { return }
                        await send(action)
                        return
                    }
                } catch {
                    guard !AuthNetworkClient.isCancellationError(error) else { return }
                    await send(._sessionSyncCompleted(
                        generation: generation,
                        binding: binding,
                        result: .failure(.upstream(0)),
                    ))
                    return
                }

                do {
                    try await continuousClock.sleep(for: retryDelays[retryIndex])
                } catch {
                    return
                }
                retryIndex += 1
            }
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    private static func sessionSyncDevice(_ deviceIdentityClient: DeviceIdentityClient) throws -> DeviceBindingRequest {
        try DeviceBindingRequest(
            deviceId: deviceIdentityClient.deviceId(),
            deviceName: Host.current().localizedName,
            appVersion: AppVersionInfo.shortVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        )
    }

    private static func cachedSnapshotRestoreAction(
        _ snapshotClient: AccessStatusSnapshotClient,
        _ sessionClient: AccountSessionClient,
        now: @Sendable () -> Date,
        context: CachedSnapshotRestoreContext,
    ) async -> Action? {
        let envelope = await snapshotClient.load(context.binding, gatewayEnvironment)
        guard !Task.isCancelled else { return nil }
        let persistedSession = try? await sessionClient.read(now())
        guard !Task.isCancelled else { return nil }
        let admission = TrustedFallbackSnapshotPolicy.validatedAdmission(.init(
            envelope: envelope,
            persistedSession: persistedSession,
            expectedBinding: context.binding,
            currentStateSessionExpiry: context.currentStateSessionExpiry,
            gatewayBinding: gatewayEnvironment.binding,
            currentDeviceID: context.currentDeviceID,
            now: now(),
        ))
        return ._cachedSnapshotRestored(
            generation: context.generation,
            binding: context.binding,
            snapshot: admission?.snapshot,
            validUntil: admission?.validUntil,
        )
    }

    func invalidateSessionSync(_ state: inout State) {
        state.syncGeneration += 1
        state.inFlightSyncReason = nil
    }

    func handleRefreshAccessTapped(_ state: inout State) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSignInInProgress, state.deviceBindingFailure == nil else {
            return .none
        }
        return revalidateCurrentPersistedSession(&state, reason: .manual)
    }

    func requestSessionSync(
        _ state: inout State,
        intent: SessionSyncIntent,
        reason: SyncReason,
    ) -> Effect<Action> {
        guard state.hasAccountSession, !state.isSessionExpired else {
            return .none
        }

        if !reason.bypassesFreshness,
           isFreshCompleteSessionSync(state)
        {
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
        return .run { [snapshotClient] send in
            let mutationGeneration = await snapshotClient.activate(binding, Self.gatewayEnvironment)
            guard !Task.isCancelled else { return }
            await send(._sessionSyncActivationCompleted(AccountAccessSessionSyncActivationCompletion(
                requestGeneration: requestGeneration,
                binding: binding,
                intent: intent,
                reason: reason,
                mutationGeneration: mutationGeneration,
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

        state.syncGeneration = max(state.syncGeneration, UInt64(clamping: completion.mutationGeneration))
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

        switch result {
        case let .success(result):
            return handleSessionSyncSuccess(&state, result: result)

        case let .failure(error):
            return handleSessionSyncFailure(&state, error: error)
        }
    }

    private func isFreshCompleteSessionSync(_ state: State) -> Bool {
        guard let lastCompleteSyncAt = state.lastCompleteSyncAt else {
            return false
        }

        let isRefreshDue = state.sessionExpiresAt.map { $0.timeIntervalSince(date()) <= 360 } ?? false
        return date().timeIntervalSince(lastCompleteSyncAt) < Self.sessionSyncFreshness && !isRefreshDue
    }

    private func handleSessionSyncSuccess(
        _ state: inout State,
        result: SessionSyncResult,
    ) -> Effect<Action> {
        if let sessionExpiresAt = result.sessionExpiresAt {
            state.sessionExpiresAt = sessionExpiresAt
            state.ttlTimerActive = true
        }
        let refreshDeadline: Effect<Action> = if result.sessionExpiresAt != nil {
            scheduleRefreshDeadline(&state)
        } else {
            .none
        }
        let accessStatus = result.accessStatus.toAccessStatus()
        let syncedAt = date()
        let snapshot = AccessStatusSnapshot.fetchResult(
            status: accessStatus,
            currentPeriodEnd: result.accessStatus.currentPeriodEnd,
            sessionExpiresAt: state.sessionExpiresAt,
            fetchedAt: syncedAt,
        )

        state.isSubmitting = false
        state.status = accessStatus
        state.trialExpiresAt = result.accessStatus.currentPeriodEnd
        state.fetchRetryCount = 0
        state.deviceBindingFailure = nil

        guard result.syncStatus == .complete else {
            state.isComplete = false
            state.snapshot = nil
            state.errorMessage = "Account verification could not be completed. Please try again."

            if accessStatus.isActive {
                return .merge(
                    handleDeviceBindingFailure(&state, snapshot: snapshot, error: .serverFailure),
                    refreshDeadline,
                )
            }

            return .merge(
                .send(.delegate(.recoveryRequired(.accessFailure(
                    error: .networkFailure,
                    sessionExpiresAt: state.sessionExpiresAt,
                )))),
                refreshDeadline,
            )
        }

        let completion = handleCompleteSessionSync(
            &state,
            accessStatus: accessStatus,
            snapshot: snapshot,
            syncedAt: syncedAt,
            deviceBindingOutcome: result.deviceBindingOutcome,
        )
        return .merge(completion, refreshDeadline)
    }

    private func handleCompleteSessionSync(
        _ state: inout State,
        accessStatus: AccessStatus,
        snapshot: AccessStatusSnapshot,
        syncedAt: Date,
        deviceBindingOutcome: SessionSyncDeviceBindingOutcome,
    ) -> Effect<Action> {
        state.lastCompleteSyncAt = syncedAt

        guard accessStatus.isActive else {
            state.snapshot = nil
            state.deviceBindingRetryCount = 0
            state.isComplete = false
            state.errorMessage = errorMessageForStatus(accessStatus)
            return .concatenate(
                removeTrustedSnapshot(
                    binding: state.sessionBindingID,
                    generation: Int(state.syncGeneration),
                ),
                .send(.delegate(.recoveryRequired(.snapshot(snapshot)))),
            )
        }

        switch deviceBindingOutcome {
        case .bound, .alreadyBound:
            guard let deviceID = try? deviceIdentityClient.deviceId(), !deviceID.isEmpty else {
                return handleDeviceBindingFailure(&state, snapshot: snapshot, error: .invalidDevicePayload)
            }
            let verifiedSnapshot = AccessStatusSnapshot.fetchResult(
                status: snapshot.status,
                currentPeriodEnd: snapshot.currentPeriodEnd,
                sessionExpiresAt: snapshot.sessionExpiresAt,
                fetchedAt: syncedAt,
                sessionBindingID: state.sessionBindingID,
                gatewayBinding: Self.gatewayEnvironment.binding,
                deviceID: deviceID,
                deviceBindingVerifiedAt: syncedAt,
            )
            state.snapshot = verifiedSnapshot
            state.deviceBindingRetryCount = 0
            state.isComplete = verifiedSnapshot.hasSession
            state.errorMessage = nil
            return saveVerifiedSnapshot(
                verifiedSnapshot,
                binding: state.sessionBindingID,
                generation: Int(state.syncGeneration),
            )

        case .deviceLimitReached:
            return .concatenate(
                removeTrustedSnapshot(
                    binding: state.sessionBindingID,
                    generation: Int(state.syncGeneration),
                ),
                handleDeviceBindingFailure(&state, snapshot: snapshot, error: .seatCapacityExceeded),
            )

        case .notAttempted:
            return handleDeviceBindingFailure(&state, snapshot: snapshot, error: .serverFailure)
        }
    }

    func handleDeviceBindingFailure(
        _ state: inout State,
        snapshot: AccessStatusSnapshot,
        error: DeviceBindingError,
    ) -> Effect<Action> {
        if error == .unauthorized {
            return .send(._sessionExpiredDetected)
        }

        state.isComplete = false
        state.snapshot = nil
        state.errorMessage = errorMessage(for: error)
        state.deviceBindingFailure = deviceBindingFailure(for: error)
        if state.deviceBindingFailure?.isRetryable == true {
            state.deviceBindingRetryCount += 1
        } else {
            state.deviceBindingRetryCount = 0
        }

        switch error {
        case .noActiveAccess:
            state.status = AccessStatus.none
            state.trialExpiresAt = nil
        case .networkFailure, .serverFailure:
            state.status = .networkFailure
        case .unauthorized, .seatCapacityExceeded, .invalidDevicePayload, .notConfigured, .decodingFailure,
             .unknownGatewayCode:
            break
        }

        return .send(.delegate(.recoveryRequired(.deviceBindingFailure(snapshot: snapshot, error: error))))
    }

    private func handleSessionSyncFailure(_ state: inout State, error: SessionSyncError) -> Effect<Action> {
        state.isSubmitting = false
        state.isComplete = false
        state.deviceBindingFailure = nil

        let accessError = accessError(for: error)
        state.errorMessage = errorMessage(for: accessError)

        if accessError == .unauthorized {
            return .send(._sessionExpiredDetected)
        }

        if accessError == .networkFailure {
            state.status = .networkFailure
        }

        switch accessError {
        case .notConfigured, .decodingFailure, .unknownGatewayCode:
            state.status = nil
            state.snapshot = nil
            state.trialExpiresAt = nil
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: accessError,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))

        case .networkFailure, .unauthorized:
            break
        }

        return .send(.delegate(.recoveryRequired(.accessFailure(
            error: accessError,
            sessionExpiresAt: state.sessionExpiresAt,
        ))))
    }

    private func accessError(for error: SessionSyncError) -> AccessError {
        switch error {
        case .invalidCredential:
            .unauthorized
        case .storageFailure, .capabilityMiss:
            .notConfigured
        case .upstream:
            .networkFailure
        }
    }

    private func removeTrustedSnapshot(
        binding: UUID?,
        generation: Int,
    ) -> Effect<Action> {
        .run { [snapshotClient] _ in
            guard !Task.isCancelled else { return }
            await snapshotClient.remove(binding, Self.gatewayEnvironment, generation)
        }
    }

    private func saveVerifiedSnapshot(
        _ snapshot: AccessStatusSnapshot,
        binding: UUID?,
        generation: Int,
    ) -> Effect<Action> {
        .run { [snapshotClient] send in
            do {
                try Task.checkCancellation()
                await snapshotClient.save(snapshot, binding, Self.gatewayEnvironment, generation)
                try Task.checkCancellation()
                await send(.delegate(.unlocked(snapshot)))
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .cancellable(id: CancelID.sessionSync, cancelInFlight: true)
    }

    func handleCachedSnapshotRestored(
        _ state: inout State,
        generation: UInt64,
        binding: UUID?,
        snapshot: AccessStatusSnapshot?,
        validUntil: Date?,
    ) -> Effect<Action> {
        guard
            generation == state.syncGeneration,
            binding == state.sessionBindingID,
            state.hasAccountSession,
            !state.isSessionExpired
        else {
            return .none
        }

        state.inFlightSyncReason = nil
        state.isSubmitting = false
        state.isComplete = false
        state.deviceBindingFailure = nil
        state.status = .networkFailure
        state.errorMessage = errorMessage(for: AccessError.networkFailure)

        let now = date.now
        guard
            let snapshot,
            let validUntil,
            validUntil.timeIntervalSinceReferenceDate.isFinite,
            validUntil > now,
            let currentSessionExpiry = state.sessionExpiresAt,
            currentSessionExpiry.timeIntervalSinceReferenceDate.isFinite,
            currentSessionExpiry > now
        else {
            state.snapshot = nil
            state.trialExpiresAt = nil
            return .send(.delegate(.recoveryRequired(.accessFailure(
                error: .networkFailure,
                sessionExpiresAt: state.sessionExpiresAt,
            ))))
        }

        state.status = snapshot.status
        state.snapshot = snapshot
        state.trialExpiresAt = snapshot.currentPeriodEnd
        state.isComplete = true
        state.errorMessage = "일시적인 네트워크 오류"
        return .send(.delegate(.unlocked(snapshot)))
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

    func errorMessage(for error: DeviceBindingError) -> String {
        switch error {
        case .unauthorized:
            "Session expired. Please sign in again."
        case .noActiveAccess:
            "No active license was found for this account. Check your account and try again."
        case .seatCapacityExceeded:
            "This license has reached its device limit. Manage devices or contact support."
        case .invalidDevicePayload:
            "Could not identify this Mac. Please try again or contact support."
        case .serverFailure, .networkFailure:
            "Could not bind this Mac. Please try again."
        case .notConfigured:
            "Access service is not configured."
        case .decodingFailure:
            "Failed to process the device binding response."
        case .unknownGatewayCode:
            "An unexpected device binding error occurred."
        }
    }

    func deviceBindingFailure(for error: DeviceBindingError) -> DeviceBindingFailure {
        switch error {
        case .noActiveAccess:
            .noActiveAccess
        case .seatCapacityExceeded:
            .seatCapacityExceeded
        case .networkFailure, .serverFailure:
            .retryable
        case .invalidDevicePayload:
            .invalidDevicePayload
        case .notConfigured, .decodingFailure, .unknownGatewayCode:
            .unknown
        case .unauthorized:
            .retryable
        }
    }

    func errorMessageForStatus(_ status: AccessStatus) -> String {
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
